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
            HStack {
                Text("Recipe")
                Spacer()
                Menu {
                    ForEach(ExportRecipe.allCases) { recipe in
                        Button(recipe.rawValue) { recipe.apply(to: &model.exportOptions) }.help(recipe.summary)
                    }
                } label: { Text(model.exportOptions.recipe?.rawValue ?? "Custom") }
                    .accessibilityLabel("Export recipe")
                    .accessibilityValue(model.exportOptions.recipe?.rawValue ?? "Custom")
                    .help(model.exportOptions.recipe?.help ?? "Choose a recipe, then adjust any export setting.")
                Button("Reset") { model.exportOptions.resetEncoding() }
                    .font(.system(size: 9, weight: .medium)).buttonStyle(.borderless)
                    .accessibilityLabel("Reset Export recipe")
                    .disabled(model.exportOptions.encodingIsDefault)
            }
            Form {
                HStack {
                    Picker("Photos", selection: $model.exportOptions.scope) { ForEach(ExportScope.allCases, id: \.self) { Text($0.rawValue) } }
                    reset("Export scope", \.scope)
                }
                HStack {
                    Picker("Format", selection: $model.exportOptions.format) { ForEach(OutputFormat.allCases, id: \.self) { Text($0.rawValue) } }
                    reset("Export format", \.format)
                }
                if model.exportOptions.format == .jpeg {
                    HStack {
                        Text("Quality")
                        Slider(value: $model.exportOptions.quality, in: 0.3...1).accessibilityLabel("Export quality")
                        Text("\(Int(model.exportOptions.quality*100))%").monospacedDigit().frame(width: 42)
                        reset("Export quality", \.quality)
                    }
                } else {
                    HStack {
                        Picker("Bit depth", selection: $model.exportOptions.pngBitDepth) {
                            ForEach(PNGBitDepth.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        reset("PNG bit depth", \.pngBitDepth)
                    }
                }
                HStack {
                    Picker("Size", selection: $model.exportOptions.longEdge) {
                        Text("Full resolution").tag(0.0)
                        Text("Long edge · 3840 px").tag(3840.0)
                        Text("Long edge · 2048 px").tag(2048.0)
                        Text("Long edge · 1280 px").tag(1280.0)
                    }
                    reset("Export size", \.longEdge)
                }
                HStack {
                    Toggle("Preserve subfolder structure", isOn: $model.exportOptions.preserveFolders)
                    reset("Subfolder structure", \.preserveFolders)
                }
                HStack {
                    Picker("Existing filenames", selection: $model.exportOptions.collision) { ForEach(CollisionPolicy.allCases, id: \.self) { Text($0.rawValue) } }
                    reset("Filename collisions", \.collision)
                }
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

    private func reset<Value: Equatable>(_ title: String, _ key: WritableKeyPath<ExportOptions, Value>) -> some View {
        ResetValueButton(title: title, value: Binding(get: { model.exportOptions[keyPath: key] }, set: { model.exportOptions[keyPath: key] = $0 }), defaultValue: ExportOptions()[keyPath: key])
    }
}
