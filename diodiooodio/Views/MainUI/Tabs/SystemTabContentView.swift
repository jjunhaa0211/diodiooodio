import SwiftUI

/// 시스템 통합 탭 본문입니다.
/// 이후 배터리, 네트워크, 창 관리, 단축키 등의 모듈을 이 탭에 레고처럼 확장할 수 있습니다.
struct SystemTabContentView: View {
    let language: AppLanguage

    private func t(_ english: String, _ korean: String) -> String {
        language.text(english, korean)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("System", "시스템"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text(t("This tab is reserved for Mac-wide integration features.", "이 탭은 맥북 통합 관리 기능을 확장하는 영역입니다."))
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                placeholderRow(t("Battery status monitor", "배터리 상태 모니터"))
                placeholderRow(t("Wi-Fi/Bluetooth quick controls", "와이파이/블루투스 빠른 제어"))
                placeholderRow(t("Window/app focus automation", "창/앱 포커스 자동화"))
                placeholderRow(t("I/O device profile switching", "입출력 장치 프로필 전환"))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func placeholderRow(_ title: String) -> some View {
        HStack {
            Image(systemName: "plus.circle")
                .foregroundStyle(DesignTokens.Colors.accentPrimary)
            Text(title)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            Text(t("Planned", "확장 예정"))
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}
