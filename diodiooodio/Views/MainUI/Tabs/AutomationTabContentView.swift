import SwiftUI

/// 자동화 탭 본문입니다.
/// 앱/장치/시간 기반 규칙을 추가할 확장 지점입니다.
struct AutomationTabContentView: View {
    let language: AppLanguage

    private func t(_ english: String, _ korean: String) -> String {
        language.text(english, korean)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("Automation", "자동화"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text(t("Examples: switch output when Zoom starts, or apply EQ when Apple Music launches.", "예: Zoom 실행 시 헤드셋 출력 전환, Apple Music 실행 시 EQ 프리셋 적용"))
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                placeholderRule(
                    t("App launch trigger", "앱 실행 트리거"),
                    t("Apply routing automatically when a target app starts", "특정 앱 실행 시 라우팅 자동 적용")
                )
                placeholderRule(
                    t("Device connection trigger", "장치 연결 트리거"),
                    t("Switch output profile on Bluetooth connection", "블루투스 연결 시 출력 프로필 전환")
                )
                placeholderRule(
                    t("Schedule trigger", "시간대 트리거"),
                    t("Switch working/night profiles automatically", "업무 시간/야간 모드 자동 전환")
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func placeholderRule(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(desc)
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}
