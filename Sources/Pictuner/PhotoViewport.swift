import Foundation

/// A scale is display pixels per source pixel (100% = 1). Centers use bottom-left image coordinates.
struct PhotoViewport: Equatable {
    var scale: Double? = nil // nil means Fit, which follows the canvas size.
    var center = CGPoint(x: 0.5, y: 0.5)
    var label: String { scale.map { "\(Int(($0 * 100).rounded()))%" } ?? "Fit" }

    func resolvedScale(source: CGSize, canvas: CGSize, backing: Double) -> Double {
        guard source.width > 0, source.height > 0 else { return 1 }
        return scale ?? max(0.001, min(max(1, canvas.width-56)*backing/source.width, max(1, canvas.height-56)*backing/source.height))
    }

    func imageRect(source: CGSize, canvas: CGSize, backing: Double) -> CGRect {
        let pixelsPerPoint = max(1, backing)
        let factor = resolvedScale(source: source, canvas: canvas, backing: pixelsPerPoint)/pixelsPerPoint
        let size = CGSize(width: source.width*factor, height: source.height*factor)
        return CGRect(x: canvas.width/2-center.x*size.width, y: canvas.height/2-center.y*size.height, width: size.width, height: size.height)
    }

    mutating func constrain(source: CGSize, canvas: CGSize, backing: Double) {
        let size = imageRect(source: source, canvas: canvas, backing: backing).size
        func clamped(_ value: Double, image: Double, view: Double) -> Double {
            guard image > view, image > 0 else { return 0.5 }
            let margin = view/(2*image)
            return min(1-margin, max(margin, value))
        }
        center.x = clamped(center.x, image: size.width, view: canvas.width)
        center.y = clamped(center.y, image: size.height, view: canvas.height)
    }

    mutating func setScale(_ value: Double?, anchor: CGPoint? = nil, source: CGSize, canvas: CGSize, backing: Double) {
        if value == nil { self = PhotoViewport(); return }
        let point = anchor ?? CGPoint(x: canvas.width/2, y: canvas.height/2)
        let before = imageRect(source: source, canvas: canvas, backing: backing)
        let unit = CGPoint(x: (point.x-before.minX)/max(1, before.width), y: (point.y-before.minY)/max(1, before.height))
        scale = min(8, max(0.05, value!))
        let after = imageRect(source: source, canvas: canvas, backing: backing)
        center = CGPoint(x: unit.x-(point.x-canvas.width/2)/max(1, after.width), y: unit.y-(point.y-canvas.height/2)/max(1, after.height))
        constrain(source: source, canvas: canvas, backing: backing)
    }

    mutating func pan(by delta: CGSize, source: CGSize, canvas: CGSize, backing: Double) {
        let rect = imageRect(source: source, canvas: canvas, backing: backing)
        center.x -= delta.width/max(1, rect.width)
        center.y -= delta.height/max(1, rect.height)
        constrain(source: source, canvas: canvas, backing: backing)
    }

    func detailViewport(source: CGSize, canvas: CGSize, backing: Double) -> DetailViewport? {
        guard source.width > 0, source.height > 0, canvas.width > 0, canvas.height > 0 else { return nil }
        let actualScale = resolvedScale(source: source, canvas: canvas, backing: backing)
        let overviewScale = min(1, 1800/max(source.width, source.height))
        // Request detail whenever the overview would need upscaling on the physical display,
        // including Fit on a large Retina screen. Small source images already fit in the overview.
        guard actualScale > overviewScale * 1.01, overviewScale < 1 else { return nil }
        let rect = imageRect(source: source, canvas: canvas, backing: backing)
        let visible = rect.intersection(CGRect(origin: .zero, size: canvas))
        guard !visible.isNull, !visible.isEmpty else { return nil }
        let region = CGRect(x: (visible.minX-rect.minX)/rect.width, y: (visible.minY-rect.minY)/rect.height, width: visible.width/rect.width, height: visible.height/rect.height)
        return DetailViewport(region: region, scale: min(1, actualScale))
    }
}

struct DetailViewport: Equatable {
    let region: CGRect // normalized, bottom-left source coordinates
    let scale: Double // output pixels per source pixel, capped at native resolution
}
