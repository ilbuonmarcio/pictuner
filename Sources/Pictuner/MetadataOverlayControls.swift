import SwiftUI

struct MetadataOverlayControls: View {
    @EnvironmentObject var model: AppModel
    private var metadata: PhotoMetadata { model.preview?.metadata ?? PhotoMetadata() }

    private func binding<Value>(_ key: WritableKeyPath<MetadataOverlay, Value>) -> Binding<Value> {
        Binding(get: { model.settings.adjustments.metadataOverlay[keyPath: key] }, set: { value in
            var adjustments = model.settings.adjustments
            adjustments.metadataOverlay[keyPath: key] = value
            model.setAdjustments(adjustments)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Date & GPS").font(.headline)
                Spacer()
                Toggle("Show on photo", isOn: binding(\.enabled)).toggleStyle(.switch).controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 10) {
                field("Capture date & time", value: metadata.captureDate, toggle: binding(\.showsDate))
                field("GPS coordinates", value: metadata.coordinates, toggle: binding(\.showsGPS))
            }
            Divider()
            HStack {
                Picker("Position", selection: binding(\.position)) {
                    ForEach(OverlayPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                ResetValueButton(title: "Label position", value: binding(\.position), defaultValue: MetadataOverlay().position)
            }
            dimension("Margin", key: \.margin, range: 0.01...0.12)
            dimension("Text size", key: \.textSize, range: 0.012...0.05)
            Text("Included in exported images.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 400)
        .disabled(!model.canEdit || model.isCropping)
    }

    private func field(_ title: String, value: String?, toggle: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: toggle)
            Text(value ?? "Not available in this photo")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.leading, 20).textSelection(.enabled)
        }
    }

    private func dimension(_ title: String, key: WritableKeyPath<MetadataOverlay, Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 62, alignment: .leading)
            Slider(value: binding(key), in: range, onEditingChanged: model.editingGesture)
                .accessibilityLabel(title)
            Text(String(format: "%.1f%%", model.settings.adjustments.metadataOverlay[keyPath: key]*100))
                .font(.system(size: 11, design: .monospaced)).frame(width: 43, alignment: .trailing)
            ResetValueButton(title: "Label \(title.lowercased())", value: binding(key), defaultValue: MetadataOverlay()[keyPath: key])
        }.help("Proportion of the cropped photo’s shorter edge")
    }
}
