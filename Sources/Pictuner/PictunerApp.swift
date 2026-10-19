import SwiftUI
import AppKit

@main
struct PictunerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Pictuner", id: "main") {
            ContentView().environmentObject(model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1360, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Workspace…", action: model.addWorkspace).keyboardShortcut("o")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Edit", action: model.undo).keyboardShortcut("z").disabled(!model.canUndo)
                Button("Redo Edit", action: model.redo).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo)
            }
            CommandMenu("Photo") {
                Button(model.settings.exportReady ? "Remove from Export" : "Include in Export", action: model.toggleExportReady)
                    .keyboardShortcut("g", modifiers: [.command, .shift]).disabled(!model.canEdit)
                Divider()
                Button("Copy Adjustments", action: model.copyAdjustments).keyboardShortcut("c", modifiers: [.command, .shift]).disabled(model.activePhoto == nil)
                Button("Paste Adjustments", action: model.pasteAdjustments).keyboardShortcut("v", modifiers: [.command, .shift]).disabled(!model.hasCopiedAdjustments || !model.canEdit)
                Button("Select All Photos", action: model.selectAll).keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button("Export Copies…") { model.showExportSheet = true }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.photos.isEmpty || model.exporting)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
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
