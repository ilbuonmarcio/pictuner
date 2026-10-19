import SwiftUI

struct ExportSheet: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Export").font(.system(size: 20, weight: .semibold))
                Spacer()
                Text("\(model.exportItems().count) \(model.exportItems().count == 1 ? "photo" : "photos")").foregroundStyle(.secondary)
            }
            Form {
                Picker("Photos", selection: $model.exportOptions.scope) { ForEach(ExportScope.allCases, id: \.self) { Text($0.rawValue) } }
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
            Text("sRGB · Metadata excluded").font(.system(size: 11)).foregroundStyle(.secondary)
                .help("Source EXIF and GPS metadata are not included.")
            if model.exportItems().isEmpty {
                Text("Mark photos using Include in Export.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { model.showExportSheet = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Export…", action: model.startExport).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.exportItems().isEmpty)
            }
        }.padding(26).frame(width: 470)
    }
}
