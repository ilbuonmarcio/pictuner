import SwiftUI

enum InspectorSection: String, CaseIterable, Identifiable {
    case light = "Light", color = "Color", selective = "Selective", effects = "Effects"
    var id: String { rawValue }
}

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedSection: InspectorSection
    @State private var histogramRGB = true
    @State private var presetName = ""
    @State private var namingPreset = false

    init(section: InspectorSection = .light) {
        _selectedSection = State(initialValue: section)
    }

    var body: some View {
        VStack(spacing: 0) {
            histogram.padding(16)
            Picker("Adjustments", selection: $selectedSection) {
                ForEach(InspectorSection.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().pickerStyle(.segmented).controlSize(.small)
                .padding(.horizontal, 16).padding(.bottom, 16)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                switch selectedSection {
                case .light: light
                case .color: color
                case .selective: selectiveColor
                case .effects: effects
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .disabled(!model.canEdit || model.isCropping)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Spacer()
                Button("Reset All Edits") { model.setAdjustments(Adjustments()) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .help("Reset color, effects, crop, rotation and mirror settings")
                    .disabled(!model.canEdit || model.isCropping || !model.settings.adjustments.isEdited)
            }.padding(.horizontal, 16).frame(height: 38)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .onChange(of: selectedSection) { _, section in
                if section != .selective { model.pickingColor = false; model.showMask = false }
            }
            .alert("Save Preset", isPresented: $namingPreset) {
                TextField("Preset name", text: $presetName)
                Button("Cancel", role: .cancel) { presetName = "" }
                Button("Save") { model.savePreset(name: presetName); presetName = "" }
            }
    }

    private var light: some View {
        Group {
            adjustment("Exposure", \.exposure, -4...4, unit: " EV")
            adjustment("Brightness", \.brightness, -0.3...0.3)
            adjustment("Contrast", \.contrast, 0.5...1.8)
            adjustment("Highlights", \.highlights, 0...1)
            adjustment("Shadows", \.shadows, 0...1)
        }
    }
    private var color: some View {
        Group {
            adjustment("Temperature", \.temperature, -3000...3000, digits: 0)
            adjustment("Tint", \.tint, -100...100, digits: 0)
            adjustment("Saturation", \.saturation, 0...2)
            adjustment("Hue", \.hue, -180...180, unit: "°", digits: 0)
        }
    }
    private var effects: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                Text("Looks").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 6) {
                    presetButton("Natural") { Adjustments() }
                    presetButton("Mono") { var a = Adjustments(); a.monochrome = 1; return a }
                    presetButton("Sepia") { var a = Adjustments(); a.sepia = 0.8; return a }
                }
                adjustment("Black & white", \.monochrome, 0...1)
                adjustment("Sepia", \.sepia, 0...1)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Vignette").font(.system(size: 12, weight: .semibold))
                adjustment("Strength", \.vignette, 0...1)
                adjustment("Radius", \.vignetteRadius, 0.1...1.8)
                adjustment("Softness", \.vignetteSoftness, 0.05...1.5)
            }
            HStack {
                Menu("Presets") {
                    ForEach(model.presets) { preset in Button(preset.name) { model.applyColorAdjustments(preset.adjustments) } }
                }.disabled(model.presets.isEmpty)
                Button("Save Preset…") { namingPreset = true }
            }.controlSize(.small)
        }
    }
    private var histogram: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Histogram").font(.system(size: 11, weight: .medium))
                Spacer()
                Picker("Channels", selection: $histogramRGB) { Text("RGB").tag(true); Text("Luma").tag(false) }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small).frame(width: 112)
            }
            HistogramView(data: model.showingOriginal ? model.preview?.originalHistogram : model.preview?.histogram, rgb: histogramRGB)
                .frame(height: 72).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
            Toggle("Show clipping", isOn: $model.showClipping).font(.system(size: 11)).toggleStyle(.checkbox)
                .help("Red marks any sRGB channel at white; blue marks any channel at black.")
                .disabled(model.preview == nil)
        }
    }
    private func adjustment(_ label: String, _ key: WritableKeyPath<Adjustments, Double>, _ range: ClosedRange<Double>, unit: String = "", digits: Int = 2) -> some View {
        EditSlider(title: label, value: model.adjustmentBinding(key), range: range, unit: unit, digits: digits, onEditing: model.editingGesture)
    }
    private func selectiveSlider(_ label: String, _ key: WritableKeyPath<SelectiveColor, Double>, _ range: ClosedRange<Double>) -> some View {
        EditSlider(title: label, value: model.selectiveBinding(key), range: range, onEditing: model.editingGesture)
    }
    private func presetButton(_ name: String, make: @escaping () -> Adjustments) -> some View {
        Button(name) { model.applyColorAdjustments(make()) }.font(.system(size: 11)).frame(maxWidth: .infinity)
    }
    private var selectiveColor: some View {
        Group {
            HStack(spacing: 8) {
                Toggle("Enabled", isOn: Binding(get: { model.settings.adjustments.selective.enabled }, set: { value in
                    var a = model.settings.adjustments; a.selective.enabled = value; model.setAdjustments(a)
                    if !value { model.showMask = false }
                })).font(.system(size: 11)).toggleStyle(.checkbox)
                    .accessibilityLabel("Selective color").help("Selects matching colors throughout the image.")
                Spacer(minLength: 0)
                Circle().fill(Color(hue: model.settings.adjustments.selective.hue, saturation: model.settings.adjustments.selective.saturation, brightness: model.settings.adjustments.selective.brightness))
                    .frame(width: 18, height: 18).overlay(Circle().stroke(.white.opacity(0.2)))
                Button(model.pickingColor ? "Cancel" : "Pick Color…") {
                    model.pickingColor.toggle(); model.showMask = false; model.showingOriginal = false
                }.controlSize(.small).disabled(model.preview == nil || model.isRendering)
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
            }.font(.system(size: 11))
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
