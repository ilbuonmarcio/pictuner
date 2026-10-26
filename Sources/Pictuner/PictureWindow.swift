import SwiftUI
import AppKit

/// Only one canvas is mounted at a time, so the bounded detail renderer has one viewport.
struct PictureSurface: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("compositionGridVisible") private var compositionGridVisible = false
    var body: some View {
ZStack {
                    photoCanvas
                    if model.activePhoto == nil { emptyState }
                    else if let error = model.previewError {
                        ContentUnavailableView("Unable to open image", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else if model.preview == nil { ProgressView().accessibilityLabel("Loading image").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                    VStack {
                        HStack {
                            if model.showingOriginal { badge("Original", icon: "circle.lefthalf.filled") }
                            else if model.showMask { badge("Mask", icon: "viewfinder") }
                            else if model.pickingColor { badge("Pick a color", icon: "eyedropper") }
                            else if model.levelingHorizon { badge("Draw horizon", icon: "angle") }
                            Spacer()
                            if model.isRendering && model.preview != nil { ProgressView().controlSize(.small).padding(12) }
                        }
                        Spacer()
                    }.padding(18).allowsHitTesting(false)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var photoCanvas: PreviewCanvas {
        PreviewCanvas(image: displayImage,
            clipping: displayClipping,
            detailImage: displayDetail,
            detailClipping: detailClipping,
            detailRegion: model.preview?.detail?.region,
            sourceSize: model.preview?.sourceSize ?? .zero,
            identity: model.selectedID,
            viewport: model.viewport,
            picking: model.pickingColor,
            showGrid: compositionGridVisible,
            crop: model.preview == nil ? nil : model.cropDraft,
            cropRatio: model.cropRatio,
            originalImage: model.preview?.original,
            originalDetail: model.preview?.detail?.original,
            originalClipping: model.showClipping ? model.preview?.originalClipping : nil,
            originalDetailClipping: model.showClipping ? model.preview?.detail?.originalClipping : nil,
            wipe: model.activeWipe,
            wipeChanged: model.setWipePosition,
            leveling: model.levelingHorizon,
            horizonChanged: model.levelHorizon,
            escape: model.escapePreview,
            cropChanged: model.updateCrop,
            cropFinished: { if $0 { model.applyCrop() } else { model.cancelCrop() } },
            viewportChanged: { model.updateViewport($0, canvas: $1, backing: $2) },
            geometryChanged: { model.updateCanvasGeometry($0, backing: $1) },
            compare: { model.showingOriginal = $0 },
            navigate: model.navigate,
            sample: model.sampleColor)
    }

    private var displayImage: CGImage? {
        guard let preview = model.preview else { return nil }
        if model.showingOriginal { return preview.original }
        if model.showMask, let mask = preview.mask { return mask }
        return preview.edited
    }
    private var displayClipping: CGImage? {
        guard model.showClipping, !model.showMask else { return nil }
        return model.showingOriginal ? model.preview?.originalClipping : model.preview?.clipping
    }
    private var displayDetail: CGImage? {
        guard let detail = model.preview?.detail else { return nil }
        if model.showingOriginal { return detail.original }
        if model.showMask { return detail.mask ?? detail.edited }
        return detail.edited
    }
    private var detailClipping: CGImage? {
        guard model.showClipping, !model.showMask else { return nil }
        return model.showingOriginal ? model.preview?.detail?.originalClipping : model.preview?.detail?.clipping
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(model.isLoading ? "Loading…" : model.activeWorkspace == nil ? "No Workspace" : model.exportOnly ? "No Photos Included for Export" : "No Images").font(.system(size: 18, weight: .medium))
            if model.activeWorkspace == nil { Button("Add Workspace…", action: model.addWorkspace).buttonStyle(.borderedProminent).controlSize(.large) }
            if model.exportOnly && model.activeWorkspace != nil { Button("Show All Photos", action: model.toggleExportOnly) }
            if model.isLoading { ProgressView().controlSize(.small) }
        }.padding(32)
    }
    private func badge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 7).background(.regularMaterial, in: Capsule())
    }

}

@MainActor
final class PictureWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isDetached = false
    private var window: NSWindow?
    private weak var model: AppModel?

    func detach(model: AppModel) {
        guard window == nil else { window?.makeKeyAndOrderFront(nil); return }
        self.model = model
        model.showingOriginal = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "PicTuner — Picture"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 320, height: 240)
        window.delegate = self
        window.contentView = NSHostingView(rootView: PictureSurface().environmentObject(model).preferredColorScheme(.dark))
        window.center()
        self.window = window
        isDetached = true
        window.makeKeyAndOrderFront(nil)
    }

    func attach() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        model?.showingOriginal = false
        // Release the hosting tree before remounting the editor canvas.
        window?.contentView = nil
        window = nil
        isDetached = false
    }
}
