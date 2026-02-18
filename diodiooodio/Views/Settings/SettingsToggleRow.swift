import SwiftUI

/// SettingsToggleRow 구조체를 정의합니다.
struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let description: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRowView(icon: icon, title: title, description: description) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
                .labelsHidden()
        }
    }
}

// MARK: - 프리뷰

#Preview("Toggle Rows") {
    VStack(spacing: DesignTokens.Spacing.sm) {
        SettingsToggleRow(
            icon: "power",
            title: "Launch at Login",
            description: "Start diodiooodio when you log in",
            isOn: .constant(true)
        )

        SettingsToggleRow(
            icon: "bell",
            title: "Device Disconnect Alerts",
            description: "Show notification when device disconnects",
            isOn: .constant(false)
        )
    }
    .padding()
    .frame(width: 400)
    .darkGlassBackground()
    .environment(\.colorScheme, .dark)
}
