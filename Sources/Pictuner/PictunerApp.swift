import SwiftUI
import AppKit

@main
struct PicTunerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @AppStorage("workspaceSidebarVisible") private var workspaceSidebarVisible = true
    var body: some Scene {
        Window("PicTuner", id: "main") {
            ContentView().environmentObject(model)
                .background(OpeningWindowSize())
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1480, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Workspace…", action: model.addWorkspace).keyboardShortcut("o")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Edit", action: model.undo).keyboardShortcut("z").disabled(!model.canUndo)
                Button("Redo Edit", action: model.redo).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo)
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button(model.distractionFree ? "Exit Distraction-Free Mode" : "Distraction-Free Mode", action: model.toggleDistractionFree)
                    .keyboardShortcut("f", modifiers: [.command, .shift]).disabled(model.isCropping)
                Button(model.comparisonWipe ? "Hide Before/After Wipe" : "Show Before/After Wipe", action: model.toggleComparisonWipe)
                    .keyboardShortcut("\\").disabled(model.preview == nil || model.isCropping)
                Button("Move Comparison Divider Left") { model.setWipePosition(model.wipePosition-0.05) }
                    .keyboardShortcut(.leftArrow, modifiers: .option).disabled(model.activeWipe == nil)
                Button("Move Comparison Divider Right") { model.setWipePosition(model.wipePosition+0.05) }
                    .keyboardShortcut(.rightArrow, modifiers: .option).disabled(model.activeWipe == nil)
                Divider()
                Button("Zoom In") { model.zoomBy(sqrt(2)) }.keyboardShortcut("+", modifiers: .command).disabled(model.preview == nil || model.isCropping)
                Button("Zoom Out") { model.zoomBy(1/sqrt(2)) }.keyboardShortcut("-", modifiers: .command).disabled(model.preview == nil || model.isCropping)
                Button("Fit to Window") { model.setZoom(nil) }.keyboardShortcut("0", modifiers: .command).disabled(model.preview == nil || model.isCropping)
                Button("Actual Pixels (100%)") { model.setZoom(1) }.keyboardShortcut("1", modifiers: .command).disabled(model.preview == nil || model.isCropping)
            }
            CommandGroup(after: .sidebar) {
                Button(workspaceSidebarVisible ? "Hide Workspaces" : "Show Workspaces") {
                    workspaceSidebarVisible.toggle()
                }.keyboardShortcut("s", modifiers: [.control, .command])
            }
            CommandMenu("Photo") {
                Button("Crop…", action: model.beginCrop).keyboardShortcut("k").disabled(!model.canEdit || model.preview == nil || model.isCropping)
                Button("Straighten…") { model.beginCrop(); model.levelingHorizon = model.isCropping }
                    .disabled(!model.canEdit || model.preview == nil || model.isCropping)
                Button("Rotate Left 90°") { model.rotate(clockwise: false) }.disabled(!model.canEdit || model.isCropping)
                Button("Rotate Right 90°") { model.rotate(clockwise: true) }.disabled(!model.canEdit || model.isCropping)
                Button("Flip Horizontally") { model.flip(horizontal: true) }.disabled(!model.canEdit || model.isCropping)
                Button("Flip Vertically") { model.flip(horizontal: false) }.disabled(!model.canEdit || model.isCropping)
                Divider()
                Button(model.settings.exportReady ? "Remove from Export" : "Include in Export", action: model.toggleExportReady)
                    .keyboardShortcut("g", modifiers: [.command, .shift]).disabled(!model.canEdit)
                Divider()
                Button("Copy Adjustments", action: model.copyAdjustments).keyboardShortcut("c", modifiers: [.command, .shift]).disabled(model.activePhoto == nil)
                Button("Paste Adjustments", action: model.pasteAdjustments).keyboardShortcut("v", modifiers: [.command, .shift]).disabled(!model.hasCopiedAdjustments || !model.canEdit || model.isCropping)
                Button("Select All Photos", action: model.selectAll).keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button("Export…") { model.showExportSheet = true }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.photos.isEmpty || model.exporting || model.isCropping)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.prepareToQuit() != false else { return .terminateCancel }
        if model?.exporting == true {
            let alert = NSAlert()
            alert.messageText = "An export is still running"
            alert.informativeText = "Cancel the export and quit? Completed copies will be kept."
            alert.addButton(withTitle: "Keep Exporting")
            alert.addButton(withTitle: "Cancel Export and Quit")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            model?.cancelExport()
            // Let the in-flight encoder finish and remove temporary files before terminating.
            Task { @MainActor in
                while model?.exporting == true { try? await Task.sleep(for: .milliseconds(100)) }
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
