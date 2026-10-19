import SwiftUI
import AppKit

struct PreviewCanvas: NSViewRepresentable {
    let image: CGImage?
    let clipping: CGImage?
    let detailImage: CGImage?
    let detailClipping: CGImage?
    let detailRegion: CGRect?
    let sourceSize: CGSize
    let identity: String?
    let viewport: PhotoViewport
    let picking: Bool
    let crop: CropRegion?
    let cropRatio: Double?
    let cropChanged: (CropRegion) -> Void
    let cropFinished: (Bool) -> Void
    let viewportChanged: (PhotoViewport, CGSize, Double) -> Void
    let geometryChanged: (CGSize, Double) -> Void
    let compare: (Bool) -> Void
    let navigate: (Int) -> Void
    let sample: (CGPoint) -> Void

    func makeNSView(context: Context) -> PhotoCanvas {
        let view = PhotoCanvas()
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: PhotoCanvas, context: Context) {
        if view.identity != identity {
            view.identity = identity
            if identity != nil {
                DispatchQueue.main.async { [weak view] in
                    guard let view else { return }
                    view.window?.makeFirstResponder(view)
                }
            }
        }
        view.image = image; view.clipping = clipping
        view.detailImage = detailImage; view.detailClipping = detailClipping; view.detailRegion = detailRegion
        view.sourceSize = sourceSize; view.viewport = viewport
        if (view.crop == nil) != (crop == nil) {
            view.window?.invalidateCursorRects(for: view)
            if crop != nil {
                DispatchQueue.main.async { [weak view] in if let view { view.window?.makeFirstResponder(view) } }
            }
        }
        view.crop = crop; view.cropRatio = cropRatio
        view.cropChanged = cropChanged; view.cropFinished = cropFinished
        view.toolTip = crop == nil ? nil : "Drag corners to resize; drag inside to move. Return to apply · Esc to cancel"
        if view.picking != picking { view.picking = picking; view.window?.invalidateCursorRects(for: view) }
        view.viewportChanged = viewportChanged
        view.geometryChanged = geometryChanged
        view.compare = compare; view.navigate = navigate; view.sample = sample
        view.needsDisplay = true
        // Report geometry after SwiftUI finishes its update; it may request higher-resolution detail.
        view.reportGeometryLater()
    }
}

final class PhotoCanvas: NSView {
    var image: CGImage?
    var clipping: CGImage?
    var detailImage: CGImage?
    var detailClipping: CGImage?
    var detailRegion: CGRect?
    var sourceSize = CGSize.zero
    var identity: String?
    var viewport = PhotoViewport()
    var picking = false
    var crop: CropRegion?
    var cropRatio: Double?
    var cropChanged: ((CropRegion) -> Void)?
    var cropFinished: ((Bool) -> Void)?
    private enum CropDrag { case move(CropRegion, CGPoint), resize(CGPoint) }
    private var cropDrag: CropDrag?
    var viewportChanged: ((PhotoViewport, CGSize, Double) -> Void)?
    var geometryChanged: ((CGSize, Double) -> Void)?
    var compare: ((Bool) -> Void)?
    var navigate: ((Int) -> Void)?
    var sample: ((CGPoint) -> Void)?
    private var dragPoint: CGPoint?
    private var geometryReportPending = false
    var backing: Double { Double(window?.backingScaleFactor ?? 1) }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // NSView defaults to unclipped drawing on modern macOS. Zoomed image rectangles
        // intentionally exceed the viewport; they must never paint over adjacent controls.
        clipsToBounds = true
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(resetComparison), name: NSWindow.didResignKeyNotification, object: window)
        }
        reportGeometryLater()
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); reportGeometryLater(); needsDisplay = true }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        viewport.constrain(source: sourceSize, canvas: newSize, backing: backing)
        reportGeometryLater(); needsDisplay = true
    }
    func reportGeometryLater() {
        guard !geometryReportPending else { return }
        geometryReportPending = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            guard let self else { return }
            self.geometryReportPending = false
            // A deferred resize report must not overwrite a newer toolbar/menu zoom setting
            // with native view state from before SwiftUI has applied that setting.
            self.geometryChanged?(self.bounds.size, self.backing)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func resetComparison() { compare?(false); dragPoint = nil }
    override func resignFirstResponder() -> Bool { compare?(false); return super.resignFirstResponder() }

    var imageRect: CGRect { viewport.imageRect(source: sourceSize, canvas: bounds.size, backing: backing) }
    var detailRect: CGRect {
        guard let region = detailRegion else { return .zero }
        let rect = imageRect
        return CGRect(x: rect.minX+region.minX*rect.width, y: rect.minY+region.minY*rect.height, width: region.width*rect.width, height: region.height*rect.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // Bound every drawing branch, including shadows, detail, clipping and crop overlays.
        context.clip(to: bounds)
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill(); bounds.fill()
        guard let image else { return }
        context.interpolationQuality = .high
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 18, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        context.draw(image, in: imageRect)
        context.restoreGState()
        if let clipping { context.draw(clipping, in: imageRect) }
        if let detailImage {
            // Replace the corresponding overview area, including its clipping overlay.
            context.saveGState()
            context.clip(to: detailRect)
            NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
            context.fill(detailRect)
            context.draw(detailImage, in: detailRect)
            if let detailClipping { context.draw(detailClipping, in: detailRect) }
            context.restoreGState()
        }
        if let crop { drawCrop(crop, context: context) }
    }
    private func normalized(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(x: min(1, max(0, (point.x-rect.minX)/max(1, rect.width))), y: min(1, max(0, (point.y-rect.minY)/max(1, rect.height))))
    }
    private func cropRect(_ crop: CropRegion) -> CGRect {
        let image = imageRect
        return CGRect(x: image.minX+crop.x*image.width, y: image.minY+crop.y*image.height, width: crop.width*image.width, height: crop.height*image.height)
    }
    private func cropCorners(_ crop: CropRegion) -> [CGPoint] {
        let rect = cropRect(crop)
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }
    private func drawCrop(_ crop: CropRegion, context: CGContext) {
        let image = imageRect, rect = cropRect(crop)
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        for shade in [CGRect(x: image.minX, y: image.minY, width: image.width, height: rect.minY-image.minY),
                      CGRect(x: image.minX, y: rect.maxY, width: image.width, height: image.maxY-rect.maxY),
                      CGRect(x: image.minX, y: rect.minY, width: rect.minX-image.minX, height: rect.height),
                      CGRect(x: rect.maxX, y: rect.minY, width: image.maxX-rect.maxX, height: rect.height)] { context.fill(shade) }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(0.5)
        for fraction in [1.0/3, 2.0/3] {
            context.move(to: CGPoint(x: rect.minX+rect.width*fraction, y: rect.minY)); context.addLine(to: CGPoint(x: rect.minX+rect.width*fraction, y: rect.maxY))
            context.move(to: CGPoint(x: rect.minX, y: rect.minY+rect.height*fraction)); context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY+rect.height*fraction))
        }
        context.strokePath()
        context.setStrokeColor(NSColor.white.cgColor); context.setLineWidth(1)
        context.stroke(rect)
        context.setFillColor(NSColor.white.cgColor)
        for point in cropCorners(crop) { context.fill(CGRect(x: point.x-4, y: point.y-4, width: 8, height: 8)) }
        context.restoreGState()
    }

    func changeZoom(_ scale: Double?, anchor: CGPoint? = nil) {
        guard image != nil, crop == nil else { return }
        viewport.setScale(scale, anchor: anchor, source: sourceSize, canvas: bounds.size, backing: backing)
        viewportChanged?(viewport, bounds.size, backing)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    override func magnify(with event: NSEvent) {
        let scale = viewport.resolvedScale(source: sourceSize, canvas: bounds.size, backing: backing)
        changeZoom(scale*max(0.1, 1+event.magnification), anchor: convert(event.locationInWindow, from: nil))
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let crop {
            guard imageRect.contains(point) || cropCorners(crop).contains(where: { hypot($0.x-point.x, $0.y-point.y) < 16 }) else { return }
            let corners = cropCorners(crop)
            if let index = corners.firstIndex(where: { hypot($0.x-point.x, $0.y-point.y) < 14 }) {
                cropDrag = .resize(normalized(corners[(index+2)%4]))
            } else if cropRect(crop).contains(point) {
                cropDrag = .move(crop, normalized(point))
            } else { cropDrag = .resize(normalized(point)) }
        } else if picking, imageRect.contains(point) {
            sample?(CGPoint(x: (point.x-imageRect.minX)/imageRect.width, y: 1-(point.y-imageRect.minY)/imageRect.height))
        } else if event.clickCount == 2 {
            changeZoom(viewport.scale == nil ? 1 : nil, anchor: point)
        } else { dragPoint = point }
    }
    override func mouseDragged(with event: NSEvent) {
        if let cropDrag {
            let point = normalized(convert(event.locationInWindow, from: nil))
            let next: CropRegion
            switch cropDrag {
            case .move(let start, let origin): next = start.moved(by: CGSize(width: point.x-origin.x, height: point.y-origin.y))
            case .resize(let anchor):
                let ratio = cropRatio.map { $0*sourceSize.height/sourceSize.width }
                next = CropRegion.between(anchor: anchor, point: point, ratio: ratio)
            }
            crop = next; cropChanged?(next); needsDisplay = true
            return
        }
        guard let dragPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        viewport.pan(by: CGSize(width: point.x-dragPoint.x, height: point.y-dragPoint.y), source: sourceSize, canvas: bounds.size, backing: backing)
        self.dragPoint = point
        viewportChanged?(viewport, bounds.size, backing)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { dragPoint = nil; cropDrag = nil }
    override func scrollWheel(with event: NSEvent) {
        guard image != nil, crop == nil else { return }
        if event.modifierFlags.contains(.option) || !event.hasPreciseScrollingDeltas {
            let scale = viewport.resolvedScale(source: sourceSize, canvas: bounds.size, backing: backing)
            changeZoom(scale*exp(event.scrollingDeltaY*0.025), anchor: convert(event.locationInWindow, from: nil))
        } else {
            viewport.pan(by: CGSize(width: event.scrollingDeltaX, height: -event.scrollingDeltaY), source: sourceSize, canvas: bounds.size, backing: backing)
            viewportChanged?(viewport, bounds.size, backing)
            needsDisplay = true
        }
    }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        if let crop {
            switch event.keyCode {
            case 36, 76: cropFinished?(true)
            case 53: cropFinished?(false)
            case 123...126:
                let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
                let dx = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
                let dy = event.keyCode == 125 ? -step : event.keyCode == 126 ? step : 0
                let next = crop.moved(by: CGSize(width: dx/max(1, sourceSize.width), height: dy/max(1, sourceSize.height)))
                self.crop = next; cropChanged?(next); needsDisplay = true
            case 49: if !event.isARepeat { compare?(true) }
            default: super.keyDown(with: event)
            }
            return
        }
        switch event.keyCode {
        case 49: if !event.isARepeat { compare?(true) }
        case 123: navigate?(-1)
        case 124: navigate?(1)
        default: super.keyDown(with: event)
        }
    }
    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { compare?(false) } else { super.keyUp(with: event) }
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: (picking || crop != nil) ? .crosshair : viewport.scale == nil ? .arrow : .openHand)
    }
}

struct CompareButton: NSViewRepresentable {
    let enabled: Bool
    let comparing: Bool
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> HoldButton {
        let button = HoldButton(title: "Original", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.setAccessibilityLabel("Show original. Press and hold to compare.")
        button.toolTip = "Hold to compare · Space"
        return button
    }
    func updateNSView(_ button: HoldButton, context: Context) {
        button.isEnabled = enabled
        button.setAccessibilityValue(comparing ? "Showing original" : "Showing edited")
        button.onChange = onChange
    }
}
final class HoldButton: NSButton {
    var onChange: ((Bool) -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) { if isEnabled { onChange?(true) } }
    override func mouseUp(with event: NSEvent) { onChange?(false) }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onChange?(true)
        DispatchQueue.main.asyncAfter(deadline: .now()+1) { [weak self] in self?.onChange?(false) }
        return true
    }
}
