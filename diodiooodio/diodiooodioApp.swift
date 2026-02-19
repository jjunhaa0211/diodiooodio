import SwiftUI
import UserNotifications
import AppKit
import os

private let logger = Logger(subsystem: "com.diodiooodio.app", category: "App")

enum MainUIEntryMode {
    case dev
    case state
}

@MainActor
enum MainUIEntryRouter {
    static let mode: MainUIEntryMode = .dev

    static var shouldShowDynamicBarOnLaunch: Bool {
        mode == .state
    }

    static func handleMainUISelection(openWindow: OpenWindowAction) {
        switch mode {
        case .dev:
            showDevelopmentAlert()
        case .state:
            openWindow(id: "main-ui")
        }
    }

    private static func showDevelopmentAlert() {
        let alert = NSAlert()
        alert.messageText = "해당 기능은 개발 중에 있습니다."
        alert.addButton(withTitle: "확인")
        alert.alertStyle = .informational
        alert.runModal()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var audioEngine: AudioEngine?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let audioEngine else { return }
        let urlHandler = URLHandler(audioEngine: audioEngine)

        for url in urls {
            urlHandler.handleURL(url)
        }
    }

    // Menu bar app는 다음 실행 시 이전 윈도우(특히 빈 Settings)를 복원하지 않는다.
    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    // Menu bar app는 다음 실행 시 이전 윈도우(특히 빈 Settings)를 복원하지 않는다.
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}

@main
struct DiodiooodioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var audioEngine: AudioEngine
    @State private var musicService: AppleMusicNowPlayingService
    @State private var notchController: NotchIslandController
    @State private var showMenuBarExtra = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            menuBarContent
        }
        label: {
            if currentIconStyle.isSystemSymbol {
                Label("diodiooodio", systemImage: currentIconStyle.iconName)
            } else {
                Label("diodiooodio", image: currentIconStyle.iconName)
            }
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }

    /// 현재 아이콘 style 값입니다.
    private var currentIconStyle: MenuBarIconStyle {
        audioEngine.settingsManager.appSettings.menuBarIconStyle
    }

    @ViewBuilder
    private var menuBarContent: some View {
        MenuBarPopupView(
            audioEngine: audioEngine,
            deviceVolumeMonitor: audioEngine.deviceVolumeMonitor,
            notchController: notchController
        )
    }

    init() {
        // 윈도우 상태 복원을 앱 단위로 비활성화한다.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        let settings = SettingsManager()
        let engine = AudioEngine(settingsManager: settings)
        let music = AppleMusicNowPlayingService()
        let notch = NotchIslandController(musicService: music, settingsManager: settings)
        _audioEngine = State(initialValue: engine)
        _musicService = State(initialValue: music)
        _notchController = State(initialValue: notch)

        _appDelegate.wrappedValue.audioEngine = engine

        // 장치 연결 해제/복구 알림 권한 요청
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                logger.error("Notification authorization error: \(error.localizedDescription)")
            }
            _ = granted
        }

        // 앱 종료 직전 디바운스 대기 중인 설정 저장을 즉시 반영한다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [settings] _ in
            settings.flushSync()
        }

        // state 모드에서만 앱 실행 직후 다이나믹 바를 자동 표시한다.
        DispatchQueue.main.async {
            guard MainUIEntryRouter.shouldShowDynamicBarOnLaunch else { return }
            notch.show()
        }
    }
}
