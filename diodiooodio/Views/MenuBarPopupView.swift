import SwiftUI

/// 메뉴바 팝업의 루트 컨테이너입니다.
/// 화면 상태와 라이프사이클을 관리하고, 실제 UI 블록은 기능별 확장 파일에서 조립합니다.
struct MenuBarPopupView: View {
    @Environment(\.openWindow) private var openWindow

    @Bindable var audioEngine: AudioEngine
    @Bindable var deviceVolumeMonitor: DeviceVolumeMonitor
    @Bindable var notchController: NotchIslandController

    // MARK: - 상태 저장소

    /// 출력 장치 목록 정렬 결과를 캐시합니다.
    @State var sortedDevices: [AudioDevice] = []
    /// 현재 EQ 패널이 펼쳐진 앱 ID입니다.
    @State var expandedEQAppID: String?
    /// EQ 토글 애니메이션 중복 실행 방지 플래그입니다.
    @State var isEQAnimating = false
    /// 설정 패널 토글 애니메이션 중복 실행 방지 플래그입니다.
    @State var isSettingsAnimating = false
    /// 팝업 활성 여부입니다.
    @State var isPopupVisible = true
    /// 설정 패널 열림 여부입니다.
    @State var isSettingsOpen = false
    /// 설정 화면 바인딩을 위한 로컬 설정 사본입니다.
    @State var localAppSettings = AppSettings()

    // MARK: - 레이아웃 상수

    enum Layout {
        static let deviceScrollThreshold = 4
        static let deviceScrollHeight: CGFloat = 160
        static let appScrollThreshold = 5
        static let appScrollHeight: CGFloat = 220
    }

    // MARK: - 파생 상태

    var language: AppLanguage { localAppSettings.language }
    var displayableApps: [DisplayableApp] { audioEngine.displayableApps }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            topBar

            if isSettingsOpen {
                settingsPanel
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                mainContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: DesignTokens.Dimensions.popupWidth)
        .darkGlassBackground()
        .onAppear(perform: handleOnAppear)
        .onChange(of: audioEngine.outputDevices) { _, _ in
            updateSortedDevices()
        }
        .onChange(of: localAppSettings) { _, newValue in
            audioEngine.settingsManager.updateAppSettings(newValue)
            notchController.reloadModuleVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isPopupVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            isPopupVisible = false
        }
        .background { settingsShortcutButton }
    }
}

// MARK: - 공통 헬퍼

extension MenuBarPopupView {
    /// 현재 언어에 맞는 문구를 반환합니다.
    func t(_ english: String, _ korean: String) -> String {
        language.text(english, korean)
    }

    /// 루트 화면 최초 표시 시 필요한 초기 동기화를 수행합니다.
    func handleOnAppear() {
        updateSortedDevices()
        localAppSettings = audioEngine.settingsManager.appSettings
    }

    /// 설정 패널을 열고 닫습니다.
    func toggleSettings() {
        guard !isSettingsAnimating else { return }
        isSettingsAnimating = true

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isSettingsOpen.toggle()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isSettingsAnimating = false
        }
    }

    /// 설정 토글 단축키(⌘ + ,)를 처리하는 숨김 버튼입니다.
    var settingsShortcutButton: some View {
        Button("") { toggleSettings() }
            .keyboardShortcut(",", modifiers: .command)
            .hidden()
    }

    /// 설정 패널 내용입니다.
    var settingsPanel: some View {
        SettingsView(
            settings: $localAppSettings,
            onResetAll: {
                audioEngine.settingsManager.resetAllSettings()
                localAppSettings = audioEngine.settingsManager.appSettings
            }
        )
    }

    /// MainUI 진입 동작을 수행합니다.
    func openMainUI() {
        MainUIEntryRouter.handleMainUISelection(openWindow: openWindow)
    }
}
