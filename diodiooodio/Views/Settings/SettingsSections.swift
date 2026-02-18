import SwiftUI

// MARK: - 기능: 공통 섹션 래퍼

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            SectionHeader(title: title)
                .padding(.bottom, DesignTokens.Spacing.xs)
            content
        }
    }
}

// MARK: - 기능: 일반

struct SettingsGeneralSection: View {
    @Binding var settings: AppSettings
    let language: AppLanguage
    let t: (String, String) -> String

    var body: some View {
        SettingsSection(title: t("Overall Settings", "총괄 세팅")) {
            SettingsToggleRow(
                icon: "power",
                title: t("Launch at Login", "로그인 시 자동 실행"),
                description: t("Start diodiooodio when you log in", "로그인할 때 diodiooodio 자동 실행"),
                isOn: $settings.launchAtLogin
            )

            SettingsLanguagePickerRow(
                icon: "globe",
                title: t("Language", "언어"),
                description: t("Choose app language", "앱 언어를 선택하세요"),
                selection: $settings.language
            )

            SettingsIconPickerRow(
                icon: "menubar.rectangle",
                title: t("Menu Bar Icon", "메뉴바 아이콘"),
                language: language,
                selection: $settings.menuBarIconStyle
            )
        }
    }
}

// MARK: - 기능: 오디오

struct SettingsAudioSection: View {
    @Binding var settings: AppSettings
    let t: (String, String) -> String

    var body: some View {
        SettingsSection(title: t("Audio", "오디오")) {
            SettingsSliderRow(
                icon: "speaker.wave.2",
                title: t("Default App Volume", "기본 앱 볼륨"),
                description: t("Starting volume for newly detected apps", "새로 감지된 앱의 시작 볼륨"),
                value: $settings.defaultNewAppVolume,
                range: 0.1...1.0
            )

            SettingsSliderRow(
                icon: "speaker.wave.3",
                title: t("Max Volume Boost", "최대 볼륨 부스트"),
                description: t("Upper limit for per-app volume boost", "앱별 볼륨 부스트 상한"),
                value: $settings.maxVolumeBoost,
                range: 1.0...4.0
            )
        }
    }
}

// MARK: - 기능: 알림

struct SettingsNotificationsSection: View {
    @Binding var settings: AppSettings
    let t: (String, String) -> String

    var body: some View {
        SettingsSection(title: t("Notifications", "알림")) {
            SettingsToggleRow(
                icon: "bell",
                title: t("Device Disconnect Alerts", "장치 연결 해제 알림"),
                description: t("Show notification when device disconnects", "오디오 장치 연결 해제 시 알림 표시"),
                isOn: $settings.showDeviceDisconnectAlerts
            )
        }
    }
}

// MARK: - 기능: 데이터 초기화

struct SettingsDataSection: View {
    @Binding var showResetConfirmation: Bool
    let onResetAll: () -> Void
    let t: (String, String) -> String

    var body: some View {
        SettingsSection(title: t("Data", "데이터")) {
            if showResetConfirmation {
                resetConfirmationRow
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                SettingsButtonRow(
                    icon: "arrow.counterclockwise",
                    title: t("Reset All Settings", "모든 설정 초기화"),
                    description: t("Clear all volumes, EQ, and device routings", "볼륨, EQ, 라우팅 설정을 모두 초기화"),
                    buttonLabel: t("Reset", "초기화"),
                    isDestructive: true
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showResetConfirmation = true
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private var resetConfirmationRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(DesignTokens.Colors.mutedIndicator)
                .frame(width: DesignTokens.Dimensions.settingsIconWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(t("Reset all settings?", "모든 설정을 초기화할까요?"))
                    .font(DesignTokens.Typography.rowName)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(t("This cannot be undone", "이 작업은 되돌릴 수 없습니다"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            Button(t("Cancel", "취소")) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showResetConfirmation = false
                }
            }
            .buttonStyle(.plain)
            .font(DesignTokens.Typography.pickerText)
            .foregroundStyle(DesignTokens.Colors.textSecondary)

            Button(t("Reset", "초기화")) {
                onResetAll()
                showResetConfirmation = false
            }
            .buttonStyle(.plain)
            .font(DesignTokens.Typography.pickerText)
            .foregroundStyle(DesignTokens.Colors.mutedIndicator)
        }
        .hoverableRow()
    }
}

// MARK: - 기능: 하단 정보

struct SettingsAboutFooter: View {
    let t: (String, String) -> String

    var body: some View {
        let startYear = 2026
        let currentYear = Calendar.current.component(.year, from: Date())
        let yearText = startYear == currentYear ? "\(startYear)" : "\(startYear)-\(currentYear)"
        let githubURL = URL(string: "https://github.com/ronitsingh10/diodiooodio")

        return HStack(spacing: DesignTokens.Spacing.xs) {
            if let githubURL {
                Link(destination: githubURL) {
                    Text("\(Image(systemName: "star")) \(t("Star on GitHub", "GitHub에서 별표"))")
                }
            }

            Text("·")
            Text("Copyright © \(yearText) Ronit Singh")
        }
        .font(DesignTokens.Typography.caption)
        .foregroundStyle(DesignTokens.Colors.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.Spacing.sm)
    }
}
