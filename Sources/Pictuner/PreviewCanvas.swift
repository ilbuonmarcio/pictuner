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
    let showGrid: Bool
    let crop: CropRegion?
    let cropRatio: Double?
    let originalImage: CGImage?
    let originalDetail: CGImage?
    let originalClipping: CGImage?
    let originalDetailClipping: CGImage?
    let wipe: Double?
    let wipeChanged: (Double) -> Void
    let leveling: Bool
    let horizonChanged: (Double) -> Void
    let escape: () -> Void
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
            view.cancelDrags()
            if identity != nil {
                DispatchQueue.main.async { [weak view] in
                    guard let view else { return }
                    view.window?.makeFirstResponder(view)
                }
            }
        }
        view.image = image; view.clipping = clipping
        view.detailImage = detailImage; view.detailClipping = detailClipping; view.detailRegion = detailRegion
        view.sourceSize = sourceSize; view.viewport = viewport; view.showGrid = showGrid
        view.originalImage = originalImage; view.originalDetail = originalDetail
        view.originalClipping = originalClipping; view.originalDetailClipping = originalDetailClipping
        if view.wipe != wipe || view.leveling != leveling { view.window?.invalidateCursorRects(for: view) }
        view.wipe = wipe; view.wipeChanged = wipeChanged
        view.leveling = leveling; view.horizonChanged = horizonChanged; view.escape = escape
        if !leveling { view.horizonLine = nil }
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
    var showGrid = false
    var originalImage: CGImage?
    var originalDetail: CGImage?
    var originalClipping: CGImage?
    var originalDetailClipping: CGImage?
    var wipe: Double?
    var wipeChanged: ((Double) -> Void)?
    var leveling = false
    var horizonChanged: ((Double) -> Void)?
    var escape: (() -> Void)?
    var horizonLine: (CGPoint, CGPoint)?
    private var draggingWipe = false
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
            guard self.window != nil else { return }
            // A deferred resize report must not overwrite a newer toolbar/menu zoom setting
            // with native view state from before SwiftUI has applied that setting.
            self.geometryChanged?(self.bounds.size, self.backing)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    func cancelDrags() { dragPoint = nil; cropDrag = nil; draggingWipe = false; horizonLine = nil }
    @objc private func resetComparison() { compare?(false); cancelDrags() }
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
        if let wipe, let originalImage {
            context.saveGState()
            let visible = comparisonRect
            context.clip(to: CGRect(x: visible.minX, y: visible.minY, width: visible.width*wipe, height: visible.height))
            context.draw(originalImage, in: imageRect)
            if let originalClipping { context.draw(originalClipping, in: imageRect) }
            if let originalDetail {
                context.saveGState(); context.clip(to: detailRect)
                context.draw(originalDetail, in: detailRect)
                if let originalDetailClipping { context.draw(originalDetailClipping, in: detailRect) }
                context.restoreGState()
            }
            context.restoreGState()
        }
        if let crop { drawCrop(crop, context: context) }
        else if showGrid { drawCompositionGrid(context: context) }
        if wipe != nil { drawWipe(context: context) }
        if let (start, end) = horizonLine {
            context.saveGState()
            context.clip(to: imageRect)
            context.move(to: start); context.addLine(to: end)
            context.setStrokeColor(NSColor.black.cgColor); context.setLineWidth(4); context.strokePath()
            context.move(to: start); context.addLine(to: end)
            context.setStrokeColor(NSColor.systemYellow.cgColor); context.setLineWidth(2); context.strokePath()
            for point in [start, end] { context.setFillColor(NSColor.white.cgColor); context.fillEllipse(in: CGRect(x: point.x-4, y: point.y-4, width: 8, height: 8)) }
            context.restoreGState()
        }
    }

    var comparisonRect: CGRect { imageRect.intersection(bounds) }
    var wipeX: Double { comparisonRect.minX+comparisonRect.width*(wipe ?? 0.5) }
    func moveWipe(to point: CGPoint) {
        guard wipe != nil, comparisonRect.width > 0 else { return }
        let value = min(1, max(0, (point.x-comparisonRect.minX)/comparisonRect.width))
        wipe = value; wipeChanged?(value); needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    private func drawWipe(context: CGContext) {
        let rect = comparisonRect
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
        let x = min(rect.maxX-1, max(rect.minX+1, wipeX))
        context.saveGState(); defer { context.restoreGState() }
        context.clip(to: rect)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(3); context.move(to: CGPoint(x: x, y: rect.minY)); context.addLine(to: CGPoint(x: x, y: rect.maxY)); context.strokePath()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1); context.move(to: CGPoint(x: x, y: rect.minY)); context.addLine(to: CGPoint(x: x, y: rect.maxY)); context.strokePath()
        let handle = CGRect(x: x-12, y: rect.midY-12, width: 24, height: 24)
        context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor); context.fillEllipse(in: handle)
        context.strokeEllipse(in: handle)
        for direction in [-1.0, 1.0] {
            context.move(to: CGPoint(x: x+direction*3, y: rect.midY+3))
            context.addLine(to: CGPoint(x: x+direction*6, y: rect.midY))
            context.addLine(to: CGPoint(x: x+direction*3, y: rect.midY-3))
        }
        context.strokePath()
        for (text, origin, room) in [("Original", rect.minX+8, x-rect.minX), ("Edited", rect.maxX-58, rect.maxX-x)] where room > 85 {
            let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
            let size = label.size(), box = CGRect(x: origin-4, y: rect.maxY-size.height-12, width: size.width+8, height: size.height+8)
            context.setFillColor(NSColor.black.withAlphaComponent(0.65).cgColor); context.fill(box)
            label.draw(at: CGPoint(x: origin, y: box.minY+4))
        }
    }
    private func drawCompositionGrid(context: CGContext) {
        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return }
        let path = CGMutablePath()
        for fraction in [1.0/3, 2.0/3] {
            path.move(to: CGPoint(x: rect.minX+rect.width*fraction, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX+rect.width*fraction, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY+rect.height*fraction))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY+rect.height*fraction))
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        // A dark underlay keeps the thin white lines readable on both bright and dark photos.
        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(2)
        context.strokePath()
        context.addPath(path)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.65).cgColor)
        context.setLineWidth(0.75)
        context.strokePath()
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
        if leveling, crop != nil, imageRect.contains(point) {
            horizonLine = (point, point); needsDisplay = true; return
        }
        if wipe != nil, comparisonRect.contains(point), abs(point.x-wipeX) <= 14 {
            draggingWipe = true; moveWipe(to: point); return
        }
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
        let canvasPoint = convert(event.locationInWindow, from: nil)
        if let (start, _) = horizonLine {
            horizonLine = (start, CGPoint(x: min(imageRect.maxX, max(imageRect.minX, canvasPoint.x)), y: min(imageRect.maxY, max(imageRect.minY, canvasPoint.y))))
            needsDisplay = true; return
        }
        if draggingWipe { moveWipe(to: canvasPoint); return }
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
    override func mouseUp(with event: NSEvent) {
        if let (start, end) = horizonLine, let angle = ImageGeometry.horizonCorrection(from: start, to: end) { horizonChanged?(angle) }
        cancelDrags(); needsDisplay = true
    }
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
        if event.keyCode == 53, crop == nil { escape?(); return }
        if wipe != nil, event.modifierFlags.intersection([.command, .control, .option]) == .option, [123, 124].contains(event.keyCode) {
            let value = min(1, max(0, (wipe ?? 0.5)+(event.keyCode == 123 ? -0.05 : 0.05)))
            wipe = value; wipeChanged?(value); needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }
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
        if wipe != nil {
            let rect = CGRect(x: wipeX-10, y: comparisonRect.minY, width: 20, height: comparisonRect.height).intersection(bounds)
            if !rect.isNull { addCursorRect(rect, cursor: .resizeLeftRight) }
        }
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
