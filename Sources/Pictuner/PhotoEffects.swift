import CoreImage

/// Queue-owned spatial and creative effects shared by overview, source-detail, and export.
final class PhotoEffects {
    private lazy var contrastKernel = CIColorKernel(source: """
    kernel vec4 localContrast(__sample original, __sample blurred, float amount, float midtones) {
        vec4 p = unpremultiply(original);
        vec4 b = unpremultiply(blurred);
        vec3 luma = vec3(0.2126, 0.7152, 0.0722);
        float y = dot(p.rgb, luma);
        float weight = mix(1.0, 4.0*clamp(y,0.0,1.0)*(1.0-clamp(y,0.0,1.0)), midtones);
        float detail = dot(p.rgb-b.rgb, luma)*amount*weight;
        return premultiply(vec4(max(vec3(0.0), p.rgb+detail),p.a));
    }
    """)
    private lazy var gradingKernel = CIColorKernel(source: """
    kernel vec4 grade(__sample pixel, vec3 shadows, vec3 highlights, vec3 settings) {
        vec4 p = unpremultiply(pixel);
        vec3 luma = vec3(0.2126,0.7152,0.0722);
        float y = clamp(dot(p.rgb,luma),0.0,1.0);
        float hi = smoothstep(0.15+settings.z*0.2,0.85+settings.z*0.2,y);
        vec3 shadowChroma = shadows-vec3(dot(shadows,luma));
        vec3 highlightChroma = highlights-vec3(dot(highlights,luma));
        vec3 tint = (shadowChroma*settings.x*(1.0-hi)+highlightChroma*settings.y*hi)*0.35*4.0*y*(1.0-y);
        return premultiply(vec4(max(vec3(0.0),p.rgb+tint),p.a));
    }
    """)
    private lazy var grainKernel = CIColorKernel(source: """
    float hash(vec2 p) { return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453); }
    kernel vec4 grain(__sample pixel, float amount, float size, float sourceScale) {
        vec4 p = unpremultiply(pixel);
        vec2 uv = destCoord()/max(sourceScale*size,0.001);
        vec2 cell = floor(uv);
        vec2 f = fract(uv); f = f*f*(3.0-2.0*f);
        float a = mix(hash(cell),hash(cell+vec2(1.0,0.0)),f.x);
        float b = mix(hash(cell+vec2(0.0,1.0)),hash(cell+vec2(1.0,1.0)),f.x);
        float noise = (mix(a,b,f.y)-0.5)*amount*0.3*min(1.0,sourceScale*size);
        return premultiply(vec4(max(vec3(0.0),p.rgb+noise),p.a));
    }
    """)

    func localContrast(_ image: CIImage, amount: Double, radius: Double, midtones: Bool) throws -> CIImage {
        guard amount != 0 else { return image }
        let blurred = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.1, radius)])
        guard let result = contrastKernel?.apply(extent: image.extent, arguments: [image, blurred, amount, midtones ? 1.0 : 0.0]) else {
            throw PictunerError.message("Local contrast could not be rendered.")
        }
        return result
    }

    func grade(_ image: CIImage, _ a: Adjustments) throws -> CIImage {
        guard a.shadowTint != 0 || a.highlightTint != 0 else { return image }
        guard let result = gradingKernel?.apply(extent: image.extent, arguments: [image, color(a.shadowHue), color(a.highlightHue), CIVector(x: a.shadowTint, y: a.highlightTint, z: a.gradingBalance)]) else {
            throw PictunerError.message("Color grading could not be rendered.")
        }
        return result
    }

    func grain(_ image: CIImage, _ a: Adjustments, sourceScale: Double) throws -> CIImage {
        guard a.grain > 0 else { return image }
        guard let result = grainKernel?.apply(extent: image.extent, arguments: [image, a.grain, a.grainSize, sourceScale]) else {
            throw PictunerError.message("Film grain could not be rendered.")
        }
        return result
    }

    private func color(_ degrees: Double) -> CIVector {
        let h = (degrees.truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)/60
        let x = 1-abs(h.truncatingRemainder(dividingBy: 2)-1)
        switch h {
        case ..<1: return CIVector(x: 1, y: x, z: 0)
        case ..<2: return CIVector(x: x, y: 1, z: 0)
        case ..<3: return CIVector(x: 0, y: 1, z: x)
        case ..<4: return CIVector(x: 0, y: x, z: 1)
        case ..<5: return CIVector(x: x, y: 0, z: 1)
        default: return CIVector(x: 1, y: 0, z: x)
        }
    }

    /// Source-pixel halo for chained neighborhood filters; three radii bound Gaussian support.
    static func padding(_ a: Adjustments, sourceSize: CGSize, minimumScale: Double = 1) -> Double {
        let short = min(sourceSize.width, sourceSize.height)
        return ceil((a.noiseReduction > 0 ? 8/max(0.001, minimumScale) : 0)
            + (a.clarity != 0 ? short*0.012*3 : 0)
            + (a.texture != 0 ? short*0.0015*3 : 0)
            + (a.sharpening > 0 ? a.sharpeningRadius*3 : 0)
            + (a.glow > 0 ? short*a.glowRadius*3 : 0))
    }
}
