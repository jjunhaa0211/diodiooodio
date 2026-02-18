import SwiftUI

/// SettingsIconPickerRow 구조체를 정의합니다.
struct SettingsIconPickerRow: View {
    let icon: String
    let title: String
    let language: AppLanguage
    @Binding var selection: MenuBarIconStyle

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: DesignTokens.Dimensions.settingsIconWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.rowName)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text(language.text("Choose your preferred icon style", "원하는 메뉴바 아이콘 스타일을 선택하세요"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            // 우측 아이콘 옵션 영역
            HStack(spacing: 4) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    IconOption(style: style, isSelected: selection == style) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = style
                        }
                    }
                }
            }
        }
        .hoverableRow()
    }
}

/// IconOption 구조체를 정의합니다.
private struct IconOption: View {
    let style: MenuBarIconStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Group {
                if style.isSystemSymbol {
                    Image(systemName: style.iconName)
                        .font(.system(size: 14))
                } else {
                    Image(style.iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                }
            }
            .foregroundStyle(isSelected ? DesignTokens.Colors.accentPrimary : DesignTokens.Colors.textSecondary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? DesignTokens.Colors.accentPrimary.opacity(0.15) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? DesignTokens.Colors.accentPrimary : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}


#Preview("Icon Picker Row") {
    VStack(spacing: DesignTokens.Spacing.sm) {
        SettingsIconPickerRow(
            icon: "menubar.rectangle",
            title: "Menu Bar Icon",
            language: .english,
            selection: .constant(.default)
        )
    }
    .padding(DesignTokens.Spacing.lg)
    .frame(width: DesignTokens.Dimensions.popupWidth)
    .darkGlassBackground()
    .environment(\.colorScheme, .dark)
}
