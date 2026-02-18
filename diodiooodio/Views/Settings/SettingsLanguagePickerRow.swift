import SwiftUI

/// SettingsLanguagePickerRow 구조체를 정의합니다.
struct SettingsLanguagePickerRow: View {
    let icon: String
    let title: String
    let description: String?
    @Binding var selection: AppLanguage

    var body: some View {
        SettingsRowView(icon: icon, title: title, description: description) {
            HStack(spacing: 6) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = language
                        }
                    } label: {
                        Text(language.displayName)
                            .font(DesignTokens.Typography.pickerText)
                            .foregroundStyle(selection == language ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                RoundedRectangle(cornerRadius: DesignTokens.Dimensions.buttonRadius)
                                    .fill(selection == language ? DesignTokens.Colors.accentPrimary.opacity(0.2) : Color.clear)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Dimensions.buttonRadius)
                                    .stroke(selection == language ? DesignTokens.Colors.accentPrimary : Color.clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview("Language Picker Row") {
    VStack(spacing: DesignTokens.Spacing.sm) {
        SettingsLanguagePickerRow(
            icon: "globe",
            title: "Language",
            description: "Choose app language",
            selection: .constant(.english)
        )
    }
    .padding()
    .frame(width: 480)
    .darkGlassBackground()
}
