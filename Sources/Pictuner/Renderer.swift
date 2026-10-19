import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO

struct HistogramData: Sendable {
    var red = [Double](repeating: 0, count: 256)
    var green = [Double](repeating: 0, count: 256)
    var blue = [Double](repeating: 0, count: 256)
    var luminance = [Double](repeating: 0, count: 256)
}

struct PreviewResult {
    let original: CGImage
    let edited: CGImage
    let samplingImage: CGImage
    let mask: CGImage?
    let clipping: CGImage
    let originalClipping: CGImage
    let histogram: HistogramData
    let originalHistogram: HistogramData
    let sourceSize: CGSize
}

/// Owned by the render queue; export uses its own instance on a separate serial queue.
final class Renderer {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    lazy var context = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace, .cacheIntermediates: false])
    private var cachedURL: URL?
    private var cachedDate: Date?
    private var cachedImage: CIImage?
    private struct PreparedPreview {
        let baseline: CIImage
        let original: CGImage
        let histogram: HistogramData
        let clipping: CGImage
    }
    private var preparedPreviews: [Double: PreparedPreview] = [:]

    private static let hsvFunctions = """
    vec3 toHSV(vec3 c) {
        float hi = max(c.r, max(c.g, c.b));
        float lo = min(c.r, min(c.g, c.b));
        float d = hi - lo;
        float h = 0.0;
        if (d > 0.00001) {
            if (hi == c.r) h = mod((c.g-c.b)/d, 6.0);
            else if (hi == c.g) h = (c.b-c.r)/d + 2.0;
            else h = (c.r-c.g)/d + 4.0;
        }
        return vec3(fract(h/6.0 + 1.0), hi > 0.00001 ? d/hi : 0.0, hi);
    }
    """
    private lazy var selectiveKernel: CIColorKernel? = CIColorKernel(source: Self.hsvFunctions + """
    kernel vec4 selective(__sample p, vec3 selected, vec4 range, vec3 effect, float maskOnly) {
        vec3 hsv = toHSV(clamp(p.rgb, 0.0, 1.0));
        float dh = abs(hsv.x-selected.x);
        dh = min(dh, 1.0-dh);
        float softness = max(range.w, 0.001);
        float h = 1.0-smoothstep(range.x, range.x+softness*0.5, dh);
        float s = 1.0-smoothstep(range.y, range.y+softness, abs(hsv.y-selected.y));
        float v = 1.0-smoothstep(range.z, range.z+softness, abs(hsv.z-selected.z));
        float weight = h*s*v;
        if (maskOnly > 0.5) return vec4(vec3(weight), 1.0);
        float gray = dot(p.rgb, vec3(0.2126,0.7152,0.0722));
        vec3 inside = mix(vec3(gray), p.rgb, effect.x) * exp2(effect.y);
        vec3 outside = mix(vec3(gray), p.rgb, effect.z);
        return vec4(mix(outside, inside, weight), p.a);
    }
    """)
    private lazy var vignetteKernel = CIColorKernel(source: """
    kernel vec4 vignette(__sample p, vec2 size, float strength, float radius, float softness) {
        vec2 uv = (destCoord()-size*0.5)/(min(size.x,size.y)*0.5);
        float edge = smoothstep(radius, radius+max(softness,0.01), length(uv));
        return vec4(p.rgb*(1.0-strength*edge),p.a);
    }
    """)
    private lazy var clippingKernel = CIColorKernel(source: """
    kernel vec4 clipping(__sample p) {
        if (max(p.r,max(p.g,p.b)) >= 0.999) return vec4(1.0,0.16,0.1,0.7);
        if (min(p.r,min(p.g,p.b)) <= 0.001) return vec4(0.1,0.4,1.0,0.7);
        return vec4(0.0);
    }
    """)

    func load(_ url: URL) throws -> CIImage {
        let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if url == cachedURL, date == cachedDate, let cachedImage { return cachedImage }
        let image: CIImage?
        if ImageFiles.isRAW(url) {
            // CIRAWFilter develops sensor data, rather than loading the embedded JPEG.
            image = CIRAWFilter(imageURL: url)?.outputImage
        } else {
            image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
        }
        guard let image, !image.extent.isEmpty, !image.extent.isInfinite else {
            throw PictunerError.message("Cannot decode \(url.lastPathComponent). RAW compatibility depends on this Mac's camera decoder.")
        }
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        cachedURL = url; cachedDate = date; cachedImage = normalized
        preparedPreviews.removeAll()
        return normalized
    }

    func beforeSelective(_ input: CIImage, _ a: Adjustments) -> CIImage {
        var image = input
        if a.temperature != 0 || a.tint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500 + a.temperature, y: a.tint), "inputTargetNeutral": CIVector(x: 6500, y: 0)])
        }
        if a.exposure != 0 { image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: a.exposure]) }
        if a.brightness != 0 || a.contrast != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: a.brightness, kCIInputContrastKey: a.contrast])
        }
        if a.highlights != 1 || a.shadows != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": a.highlights, "inputShadowAmount": a.shadows])
        }
        if a.hue != 0 { image = image.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: a.hue * .pi / 180]) }
        if a.saturation != 1 { image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: a.saturation]) }
        return image
    }

    func selective(_ input: CIImage, _ s: SelectiveColor, mask: Bool = false) throws -> CIImage {
        guard let kernel = selectiveKernel,
              let image = kernel.apply(extent: input.extent, arguments: [input, CIVector(x: s.hue, y: s.saturation, z: s.brightness), CIVector(x: s.hueRange, y: s.saturationTolerance, z: s.brightnessTolerance, w: s.softness), CIVector(x: s.selectedSaturation, y: s.selectedBrightness, z: s.outsideSaturation), mask ? 1.0 : 0.0]) else {
            throw PictunerError.message("The selective-color shader could not be initialized on this Mac.")
        }
        return image
    }

    func render(_ input: CIImage, adjustments a: Adjustments) throws -> CIImage {
        var image = beforeSelective(input, a)
        if a.selective.enabled { image = try selective(image, a.selective) }
        if a.monochrome > 0 { image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1-a.monochrome]) }
        if a.sepia > 0 { image = image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: a.sepia]) }
        if a.vignette > 0 {
            guard let filtered = vignetteKernel?.apply(extent: image.extent, arguments: [image, CIVector(x: input.extent.width, y: input.extent.height), a.vignette, a.vignetteRadius, a.vignetteSoftness]) else {
                throw PictunerError.message("The vignette shader could not be initialized.")
            }
            image = filtered
        }
        return image.cropped(to: input.extent)
    }

    func resize(_ image: CIImage, longEdge: Double) -> CIImage {
        let scale = min(1, longEdge / max(image.extent.width, image.extent.height))
        guard scale < 1 else { return image }
        return image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]).cropped(to: CGRect(x: 0, y: 0, width: floor(image.extent.width*scale), height: floor(image.extent.height*scale)))
    }

    func cgImage(_ image: CIImage) throws -> CGImage {
        guard let result = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw PictunerError.message("The image could not be rendered.")
        }
        return result
    }

    private func clipping(_ image: CGImage) throws -> CGImage {
        let input = CIImage(cgImage: image)
        guard let clipped = clippingKernel?.apply(extent: input.extent, arguments: [input]) else {
            throw PictunerError.message("Clipping preview could not be rendered.")
        }
        return try cgImage(clipped)
    }

    func preview(url: URL, adjustments: Adjustments, longEdge: Double = 1800) throws -> PreviewResult {
        let source = try load(url)
        let prepared: PreparedPreview
        if let cached = preparedPreviews[longEdge] { prepared = cached }
        else {
            let resized = resize(source, longEdge: longEdge)
            let width = Int(resized.extent.width), height = Int(resized.extent.height)
            // Materialize RAW development once per resolution. Half floats preserve values
            // above display white for exposure/highlight recovery in subsequent adjustments.
            let extendedSRGB = CGColorSpace(name: CGColorSpace.extendedSRGB)!
            var pixels = Data(count: width * height * 8)
            pixels.withUnsafeMutableBytes { bytes in
                context.render(resized, toBitmap: bytes.baseAddress!, rowBytes: width * 8, bounds: resized.extent, format: .RGBAh, colorSpace: extendedSRGB)
            }
            let baseline = CIImage(bitmapData: pixels, bytesPerRow: width * 8, size: CGSize(width: width, height: height), format: .RGBAh, colorSpace: extendedSRGB)
            let original = try cgImage(baseline)
            prepared = PreparedPreview(baseline: baseline, original: original, histogram: histogram(CIImage(cgImage: original)), clipping: try clipping(original))
            // Bound this cache to the active photo's interactive and settled resolutions.
            if preparedPreviews.count >= 2 { preparedPreviews.removeAll() }
            preparedPreviews[longEdge] = prepared
        }
        let baseline = prepared.baseline
        let edited = try render(baseline, adjustments: adjustments)
        let final = try cgImage(edited)
        let sampling = try cgImage(beforeSelective(baseline, adjustments))
        let mask = adjustments.selective.enabled ? try cgImage(selective(beforeSelective(baseline, adjustments), adjustments.selective, mask: true)) : nil
        return PreviewResult(original: prepared.original, edited: final, samplingImage: sampling, mask: mask, clipping: try clipping(final), originalClipping: prepared.clipping, histogram: histogram(CIImage(cgImage: final)), originalHistogram: prepared.histogram, sourceSize: source.extent.size)
    }

    func histogram(_ image: CIImage) -> HistogramData {
        let small = resize(image, longEdge: 256)
        let width = max(1, Int(small.extent.width)), height = max(1, Int(small.extent.height))
        var bytes = [UInt8](repeating: 0, count: width*height*4)
        context.render(small, toBitmap: &bytes, rowBytes: width*4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: colorSpace)
        var result = HistogramData()
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let r = Int(bytes[offset]), g = Int(bytes[offset+1]), b = Int(bytes[offset+2])
            result.red[r] += 1; result.green[g] += 1; result.blue[b] += 1
            let luma = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
            result.luminance[Int(luma.rounded())] += 1
        }
        return result
    }

    static func sample(_ image: CGImage, at point: CGPoint) -> (Double, Double, Double) {
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        var pixel = [UInt8](repeating: 0, count: 4)
        let x = min(image.width-1, max(0, Int(point.x*Double(image.width))))
        let y = min(image.height-1, max(0, Int((1-point.y)*Double(image.height))))
        context.render(CIImage(cgImage: image), toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let r = Double(pixel[0])/255, g = Double(pixel[1])/255, b = Double(pixel[2])/255
        let hi = max(r, g, b), lo = min(r, g, b), delta = hi-lo
        var h = 0.0
        if delta > 0.00001 {
            if hi == r { h = (g-b)/delta }
            else if hi == g { h = (b-r)/delta+2 }
            else { h = (r-g)/delta+4 }
            h = (h/6+1).truncatingRemainder(dividingBy: 1)
        }
        return (h, hi > 0 ? delta/hi : 0, hi)
    }
}
