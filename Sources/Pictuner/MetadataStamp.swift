import Foundation
import CoreImage
import CoreText

/// A small text bitmap, composited in full-image coordinates even for zoom-region rendering.
/// Never allocates a source-sized bitmap and never changes the original/sampling branches.
final class MetadataStamp {
    private var cachedLines: [String] = []
    private var cachedBitmap: CGImage?
    static func frame(labelSize: CGSize, in size: CGSize, settings: MetadataOverlay) -> CGRect {
        let margin = min(size.width, size.height)*settings.margin
        let scale = min(1, (size.width-2*margin)/labelSize.width, (size.height-2*margin)/labelSize.height)
        let width = labelSize.width*scale, height = labelSize.height*scale
        let x: Double
        switch settings.position {
        case .topLeft, .bottomLeft: x = margin
        case .topCenter, .bottomCenter: x = (size.width-width)/2
        case .topRight, .bottomRight: x = size.width-margin-width
        }
        let top = [.topLeft, .topCenter, .topRight].contains(settings.position)
        return CGRect(x: x, y: top ? size.height-margin-height : margin, width: width, height: height)
    }

    func apply(to input: CIImage, metadata: PhotoMetadata, settings: MetadataOverlay, referenceSize: CGSize? = nil) throws -> CIImage {
        let lines = settings.lines(for: metadata)
        guard !lines.isEmpty else { return input }
        let size = referenceSize ?? input.extent.size
        let desiredFont = min(size.width, size.height)*settings.textSize
        let fontSize = 192.0
        let bitmap: CGImage
        if cachedLines == lines, let cachedBitmap { bitmap = cachedBitmap }
        else {
            bitmap = try makeLabel(lines, metadata: metadata, fontSize: fontSize)
            cachedLines = lines; cachedBitmap = bitmap
        }
        let width = Double(bitmap.width), height = Double(bitmap.height)
        let desiredSize = CGSize(width: width*desiredFont/fontSize, height: height*desiredFont/fontSize)
        let frame = Self.frame(labelSize: desiredSize, in: size, settings: settings)
        let label = CIImage(cgImage: bitmap)
            .transformed(by: CGAffineTransform(scaleX: frame.width/width, y: frame.height/height))
            .transformed(by: CGAffineTransform(translationX: frame.minX, y: frame.minY))
        return label.composited(over: input).cropped(to: input.extent)
    }

    private func makeLabel(_ lines: [String], metadata: PhotoMetadata, fontSize: Double) throws -> CGImage {
        let primary = CTFontCreateUIFontForLanguage(.system, fontSize, nil)!
        let secondary = CTFontCreateWithName("Menlo" as CFString, fontSize*0.72, nil)
        let textLines = lines.enumerated().map { index, text -> CTLine in
            let isCoordinate = text == metadata.coordinates
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): isCoordinate ? secondary : primary,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: index == 0 ? 1 : 0.85)
            ]
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        }
        var ascents = [CGFloat](), descents = [CGFloat]()
        let widths = textLines.map { line -> Double in
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            ascents.append(ascent); descents.append(descent)
            return width
        }
        let px = fontSize*0.65, py = fontSize*0.5, gap = fontSize*0.28
        let width = ceil((widths.max() ?? 0)+2*px)
        let height = ceil(zip(ascents, descents).reduce(0) { $0+$1.0+$1.1 }+gap*Double(lines.count-1)+2*py)
        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PictunerError.message("The date and GPS label could not be rendered.")
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 0.035, alpha: 0.58))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: fontSize*0.35, cornerHeight: fontSize*0.35, transform: nil))
        context.fillPath()
        var top = height-py
        for index in textLines.indices {
            context.textPosition = CGPoint(x: px, y: top-ascents[index])
            CTLineDraw(textLines[index], context)
            top -= ascents[index]+descents[index]+gap
        }
        guard let bitmap = context.makeImage() else { throw PictunerError.message("The date and GPS label could not be rendered.") }
        return bitmap
    }
}
