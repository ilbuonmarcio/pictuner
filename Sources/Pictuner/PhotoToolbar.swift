import SwiftUI

/// Photo actions stay next to the image; crop mode replaces them with its contextual controls.
struct PhotoToolbar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if model.isCropping { cropControls } else { photoControls }
        }.font(.system(size: 12)).buttonStyle(.borderless).controlSize(.small)
            .padding(.horizontal, 16).frame(height: 42)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private var photoControls: some View {
        Group {
            Button(action: model.beginCrop) { Label("Crop", systemImage: "crop") }
                .help("Crop · ⌘K").disabled(!model.canEdit || model.preview == nil)
            Button { model.rotate(clockwise: false) } label: { Image(systemName: "rotate.left") }
                .help("Rotate left 90°").accessibilityLabel("Rotate left 90 degrees").disabled(!model.canEdit)
            Button { model.rotate(clockwise: true) } label: { Image(systemName: "rotate.right") }
                .help("Rotate right 90°").accessibilityLabel("Rotate right 90 degrees").disabled(!model.canEdit)
            Menu {
                Button("Flip Horizontally") { model.flip(horizontal: true) }
                Button("Flip Vertically") { model.flip(horizontal: false) }
                if model.settings.adjustments.geometry.crop != nil {
                    Divider()
                    Button("Remove Crop", action: model.clearCrop)
                }
            } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                .menuStyle(.borderlessButton).fixedSize().help("Flip and crop options").accessibilityLabel("Flip and crop options").disabled(!model.canEdit)
            Spacer(minLength: 4)
            Button(action: model.toggleFavorite) { Image(systemName: model.settings.favorite ? "star.fill" : "star") }
                .foregroundStyle(model.settings.favorite ? .yellow : .secondary)
                .help("Favorite").accessibilityLabel("Favorite").accessibilityValue(model.settings.favorite ? "Yes" : "No").disabled(!model.canEdit)
            Button(action: model.toggleRejected) { Image(systemName: model.settings.rejected ? "xmark.circle.fill" : "xmark.circle") }
                .foregroundStyle(model.settings.rejected ? .red : .secondary)
                .help("Reject").accessibilityLabel("Reject").accessibilityValue(model.settings.rejected ? "Yes" : "No").disabled(!model.canEdit)
            Button(action: model.toggleExportReady) { Image(systemName: model.settings.exportReady ? "checkmark.circle.fill" : "checkmark.circle") }
                .foregroundStyle(model.settings.exportReady ? .green : .secondary)
                .help(model.settings.exportReady ? "Remove from Export · ⇧⌘G" : "Include in Export · ⇧⌘G")
                .accessibilityLabel("Include in Export").accessibilityValue(model.settings.exportReady ? "Marked for export" : "Not marked for export").disabled(!model.canEdit)
            Divider().frame(height: 16)
            Menu {
                Button("Copy Edits", action: model.copyAdjustments)
                Button("Paste Edits", action: model.pasteAdjustments).disabled(!model.hasCopiedAdjustments)
                if model.selectedCount > 1 {
                    Divider()
                    Button("Apply Edits to \(model.selectedCount) Selected", action: model.applyToSelection)
                    Button("Mark Selected for Export") { model.setExportReady(true, for: model.selectedIDs) }
                    Button("Unmark Selected for Export") { model.setExportReady(false, for: model.selectedIDs) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().help("Photo actions").accessibilityLabel("Photo actions").disabled(!model.canEdit)
        }
    }
    private var cropControls: some View {
        Group {
            Picker("Aspect", selection: Binding(get: { model.cropAspect }, set: model.setCropAspect)) {
                ForEach(CropAspect.allCases) { Text($0.rawValue).tag($0) }
            }.frame(width: 124).disabled(model.preview == nil)
            Button("Reset", action: model.resetCropDraft).help("Reset crop bounds").disabled(model.preview == nil)
            Spacer(minLength: 4)
            Button("Cancel", action: model.cancelCrop).help("Cancel crop · Esc")
            Button("Apply", action: model.applyCrop).buttonStyle(.borderedProminent)
                .help("Apply crop · Return").disabled(model.preview == nil)
        }
    }
}
