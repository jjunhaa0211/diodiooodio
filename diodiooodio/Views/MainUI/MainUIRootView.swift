import SwiftUI

/// 맥북 통합 관리용 MainUI 루트 화면입니다.
struct MainUIRootView: View {
    @Bindable var audioEngine: AudioEngine
    @Bindable var musicService: AppleMusicNowPlayingService
    @Bindable var notchController: NotchIslandController

    @State private var selectedTab: MainUITab = .audio
    @State private var localAppSettings = AppSettings()

    private var language: AppLanguage { localAppSettings.language }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.07, green: 0.07, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 14) {
                MainUISidebar(selectedTab: $selectedTab, language: language)
                    .frame(width: 285)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )

                VStack(spacing: 0) {
                    MainUIHeader(selectedTab: selectedTab, language: language)
                    Divider().overlay(Color.white.opacity(0.09))
                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
            }
            .padding(14)
        }
        .frame(minWidth: 1020, minHeight: 680)
        .onAppear {
            musicService.start()
            localAppSettings = audioEngine.settingsManager.appSettings
            notchController.reloadModuleVisibility()
        }
        .onChange(of: localAppSettings) { _, newValue in
            audioEngine.settingsManager.updateAppSettings(newValue)
            notchController.reloadModuleVisibility()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .audio:
            AudioTabContentView(audioEngine: audioEngine, language: language)
        case .media:
            MediaTabContentView(
                musicService: musicService,
                notchController: notchController,
                language: language
            )
        case .system:
            SystemTabContentView(language: language)
        case .automation:
            AutomationTabContentView(language: language)
        case .settings:
            MainUISettingsTabContentView(settings: $localAppSettings, notchController: notchController)
        }
    }
}

/// MainUI 상단 타이틀 바입니다.
private struct MainUIHeader: View {
    let selectedTab: MainUITab
    let language: AppLanguage

    private func t(_ english: String, _ korean: String) -> String {
        language.text(english, korean)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t("Workspace", "워크스페이스"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(selectedTab.subtitle(language))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Spacer()
            Label(selectedTab.title(language), systemImage: selectedTab.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(DesignTokens.Colors.accentPrimary.opacity(0.2)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
