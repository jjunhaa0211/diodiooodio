import SwiftUI

/// SettingsButtonRow 구조체를 정의합니다.
struct SettingsButtonRow: View {
    let icon: String
    let title: String
    let description: String?
    let buttonLabel: String
    let isDestructive: Bool
    let action: () -> Void

    init(
        icon: String,
        title: String,
        description: String? = nil,
        buttonLabel: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.buttonLabel = buttonLabel
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        SettingsRowView(icon: icon, title: title, description: description) {
            Button(action: action) {
                Text(buttonLabel)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(isDestructive ? DesignTokens.Colors.mutedIndicator : DesignTokens.Colors.textPrimary)
            }
            .buttonStyle(.plain)
            .glassButtonStyle()
        }
    }
}

// MARK: - 프리뷰

#Preview("Button Rows") {
    VStack(spacing: DesignTokens.Spacing.sm) {
        SettingsButtonRow(
            icon: "arrow.counterclockwise",
            title: "Reset All Settings",
            description: "Clear all volumes, EQ, and device routings",
            buttonLabel: "Reset",
            isDestructive: true
        ) {
            print("Reset tapped")
        }

        SettingsButtonRow(
            icon: "square.and.arrow.up",
            title: "Export Settings",
            description: "Save settings to a file",
            buttonLabel: "Export"
        ) {
            print("Export tapped")
        }
    }
    .padding()
    .frame(width: 450)
    .darkGlassBackground()
    .environment(\.colorScheme, .dark)
}
