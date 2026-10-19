import SwiftUI
import AppKit

struct PreviewCanvas: NSViewRepresentable {
    let image: CGImage?
    let clipping: CGImage?
    let identity: String?
    let zoom: Double
    let picking: Bool
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
            view.pan = .zero; view.identity = identity
            if identity != nil {
                DispatchQueue.main.async { [weak view] in
                    guard let view else { return }
                    view.window?.makeFirstResponder(view)
                }
            }
        }
        view.image = image; view.clipping = clipping; view.zoom = zoom
        if view.picking != picking { view.picking = picking; view.window?.invalidateCursorRects(for: view) }
        view.compare = compare; view.navigate = navigate; view.sample = sample
        view.needsDisplay = true
    }
}

final class PhotoCanvas: NSView {
    var image: CGImage?
    var clipping: CGImage?
    var identity: String?
    var zoom = 1.0
    var pan = CGPoint.zero
    var picking = false
    var compare: ((Bool) -> Void)?
    var navigate: ((Int) -> Void)?
    var sample: ((CGPoint) -> Void)?
    private var dragOrigin: CGPoint?
    private var initialPan = CGPoint.zero
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(resetComparison), name: NSWindow.didResignKeyNotification, object: window)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func resetComparison() { compare?(false) }
    override func resignFirstResponder() -> Bool { compare?(false); return super.resignFirstResponder() }

    var imageRect: CGRect {
        guard let image else { return .zero }
        let inset = bounds.insetBy(dx: 28, dy: 28)
        let scale = max(0, min(inset.width/Double(image.width), inset.height/Double(image.height))) * zoom
        let size = CGSize(width: Double(image.width)*scale, height: Double(image.height)*scale)
        return CGRect(x: (bounds.width-size.width)/2+pan.x, y: (bounds.height-size.height)/2+pan.y, width: size.width, height: size.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill(); bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 18, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        context.draw(image, in: imageRect)
        context.restoreGState()
        if let clipping { context.draw(clipping, in: imageRect) }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if picking, imageRect.contains(point) {
            sample?(CGPoint(x: (point.x-imageRect.minX)/imageRect.width, y: 1-(point.y-imageRect.minY)/imageRect.height))
        } else { dragOrigin = point; initialPan = pan }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, zoom > 1 else { return }
        let point = convert(event.locationInWindow, from: nil)
        pan = CGPoint(x: initialPan.x+point.x-dragOrigin.x, y: initialPan.y+point.y-dragOrigin.y)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { dragOrigin = nil }
    override func scrollWheel(with event: NSEvent) {
        guard zoom > 1 else { super.scrollWheel(with: event); return }
        pan.x += event.scrollingDeltaX; pan.y -= event.scrollingDeltaY; needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
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
    override func resetCursorRects() { if picking { addCursorRect(bounds, cursor: .crosshair) } }
}

struct CompareButton: NSViewRepresentable {
    let enabled: Bool
    let comparing: Bool
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> HoldButton {
        let button = HoldButton(title: "Show Original · Space", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.setAccessibilityLabel("Show original. Press and hold to compare.")
        return button
    }
    func updateNSView(_ button: HoldButton, context: Context) {
        button.isEnabled = enabled
        button.title = comparing ? "Original · release to return" : "Show Original · Space"
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
