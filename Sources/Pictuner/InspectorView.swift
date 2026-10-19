import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    @State private var histogramRGB = true
    @State private var presetName = ""
    @State private var namingPreset = false
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("EDIT").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary); Spacer(); Button("Reset") { model.setAdjustments(Adjustments()) }.buttonStyle(.plain).font(.system(size: 11)).disabled(!model.canEdit) }.padding(18)
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
                    .help("Only marked photos are exported. Shortcut: ⇧⌘G.")
                    .accessibilityValue(model.settings.exportReady ? "Marked for export" : "Not marked for export")
                    HStack {
                        Button(action: model.toggleFavorite) { Label("Favorite", systemImage: model.settings.favorite ? "star.fill" : "star") }.tint(model.settings.favorite ? .yellow : .secondary)
                        Spacer()
                        Button(action: model.toggleRejected) { Label("Reject", systemImage: model.settings.rejected ? "xmark.circle.fill" : "xmark.circle") }.tint(model.settings.rejected ? .red : .secondary)
                    }.font(.system(size: 11)).buttonStyle(.plain).disabled(!model.canEdit)
                    Divider()
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
                        Menu("Saved presets") {
                            if model.presets.isEmpty { Text("No saved presets yet") }
                            ForEach(model.presets) { preset in Button(preset.name) { model.setAdjustments(preset.adjustments) } }
                        }
                        Button("Save Current as Preset…") { namingPreset = true }.font(.system(size: 11))
                    }
                    section("Vignette", icon: "circle.dotted.circle") {
                        adjustment("Strength", \.vignette, 0...1)
                        adjustment("Radius", \.vignetteRadius, 0.1...1.8)
                        adjustment("Softness", \.vignetteSoftness, 0.05...1.5)
                    }
                    Divider()
                    VStack(spacing: 8) {
                        Button("Mark Selected for Export") { model.setExportReady(true, for: model.selectedIDs) }
                            .disabled(!model.canEdit || model.selectedIDs.isEmpty)
                        Button("Unmark Selected for Export") { model.setExportReady(false, for: model.selectedIDs) }
                            .disabled(!model.canEdit || model.selectedIDs.isEmpty)
                        HStack {
                            Button("Copy Edits", action: model.copyAdjustments)
                            Button("Paste Edits", action: model.pasteAdjustments).disabled(!model.hasCopiedAdjustments)
                        }
                        Button("Apply to \(model.selectedCount) Selected", action: model.applyToSelection).disabled(model.selectedCount < 2)
                        Text("⌘-click thumbnails to select more photos.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }.padding(.horizontal, 18).padding(.bottom, 24)
                    .disabled(model.activePhoto == nil)
            }
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .alert("Save Preset", isPresented: $namingPreset) {
                TextField("Preset name", text: $presetName)
                Button("Cancel", role: .cancel) { presetName = "" }
                Button("Save") { model.savePreset(name: presetName); presetName = "" }
            } message: { Text("Save these adjustments for another photo.") }
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
            content().disabled(!model.canEdit)
        }
    }
    private func adjustment(_ label: String, _ key: WritableKeyPath<Adjustments, Double>, _ range: ClosedRange<Double>, unit: String = "", digits: Int = 2) -> some View {
        EditSlider(title: label, value: model.adjustmentBinding(key), range: range, unit: unit, digits: digits, onEditing: model.editingGesture)
    }
    private func selectiveSlider(_ label: String, _ key: WritableKeyPath<SelectiveColor, Double>, _ range: ClosedRange<Double>) -> some View {
        EditSlider(title: label, value: model.selectiveBinding(key), range: range, onEditing: model.editingGesture)
    }
    private func presetButton(_ name: String, make: @escaping () -> Adjustments) -> some View {
        Button(name) { model.setAdjustments(make()) }.font(.system(size: 10)).frame(maxWidth: .infinity)
    }
    private var selectiveColor: some View {
        section("Selective Color", icon: "eyedropper.halffull") {
            Toggle("Enable color isolation", isOn: Binding(get: { model.settings.adjustments.selective.enabled }, set: { value in var a = model.settings.adjustments; a.selective.enabled = value; model.setAdjustments(a) })).font(.system(size: 11)).toggleStyle(.checkbox)
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
                Toggle("Preview color mask", isOn: $model.showMask).font(.system(size: 11)).toggleStyle(.checkbox)
                Text("Similar colors anywhere in the photo are included.").font(.system(size: 10)).foregroundStyle(.secondary)
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
