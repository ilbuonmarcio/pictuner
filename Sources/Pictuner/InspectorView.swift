import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    @State private var histogramRGB = true
    @State private var presetName = ""
    @State private var namingPreset = false
    var body: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); Button("Reset") { model.setAdjustments(Adjustments()) }.buttonStyle(.plain).font(.system(size: 11)).disabled(!model.canEdit || model.isCropping) }.padding(18)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    histogram
                    Button(action: model.toggleExportReady) {
                        Label(model.settings.exportReady ? "Included in Export" : "Include in Export", systemImage: model.settings.exportReady ? "checkmark.circle.fill" : "circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.settings.exportReady ? .green : .secondary)
                    .disabled(!model.canEdit)
                    .help("Include in Export · ⇧⌘G")
                    .accessibilityValue(model.settings.exportReady ? "Marked for export" : "Not marked for export")
                    HStack {
                        Button(action: model.toggleFavorite) { Label("Favorite", systemImage: model.settings.favorite ? "star.fill" : "star") }.tint(model.settings.favorite ? .yellow : .secondary)
                        Spacer()
                        Button(action: model.toggleRejected) { Label("Reject", systemImage: model.settings.rejected ? "xmark.circle.fill" : "xmark.circle") }.tint(model.settings.rejected ? .red : .secondary)
                    }.font(.system(size: 11)).buttonStyle(.plain).disabled(!model.canEdit)
                    Divider()
                    transform
                    section("Light", icon: "sun.max") {
                        adjustment("Exposure", \.exposure, -4...4, unit: " EV")
                        adjustment("Brightness", \.brightness, -0.3...0.3)
                        adjustment("Contrast", \.contrast, 0.5...1.8)
                        adjustment("Highlights", \.highlights, 0...1)
                        adjustment("Shadows", \.shadows, 0...1)
                    }
                    section("Color", icon: "circle.lefthalf.filled") {
                        adjustment("Temperature", \.temperature, -3000...3000, digits: 0)
                        adjustment("Tint", \.tint, -100...100, digits: 0)
                        adjustment("Saturation", \.saturation, 0...2)
                        adjustment("Hue", \.hue, -180...180, unit: "°", digits: 0)
                    }
                    selectiveColor
                    section("Looks", icon: "camera.filters") {
                        HStack(spacing: 6) {
                            presetButton("Natural") { Adjustments() }
                            presetButton("Mono") { var a = Adjustments(); a.monochrome = 1; return a }
                            presetButton("Sepia") { var a = Adjustments(); a.sepia = 0.8; return a }
                        }
                        adjustment("Black & white", \.monochrome, 0...1)
                        adjustment("Sepia", \.sepia, 0...1)
                        Menu("Presets") {
                            ForEach(model.presets) { preset in Button(preset.name) { model.applyColorAdjustments(preset.adjustments) } }
                        }.disabled(model.presets.isEmpty)
                        Button("Save Preset…") { namingPreset = true }.font(.system(size: 11))
                    }
                    section("Vignette", icon: "circle.dotted.circle") {
                        adjustment("Strength", \.vignette, 0...1)
                        adjustment("Radius", \.vignetteRadius, 0.1...1.8)
                        adjustment("Softness", \.vignetteSoftness, 0.05...1.5)
                    }
                    Divider()
                    VStack(spacing: 8) {
                        if model.selectedCount > 1 {
                            Button("Mark Selected for Export") { model.setExportReady(true, for: model.selectedIDs) }.disabled(!model.canEdit)
                            Button("Unmark Selected for Export") { model.setExportReady(false, for: model.selectedIDs) }.disabled(!model.canEdit)
                            Button("Apply Edits to \(model.selectedCount) Selected", action: model.applyToSelection).disabled(!model.canEdit)
                        }
                        HStack {
                            Button("Copy Edits", action: model.copyAdjustments)
                            Button("Paste Edits", action: model.pasteAdjustments).disabled(!model.hasCopiedAdjustments)
                        }
                    }.frame(maxWidth: .infinity).disabled(model.isCropping)
                }.padding(.horizontal, 18).padding(.bottom, 24)
                    .disabled(model.activePhoto == nil)
            }
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .alert("Save Preset", isPresented: $namingPreset) {
                TextField("Preset name", text: $presetName)
                Button("Cancel", role: .cancel) { presetName = "" }
                Button("Save") { model.savePreset(name: presetName); presetName = "" }
            }
    }

    private var transform: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transform", systemImage: "crop.rotate").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 12) {
                Button(action: model.beginCrop) { Image(systemName: "crop") }.help("Crop").accessibilityLabel("Crop")
                    .disabled(model.preview == nil || model.isCropping)
                Spacer()
                Button { model.rotate(clockwise: false) } label: { Image(systemName: "rotate.left") }.help("Rotate left 90°").accessibilityLabel("Rotate left 90 degrees")
                    .disabled(model.isCropping)
                Button { model.rotate(clockwise: true) } label: { Image(systemName: "rotate.right") }.help("Rotate right 90°").accessibilityLabel("Rotate right 90 degrees")
                    .disabled(model.isCropping)
                Divider().frame(height: 16)
                Button { model.flip(horizontal: true) } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }.help("Flip horizontally").accessibilityLabel("Flip horizontally")
                    .disabled(model.isCropping)
                Button { model.flip(horizontal: false) } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }.help("Flip vertically").accessibilityLabel("Flip vertically")
                    .disabled(model.isCropping)
            }.buttonStyle(.borderless).font(.system(size: 15))
            if model.isCropping {
                Picker("Aspect", selection: Binding(get: { model.cropAspect }, set: model.setCropAspect)) {
                    ForEach(CropAspect.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(model.preview == nil)
                HStack {
                    Button("Reset", action: model.resetCropDraft).help("Reset crop bounds").disabled(model.preview == nil)
                    Spacer()
                    Button("Cancel", action: model.cancelCrop)
                    Button("Apply", action: model.applyCrop).buttonStyle(.borderedProminent).disabled(model.preview == nil)
                }.controlSize(.small)
            } else if model.settings.adjustments.geometry.crop != nil {
                Button("Remove Crop", action: model.clearCrop).font(.system(size: 11))
            }
        }.disabled(!model.canEdit)
    }

    private var histogram: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Histogram").font(.system(size: 11, weight: .medium))
                Spacer()
                Picker("Channels", selection: $histogramRGB) { Text("RGB").tag(true); Text("Luma").tag(false) }.labelsHidden().pickerStyle(.segmented).frame(width: 112)
            }
            HistogramView(data: model.showingOriginal ? model.preview?.originalHistogram : model.preview?.histogram, rgb: histogramRGB).frame(height: 85)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
            Toggle("Show clipping", isOn: $model.showClipping).font(.system(size: 10)).toggleStyle(.checkbox)
                .help("Red marks any sRGB channel at white; blue marks any channel at black.")
        }
    }
    private func section<C: View>(_ name: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(name, systemImage: icon).font(.system(size: 12, weight: .semibold))
            content().disabled(!model.canEdit || model.isCropping)
        }
    }
    private func adjustment(_ label: String, _ key: WritableKeyPath<Adjustments, Double>, _ range: ClosedRange<Double>, unit: String = "", digits: Int = 2) -> some View {
        EditSlider(title: label, value: model.adjustmentBinding(key), range: range, unit: unit, digits: digits, onEditing: model.editingGesture)
    }
    private func selectiveSlider(_ label: String, _ key: WritableKeyPath<SelectiveColor, Double>, _ range: ClosedRange<Double>) -> some View {
        EditSlider(title: label, value: model.selectiveBinding(key), range: range, onEditing: model.editingGesture)
    }
    private func presetButton(_ name: String, make: @escaping () -> Adjustments) -> some View {
        Button(name) { model.applyColorAdjustments(make()) }.font(.system(size: 10)).frame(maxWidth: .infinity)
    }
    private var selectiveColor: some View {
        section("Selective Color", icon: "eyedropper.halffull") {
            Toggle("Enabled", isOn: Binding(get: { model.settings.adjustments.selective.enabled }, set: { value in var a = model.settings.adjustments; a.selective.enabled = value; model.setAdjustments(a) })).font(.system(size: 11)).toggleStyle(.checkbox)
                .accessibilityLabel("Selective color")
                .help("Selects matching colors throughout the image.")
            HStack {
                Circle().fill(Color(hue: model.settings.adjustments.selective.hue, saturation: model.settings.adjustments.selective.saturation, brightness: model.settings.adjustments.selective.brightness)).frame(width: 21, height: 21).overlay(Circle().stroke(.white.opacity(0.2)))
                Button(model.pickingColor ? "Cancel Picking" : "Pick Color…") { model.pickingColor.toggle(); model.showMask = false; model.showingOriginal = false }.disabled(model.preview == nil || model.isRendering)
                Spacer()
            }
            if model.settings.adjustments.selective.enabled {
                selectiveSlider("Hue range", \.hueRange, 0...0.5)
                selectiveSlider("Saturation tolerance", \.saturationTolerance, 0...1)
                selectiveSlider("Brightness tolerance", \.brightnessTolerance, 0...1)
                selectiveSlider("Transition softness", \.softness, 0.01...0.5)
                selectiveSlider("Selected saturation", \.selectedSaturation, 0...2)
                selectiveSlider("Selected brightness", \.selectedBrightness, -2...2)
                selectiveSlider("Other colors' saturation", \.outsideSaturation, 0...1)
                Toggle("Show mask", isOn: $model.showMask).font(.system(size: 11)).toggleStyle(.checkbox)
            }
        }
    }
}

private struct EditSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = ""
    var digits = 2
    let onEditing: (Bool) -> Void
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.*f", digits, value)+unit).monospacedDigit().foregroundStyle(.primary.opacity(0.8))
            }.font(.system(size: 10))
            Slider(value: $value, in: range, onEditingChanged: onEditing).controlSize(.mini).accessibilityLabel(title)
        }
    }
}

private struct HistogramView: View {
    let data: HistogramData?
    let rgb: Bool
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 7, dy: 7)
            for fraction in [0.25, 0.5, 0.75] {
                var grid = Path(); grid.move(to: CGPoint(x: rect.minX+rect.width*fraction, y: rect.minY)); grid.addLine(to: CGPoint(x: rect.minX+rect.width*fraction, y: rect.maxY))
                context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)
            }
            guard let data else { return }
            let channels: [([Double], Color)] = rgb ? [(data.red, .red), (data.green, .green), (data.blue, .blue)] : [(data.luminance, .white)]
            let maximum = max(1, channels.flatMap { $0.0 }.max() ?? 1)
            for (values, color) in channels {
                var path = Path(); path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                for index in values.indices {
                    path.addLine(to: CGPoint(x: rect.minX+Double(index)/255*rect.width, y: rect.maxY-sqrt(values[index]/maximum)*rect.height))
                }
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.22)))
                context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 0.8)
            }
        }.accessibilityLabel(rgb ? "Red, green and blue histogram" : "Luminance histogram")
    }
}
