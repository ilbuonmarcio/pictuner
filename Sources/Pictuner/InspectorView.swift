import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    static let width: CGFloat = 720
    static let minimumHeight: CGFloat = 900
    var histogramHeight: CGFloat = 168
    var compact = false
    @State private var histogramRGB = true
    @State private var presetName = ""
    @State private var namingPreset = false

    var body: some View {
        VStack(spacing: 0) {
            histogram.padding(12)
            Divider()
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                    panel("Light", icon: "sun.max") { light }
                    panel("Effects", icon: "camera.filters") {
                        looks
                        Divider().padding(.vertical, 3)
                        Text("Vignette").font(.system(size: 11, weight: .semibold))
                        vignette
                        Divider().padding(.vertical, 3)
                        adjustment("Glow", \.glow, 0...1)
                        adjustment("Glow radius", \.glowRadius, 0.002...0.06, digits: 3)
                        Divider().padding(.vertical, 3)
                        adjustment("Film grain", \.grain, 0...1)
                        adjustment("Grain size", \.grainSize, 0.5...8, unit: " px", digits: 1)
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                    panel("Color", icon: "paintpalette") { color }
                    panel("Selective Color", icon: "eyedropper") { selectiveColor }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(compact ? 8 : 12)
            .disabled(!model.canEdit || model.isCropping)
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 10) {
                Menu("Presets") {
                    ForEach(model.presets) { preset in Button(preset.name) { model.applyColorAdjustments(preset.adjustments) } }
                }.fixedSize().disabled(model.presets.isEmpty)
                Button("Save Preset…") { namingPreset = true }
                Spacer()
                Button("Reset All Edits") { model.setAdjustments(Adjustments()) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .help("Reset all photo edits, framing and Date & GPS label")
                    .disabled(!model.settings.adjustments.isEdited)
            }.controlSize(.small).padding(.horizontal, 12).frame(height: 36)
                .disabled(!model.canEdit || model.isCropping)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
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
            Divider().padding(.vertical, 3)
            Text("Detail").font(.system(size: 11, weight: .semibold))
            adjustment("Noise reduction", \.noiseReduction, 0...1)
            adjustment("Clarity", \.clarity, -1...1)
            adjustment("Texture", \.texture, -1...1)
            adjustment("Sharpening", \.sharpening, 0...2)
            adjustment("Sharpen radius", \.sharpeningRadius, 0.3...5, unit: " px", digits: 1)
        }
    }
    private var color: some View {
        Group {
            adjustment("Temperature", \.temperature, -3000...3000, digits: 0)
            adjustment("Tint", \.tint, -100...100, digits: 0)
            adjustment("Saturation", \.saturation, 0...2)
            adjustment("Hue", \.hue, -180...180, unit: "°", digits: 0)
            adjustment("Vibrance", \.vibrance, -1...1)
            Divider().padding(.vertical, 3)
            Text("Color Grading").font(.system(size: 11, weight: .semibold))
            adjustment("Shadow hue", \.shadowHue, 0...360, unit: "°", digits: 0)
                .tint(Color(hue: model.settings.adjustments.shadowHue/360, saturation: 0.75, brightness: 0.95))
            adjustment("Shadow tint", \.shadowTint, 0...1)
            adjustment("Highlight hue", \.highlightHue, 0...360, unit: "°", digits: 0)
                .tint(Color(hue: model.settings.adjustments.highlightHue/360, saturation: 0.75, brightness: 0.95))
            adjustment("Highlight tint", \.highlightTint, 0...1)
            adjustment("Grading balance", \.gradingBalance, -1...1)
        }
    }
    private var looks: some View {
        Group {
            adjustment("Black & white", \.monochrome, 0...1)
            adjustment("Sepia", \.sepia, 0...1)
        }
    }
    private var vignette: some View {
        Group {
            adjustment("Strength", \.vignette, 0...1)
            adjustment("Radius", \.vignetteRadius, 0.1...1.8)
            adjustment("Softness", \.vignetteSoftness, 0.05...1.5)
        }
    }
    static func histogramHeight(for availableHeight: CGFloat) -> CGFloat {
        availableHeight >= 1000 ? 168 : 112
    }

    static func needsCompactSpacing(height: CGFloat, histogramHeight: CGFloat) -> Bool {
        height < minimumHeight + histogramHeight - 112
    }

    private func panel<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(.tint).accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 0)
            }.font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, compact ? 4 : 8)
                .background(.white.opacity(0.045))
            Divider()
            VStack(alignment: .leading, spacing: compact ? 2 : 4) { content() }
                .padding(.horizontal, 10).padding(.vertical, compact ? 6 : 10)
        }
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.13)) }
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
    private var histogram: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Histogram").font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("Show clipping", isOn: $model.showClipping).font(.system(size: 11)).toggleStyle(.checkbox)
                    .help("Red marks any sRGB channel at white; blue marks any channel at black.")
                    .disabled(model.preview == nil)
                Picker("Channels", selection: $histogramRGB) { Text("RGB").tag(true); Text("Luma").tag(false) }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small).frame(width: 112)
                ResetValueButton(title: "Histogram channels", value: $histogramRGB, defaultValue: true)
            }
            HistogramView(data: model.showingOriginal ? model.preview?.originalHistogram : model.preview?.histogram, rgb: histogramRGB)
                .frame(height: histogramHeight).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
        }
    }
    private func adjustment(_ label: String, _ key: WritableKeyPath<Adjustments, Double>, _ range: ClosedRange<Double>, unit: String = "", digits: Int = 2) -> some View {
        EditSlider(title: label, value: model.adjustmentBinding(key), defaultValue: Adjustments()[keyPath: key], range: range, unit: unit, digits: digits, onEditing: model.editingGesture)
    }
    private func selectiveSlider(_ label: String, _ key: WritableKeyPath<SelectiveColor, Double>, _ range: ClosedRange<Double>) -> some View {
        EditSlider(title: label, value: model.selectiveBinding(key), defaultValue: SelectiveColor()[keyPath: key], range: range, onEditing: model.editingGesture)
    }
    private var sampledColor: Binding<SIMD3<Double>> {
        Binding(get: {
            let s = model.settings.adjustments.selective
            return SIMD3(s.hue, s.saturation, s.brightness)
        }, set: { sample in
            var a = model.settings.adjustments
            a.selective.hue = sample.x; a.selective.saturation = sample.y; a.selective.brightness = sample.z
            model.setAdjustments(a)
        })
    }
    private var selectiveColor: some View {
        Group {
            HStack(spacing: 8) {
                Toggle("Enabled", isOn: Binding(get: { model.settings.adjustments.selective.enabled }, set: { value in
                    var a = model.settings.adjustments; a.selective.enabled = value; model.setAdjustments(a)
                    if !value { model.showMask = false; model.pickingColor = false }
                })).font(.system(size: 11)).toggleStyle(.checkbox)
                    .accessibilityLabel("Selective color").help("Selects matching colors throughout the image.")
                Spacer(minLength: 0)
                Circle().fill(Color(hue: model.settings.adjustments.selective.hue, saturation: model.settings.adjustments.selective.saturation, brightness: model.settings.adjustments.selective.brightness))
                    .frame(width: 18, height: 18).overlay(Circle().stroke(.white.opacity(0.2)))
                Button(model.pickingColor ? "Cancel" : "Pick Color…") {
                    model.pickingColor.toggle(); model.showMask = false; model.showingOriginal = false
                }.controlSize(.small).disabled(model.preview == nil || model.isRendering)
                ResetValueButton(title: "Sampled color", value: sampledColor,
                    defaultValue: SIMD3(SelectiveColor().hue, SelectiveColor().saturation, SelectiveColor().brightness))
            }
            Group {
                selectiveSlider("Hue range", \.hueRange, 0...0.5)
                selectiveSlider("Saturation tolerance", \.saturationTolerance, 0...1)
                selectiveSlider("Brightness tolerance", \.brightnessTolerance, 0...1)
                selectiveSlider("Transition softness", \.softness, 0.01...0.5)
                selectiveSlider("Selected saturation", \.selectedSaturation, 0...2)
                selectiveSlider("Selected brightness", \.selectedBrightness, -2...2)
                selectiveSlider("Other colors' saturation", \.outsideSaturation, 0...1)
                Toggle("Show mask", isOn: $model.showMask).font(.system(size: 11)).toggleStyle(.checkbox)
                    .disabled(!model.settings.adjustments.selective.enabled)
            }
        }
    }
}

private struct EditSlider: View {
    let title: String
    @Binding var value: Double
    let defaultValue: Double
    let range: ClosedRange<Double>
    var unit = ""
    var digits = 2
    let onEditing: (Bool) -> Void
    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.9)
                .frame(width: 124, alignment: .leading)
            Slider(value: $value, in: range, onEditingChanged: onEditing)
                .controlSize(.mini).accessibilityLabel(title).frame(minWidth: 55)
            Text(String(format: "%.*f", digits, value)+unit).monospacedDigit().foregroundStyle(.primary.opacity(0.8))
                .frame(width: 45, alignment: .trailing)
            ResetValueButton(title: title, value: $value, defaultValue: defaultValue)
        }.font(.system(size: 11)).frame(height: 20)
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
