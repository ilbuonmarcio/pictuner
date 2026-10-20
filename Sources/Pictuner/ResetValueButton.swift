import SwiftUI

/// Resets through the same binding as the control, preserving its normal undo/save behavior.
struct ResetValueButton<Value: Equatable>: View {
    let title: String
    @Binding var value: Value
    let defaultValue: Value

    var body: some View {
        Button("Reset", action: reset)
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .frame(minHeight: 16)
            .fixedSize()
            .disabled(value == defaultValue)
            .help("Reset \(title.lowercased()) to default")
            .accessibilityLabel("Reset \(title)")
    }

    func reset() { value = defaultValue }
}
