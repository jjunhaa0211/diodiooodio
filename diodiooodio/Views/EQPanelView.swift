import SwiftUI

struct EQPanelView: View {
    @Binding var settings: EQSettings
    let onPresetSelected: (EQPreset) -> Void
    let onSettingsChanged: (EQSettings) -> Void

    private let frequencyLabels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    private var currentPreset: EQPreset? {
        EQPreset.allCases.first { preset in
            preset.settings.bandGains == settings.bandGains
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Toggle("", isOn: $settings.isEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.7)
                        .labelsHidden()
                        .onChange(of: settings.isEnabled) { _, _ in
                            onSettingsChanged(settings)
                        }
                    Text("EQ")
                        .font(DesignTokens.Typography.pickerText)
                        .foregroundColor(.primary)
                }

                Spacer()

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("Preset")
                        .font(DesignTokens.Typography.pickerText)
                        .foregroundColor(DesignTokens.Colors.textSecondary)

                    EQPresetPicker(
                        selectedPreset: currentPreset,
                        onPresetSelected: onPresetSelected
                    )
                }
            }
            .zIndex(1)

            HStack(spacing: 22) {
                ForEach(0..<10, id: \.self) { index in
                    EQSliderView(
                        frequency: frequencyLabels[index],
                        gain: Binding(
                            get: { settings.bandGains[index] },
                            set: { newValue in
                                settings.bandGains[index] = newValue
                                onSettingsChanged(settings)
                            }
                        )
                    )
                    .frame(width: 26, height: 100)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(DesignTokens.Colors.recessedBackground)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack {
        EQPanelView(
            settings: .constant(EQSettings()),
            onPresetSelected: { _ in },
            onSettingsChanged: { _ in }
        )
    }
    .padding(.horizontal, DesignTokens.Spacing.sm)
    .padding(.vertical, DesignTokens.Spacing.xs)
    .background {
        RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
            .fill(DesignTokens.Colors.recessedBackground)
    }
    .frame(width: 550)
    .padding()
    .background(Color.black)
}
