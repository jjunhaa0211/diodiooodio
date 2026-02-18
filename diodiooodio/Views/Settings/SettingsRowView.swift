import SwiftUI

/// SettingsRowView 구조체를 정의합니다.
struct SettingsRowView<Control: View>: View {
    let icon: String
    let title: String
    let description: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: DesignTokens.Dimensions.iconSizeSmall))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Colors.interactiveDefault)
                .frame(width: DesignTokens.Dimensions.settingsIconWidth, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.rowName)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                if let description {
                    Text(description)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            control()
        }
        .hoverableRow()
    }
}

// MARK: - 프리뷰

#Preview("Settings Row") {
    VStack(spacing: DesignTokens.Spacing.sm) {
        SettingsRowView(
            icon: "power",
            title: "Launch at Login",
            description: "Start diodiooodio when you log in"
        ) {
            Toggle("", isOn: .constant(true))
                .toggleStyle(.switch)
                .scaleEffect(0.8)
                .labelsHidden()
        }

        SettingsRowView(
            icon: "speaker.wave.2",
            title: "Default Volume",
            description: nil
        ) {
            Text("100%")
                .font(DesignTokens.Typography.percentage)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
    .padding()
    .frame(width: 400)
    .darkGlassBackground()
    .environment(\.colorScheme, .dark)
}
