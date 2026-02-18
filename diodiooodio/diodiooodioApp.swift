import SwiftUI
import UserNotifications
import FluidMenuBarExtra
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
}

@main
struct DiodiooodioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var audioEngine: AudioEngine
    @State private var musicService: AppleMusicNowPlayingService
    @State private var notchController: NotchIslandController
    @State private var showMenuBarExtra = true

    var body: some Scene {
        FluidMenuBarExtra("diodiooodio", systemImage: currentSystemImageName ?? "heart.fill", isInserted: systemIconBinding) {
            menuBarContent
        }

        FluidMenuBarExtra("diodiooodio", image: currentAssetImageName ?? "MenuBarIcon", isInserted: assetIconBinding) {
            menuBarContent
        }

        Window("MainUI", id: "main-ui") {
            MainUIRootView(
                audioEngine: audioEngine,
                musicService: musicService,
                notchController: notchController
            )
        }
        .defaultSize(width: 1080, height: 700)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) { }
            MainUICommands()
        }
    }

    /// 현재 아이콘 style 값입니다.
    private var currentIconStyle: MenuBarIconStyle {
        audioEngine.settingsManager.appSettings.menuBarIconStyle
    }

    private var currentSystemImageName: String? {
        currentIconStyle.isSystemSymbol ? currentIconStyle.iconName : nil
    }

    private var currentAssetImageName: String? {
        currentIconStyle.isSystemSymbol ? nil : currentIconStyle.iconName
    }

    /// system 아이콘 binding 상태를 나타냅니다.
    private var systemIconBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarExtra && currentIconStyle.isSystemSymbol },
            set: { showMenuBarExtra = $0 }
        )
    }

    /// asset 아이콘 binding 상태를 나타냅니다.
    private var assetIconBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarExtra && !currentIconStyle.isSystemSymbol },
            set: { showMenuBarExtra = $0 }
        )
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

/// MainUI 메뉴 명령입니다.
private struct MainUICommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("MainUI") {
            Button("Open MainUI") {
                MainUIEntryRouter.handleMainUISelection(openWindow: openWindow)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }
}
