import SwiftUI

/// MainUI 좌측 탭 선택 사이드바입니다.
struct MainUISidebar: View {
    @Binding var selectedTab: MainUITab
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            ForEach(MainUITab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tab.title(language))
                                .font(.system(size: 14, weight: .semibold))
                            Text(tab.subtitle(language))
                                .font(.system(size: 11, weight: .regular))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedTab == tab ? DesignTokens.Colors.accentPrimary.opacity(0.18) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selectedTab == tab ? DesignTokens.Colors.accentPrimary.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
    }
}
