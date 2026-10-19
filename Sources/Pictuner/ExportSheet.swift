import SwiftUI

struct ExportSheet: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Export your photos").font(.system(size: 23, weight: .semibold))
                Text("Finished copies. Untouched originals.").foregroundStyle(.secondary)
            }
            Form {
                Picker("Images", selection: $model.exportOptions.scope) { ForEach(ExportScope.allCases, id: \.self) { Text($0.rawValue) } }
                Picker("Format", selection: $model.exportOptions.format) { ForEach(OutputFormat.allCases, id: \.self) { Text($0.rawValue) } }
                if model.exportOptions.format == .jpeg {
                    HStack { Text("Quality"); Slider(value: $model.exportOptions.quality, in: 0.3...1); Text("\(Int(model.exportOptions.quality*100))%").monospacedDigit().frame(width: 42) }
                }
                Picker("Size", selection: $model.exportOptions.longEdge) {
                    Text("Full resolution").tag(0.0)
                    Text("Long edge · 3840 px").tag(3840.0)
                    Text("Long edge · 2048 px").tag(2048.0)
                    Text("Long edge · 1280 px").tag(1280.0)
                }
                Toggle("Preserve subfolder structure", isOn: $model.exportOptions.preserveFolders)
                Picker("Existing filenames", selection: $model.exportOptions.collision) { ForEach(CollisionPolicy.allCases, id: \.self) { Text($0.rawValue) } }
            }.formStyle(.grouped).frame(height: 275)
            Text("\(model.exportItems().count) marked \(model.exportItems().count == 1 ? "photo" : "photos") included. Unmarked and rejected photos are excluded. Exports use sRGB and omit source EXIF/GPS. Choose a destination outside your workspaces.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.exportItems().isEmpty {
                Text("Mark photos with Include in Export before exporting.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { model.showExportSheet = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Folder & Export…", action: model.startExport).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.exportItems().isEmpty)
            }
        }.padding(26).frame(width: 470)
    }
}
