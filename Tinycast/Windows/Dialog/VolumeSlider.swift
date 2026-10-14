import SwiftUI

struct VolumeSlider: View {
    let state: VolumeState

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: VolumeLevel.symbol(level: state.level))
                .font(Theme.Typography.menuIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.menuIcon)
            Slider(value: level, in: 0...1)
                .labelsHidden()
                .tint(Theme.Colors.textPrimary)
                .accessibilityLabel("Output volume")
            Text(VolumeLevel.percentage(state.level))
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .frame(width: Theme.Size.volumeReadout, alignment: .trailing)
        }
    }

    private var level: Binding<Double> {
        Binding(
            get: { state.level },
            set: { state.level = VolumeLevel.clamped($0) })
    }
}
