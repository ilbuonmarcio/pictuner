import SwiftUI

/// Photo actions stay next to the image; crop mode replaces them with its contextual controls.
struct PhotoToolbar: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("compositionGridVisible") private var compositionGridVisible = false

    var body: some View {
        HStack(spacing: 10) {
            if model.isCropping { cropControls } else { photoControls }
        }.font(.system(size: 12)).buttonStyle(.borderless).controlSize(.small)
            .padding(.horizontal, 16).frame(height: 42)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private var photoControls: some View {
        Group {
            Button(action: model.beginCrop) { Label("Crop", systemImage: "crop") }
                .help("Crop · ⌘K").disabled(!model.canEdit || model.preview == nil)
            Button { model.beginCrop(); model.levelingHorizon = model.isCropping } label: { Image(systemName: "angle") }
                .help("Straighten: drag along a horizon").accessibilityLabel("Straighten").disabled(!model.canEdit || model.preview == nil)
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
            Button { compositionGridVisible.toggle() } label: {
                Image(systemName: "grid")
                    .foregroundStyle(compositionGridVisible ? Color.accentColor : .secondary)
                    .frame(width: 20, height: 22)
                    .background(compositionGridVisible ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .help(compositionGridVisible ? "Hide 3×3 grid" : "Show 3×3 grid")
            .accessibilityLabel("Composition grid")
            .accessibilityValue(compositionGridVisible ? "Shown" : "Hidden")
            .accessibilityAddTraits(compositionGridVisible ? .isSelected : [])
            .disabled(model.preview == nil)
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
            HStack(spacing: 6) {
                Picker("Aspect", selection: Binding(get: { model.cropAspect }, set: model.setCropAspect)) {
                    ForEach(CropAspect.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 82).help("Crop aspect ratio").accessibilityLabel("Crop aspect ratio")
                ResetValueButton(title: "Crop aspect ratio", value: Binding(get: { model.cropAspect }, set: model.setCropAspect), defaultValue: .free)
            }.disabled(model.preview == nil)
            Button("Reset Crop", action: model.resetCropDraft).help("Reset crop bounds").disabled(model.preview == nil)
            Spacer(minLength: 4)
            Button("Cancel", action: model.cancelCrop).help("Cancel crop · Esc")
            Button("Apply", action: model.applyCrop).buttonStyle(.borderedProminent)
                .help("Apply crop · Return").disabled(model.preview == nil)
        }
    }
}

struct StraightenToolbar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Text("Straighten").fontWeight(.medium)
            Slider(value: Binding(get: { model.straightenDraft }, set: model.setStraightenDraft),
                   in: -15...15, onEditingChanged: model.straightenEditing)
                .accessibilityLabel("Straighten angle")
            Text(String(format: "%+.1f°", model.straightenDraft)).monospacedDigit().frame(width: 44)
            ResetValueButton(title: "Straighten angle", value: Binding(get: { model.straightenDraft }, set: model.setStraightenDraft), defaultValue: 0)
            Button { model.levelingHorizon.toggle() } label: {
                Image(systemName: "angle").foregroundStyle(model.levelingHorizon ? Color.accentColor : .secondary)
            }.accessibilityLabel("Draw horizon").accessibilityValue(model.levelingHorizon ? "Active" : "Inactive")
                .help("Drag along a horizon to level it. Edges are trimmed automatically.")
        }.font(.system(size: 11)).buttonStyle(.borderless).controlSize(.small)
            .padding(.horizontal, 16).frame(height: 36)
    }
}
