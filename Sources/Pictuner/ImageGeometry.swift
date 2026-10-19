import Foundation

/// Normalized coordinates in the rotated/mirrored image, with a bottom-left origin.
struct CropRegion: Codable, Equatable, Sendable {
    var x = 0.0
    var y = 0.0
    var width = 1.0
    var height = 1.0
    static let full = CropRegion()
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init() {}
    init(_ rect: CGRect) {
        let rect = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
        x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
    }
    private enum CodingKeys: String, CodingKey { case x, y, width, height }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decode(Double.self, forKey: .x); y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width); height = try c.decode(Double.self, forKey: .height)
        guard [x, y, width, height].allSatisfy(\.isFinite), x >= 0, y >= 0, width > 0, height > 0,
              x+width <= 1.000001, y+height <= 1.000001 else {
            throw DecodingError.dataCorruptedError(forKey: .width, in: c, debugDescription: "Invalid crop bounds")
        }
    }
    func pixelRect(in size: CGSize) -> CGRect {
        // Round boundaries once at source resolution; preview/export share exactly these pixels.
        let left = min(size.width-1, max(0, (x*size.width).rounded()))
        let bottom = min(size.height-1, max(0, (y*size.height).rounded()))
        let right = max(left+1, min(size.width, ((x+width)*size.width).rounded()))
        let top = max(bottom+1, min(size.height, ((y+height)*size.height).rounded()))
        return CGRect(x: left, y: bottom, width: right-left, height: top-bottom)
    }
    func moved(by delta: CGSize) -> CropRegion {
        CropRegion(CGRect(x: min(1-width, max(0, x+delta.width)), y: min(1-height, max(0, y+delta.height)), width: width, height: height))
    }
    func fitted(aspect: Double, source: CGSize) -> CropRegion {
        guard source.width > 0, source.height > 0 else { return self }
        let ratio = aspect*source.height/source.width
        var w = width, h = height
        if w/h > ratio { w = h*ratio } else { h = w/ratio }
        return CropRegion(CGRect(x: x+(width-w)/2, y: y+(height-h)/2, width: w, height: h))
    }
    /// Opposite corner stays fixed; an optional ratio is expressed in normalized coordinates.
    static func between(anchor: CGPoint, point: CGPoint, ratio: Double? = nil) -> CropRegion {
        let dx = point.x > anchor.x || (point.x == anchor.x && anchor.x < 0.5) ? 1.0 : -1.0
        let dy = point.y > anchor.y || (point.y == anchor.y && anchor.y < 0.5) ? 1.0 : -1.0
        let maxW = dx > 0 ? 1-anchor.x : anchor.x, maxH = dy > 0 ? 1-anchor.y : anchor.y
        var w = min(maxW, max(0.01, abs(point.x-anchor.x)))
        var h = min(maxH, max(0.01, abs(point.y-anchor.y)))
        if let ratio {
            if w/h > ratio { h = w/ratio } else { w = h*ratio }
            let fit = min(1, maxW/max(w, 0.000001), maxH/max(h, 0.000001))
            w *= fit; h *= fit
        }
        return CropRegion(CGRect(x: dx > 0 ? anchor.x : anchor.x-w, y: dy > 0 ? anchor.y : anchor.y-h, width: w, height: h))
    }
}

struct ImageGeometry: Codable, Equatable, Sendable {
    var quarterTurns = 0 // clockwise, before mirroring
    var flipHorizontal = false
    var flipVertical = false
    var crop: CropRegion?

    mutating func rotate(clockwise: Bool) {
        let direction = (clockwise ? 1 : -1) * (flipHorizontal != flipVertical ? -1 : 1)
        quarterTurns = (quarterTurns+direction+4)%4
        if let c = crop {
            crop = clockwise ? CropRegion(CGRect(x: c.y, y: 1-c.x-c.width, width: c.height, height: c.width))
                : CropRegion(CGRect(x: 1-c.y-c.height, y: c.x, width: c.height, height: c.width))
        }
    }
    mutating func flip(horizontal: Bool) {
        if horizontal { flipHorizontal.toggle() } else { flipVertical.toggle() }
        if let c = crop {
            crop = CropRegion(CGRect(x: horizontal ? 1-c.x-c.width : c.x, y: horizontal ? c.y : 1-c.y-c.height, width: c.width, height: c.height))
        }
    }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free = "Free", original = "Original", square = "1:1", fourThree = "4:3", threeTwo = "3:2", wide = "16:9"
    case threeFour = "3:4", twoThree = "2:3", portrait = "9:16"
    var id: String { rawValue }
    func ratio(source: CGSize) -> Double? {
        switch self {
        case .free: return nil
        case .original: return source.height > 0 ? source.width/source.height : nil
        case .square: return 1
        case .fourThree: return 4/3
        case .threeTwo: return 3/2
        case .wide: return 16/9
        case .threeFour: return 3/4
        case .twoThree: return 2/3
        case .portrait: return 9/16
        }
    }
}
