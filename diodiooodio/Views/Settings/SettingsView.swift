import SwiftUI

/// 설정 팝업의 루트 컨테이너입니다.
/// 실제 섹션 구현은 기능별 컴포넌트로 분리해 조립합니다.
struct SettingsView: View {
    @Binding var settings: AppSettings
    let onResetAll: () -> Void

    @State private var showResetConfirmation = false

    private var language: AppLanguage { settings.language }

    /// 현재 언어에 맞는 문자열을 반환합니다.
    private func t(_ english: String, _ korean: String) -> String {
        language.text(english, korean)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                SettingsGeneralSection(settings: $settings, language: language, t: t)
                SettingsAudioSection(settings: $settings, t: t)
                SettingsNotificationsSection(settings: $settings, t: t)
                SettingsDataSection(
                    showResetConfirmation: $showResetConfirmation,
                    onResetAll: onResetAll,
                    t: t
                )
                SettingsAboutFooter(t: t)
            }
        }
        .scrollIndicators(.never)
    }
}
