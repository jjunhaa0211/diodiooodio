import Foundation
import ServiceManagement
import os


struct PinnedAppInfo: Codable, Equatable {
    let persistenceIdentifier: String
    let displayName: String
    let bundleID: String?
}


enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable {
    case `default` = "Default"
    case speaker = "Speaker"
    case waveform = "Waveform"
    case equalizer = "Equalizer"

    var id: String { rawValue }

    /// 아이콘 이름 값입니다.
    var iconName: String {
        switch self {
        case .default: return "heart.fill"
        case .speaker: return "speaker.wave.2.fill"
        case .waveform: return "waveform"
        case .equalizer: return "slider.vertical.3"
        }
    }

    /// system symbol 여부를 나타냅니다.
    var isSystemSymbol: Bool { true }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "English"
    case korean = "Korean"

    var id: String { rawValue }
}


struct AppSettings: Codable, Equatable {
    // 일반
    var launchAtLogin = false
    var menuBarIconStyle: MenuBarIconStyle = .default
    var language: AppLanguage = .english

    // 오디오
    var defaultNewAppVolume: Float = 1.0 // 100%(유니티 게인)
    var maxVolumeBoost: Float = 2.0 // 200% 상한

    // 알림
    var showDeviceDisconnectAlerts = true

    // Notch 모듈
    var notchShowMusic = true
    var notchShowFiles = true
    var notchShowTime = false
    var notchAutoControl = true
    var notchPinExpanded = false
    var notchShowCompactNowPlaying = true
    var notchShowCompactPlaybackStatus = true
    var notchModuleOrder: [String] = ["music", "files", "time"]

    enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case menuBarIconStyle
        case language
        case defaultNewAppVolume
        case maxVolumeBoost
        case showDeviceDisconnectAlerts
        case notchShowMusic
        case notchShowFiles
        case notchShowTime
        case notchAutoControl
        case notchPinExpanded
        case notchShowCompactNowPlaying
        case notchShowCompactPlaybackStatus
        case notchModuleOrder
    }

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        menuBarIconStyle = try container.decodeIfPresent(MenuBarIconStyle.self, forKey: .menuBarIconStyle) ?? menuBarIconStyle
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? language
        defaultNewAppVolume = try container.decodeIfPresent(Float.self, forKey: .defaultNewAppVolume) ?? defaultNewAppVolume
        maxVolumeBoost = try container.decodeIfPresent(Float.self, forKey: .maxVolumeBoost) ?? maxVolumeBoost
        showDeviceDisconnectAlerts = try container.decodeIfPresent(Bool.self, forKey: .showDeviceDisconnectAlerts) ?? showDeviceDisconnectAlerts
        notchShowMusic = try container.decodeIfPresent(Bool.self, forKey: .notchShowMusic) ?? notchShowMusic
        notchShowFiles = try container.decodeIfPresent(Bool.self, forKey: .notchShowFiles) ?? notchShowFiles
        notchShowTime = try container.decodeIfPresent(Bool.self, forKey: .notchShowTime) ?? notchShowTime
        notchAutoControl = try container.decodeIfPresent(Bool.self, forKey: .notchAutoControl) ?? notchAutoControl
        notchPinExpanded = try container.decodeIfPresent(Bool.self, forKey: .notchPinExpanded) ?? notchPinExpanded
        notchShowCompactNowPlaying = try container.decodeIfPresent(Bool.self, forKey: .notchShowCompactNowPlaying) ?? notchShowCompactNowPlaying
        notchShowCompactPlaybackStatus = try container.decodeIfPresent(Bool.self, forKey: .notchShowCompactPlaybackStatus) ?? notchShowCompactPlaybackStatus
        notchModuleOrder = try container.decodeIfPresent([String].self, forKey: .notchModuleOrder) ?? notchModuleOrder
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(menuBarIconStyle, forKey: .menuBarIconStyle)
        try container.encode(language, forKey: .language)
        try container.encode(defaultNewAppVolume, forKey: .defaultNewAppVolume)
        try container.encode(maxVolumeBoost, forKey: .maxVolumeBoost)
        try container.encode(showDeviceDisconnectAlerts, forKey: .showDeviceDisconnectAlerts)
        try container.encode(notchShowMusic, forKey: .notchShowMusic)
        try container.encode(notchShowFiles, forKey: .notchShowFiles)
        try container.encode(notchShowTime, forKey: .notchShowTime)
        try container.encode(notchAutoControl, forKey: .notchAutoControl)
        try container.encode(notchPinExpanded, forKey: .notchPinExpanded)
        try container.encode(notchShowCompactNowPlaying, forKey: .notchShowCompactNowPlaying)
        try container.encode(notchShowCompactPlaybackStatus, forKey: .notchShowCompactPlaybackStatus)
        try container.encode(notchModuleOrder, forKey: .notchModuleOrder)
    }
}


@Observable
@MainActor
final class SettingsManager {
    struct Settings: Codable {
        var version = 8

        var appVolumes: [String: Float] = [:]
        var appDeviceRouting: [String: String] = [:]
        var appMutes: [String: Bool] = [:]
        var appEQSettings: [String: EQSettings] = [:]

        var appSettings = AppSettings()
        var appDeviceSelectionMode: [String: DeviceSelectionMode] = [:]
        var appSelectedDeviceUIDs: [String: [String]] = [:]

        var pinnedApps: Set<String> = []
        var pinnedAppInfo: [String: PinnedAppInfo] = [:]

        var ddcVolumes: [String: Int] = [:]
        var ddcMuteStates: [String: Bool] = [:]
        var ddcSavedVolumes: [String: Int] = [:]
    }

    private static let saveDebounce: Duration = .milliseconds(500)

    private var settings = Settings()
    private var saveTask: Task<Void, Never>?
    private let settingsURL: URL
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "diodiooodio", category: "SettingsManager")

    init(directory: URL? = nil) {
        let baseDirectory = directory ?? Self.defaultSettingsDirectory
        settingsURL = baseDirectory.appendingPathComponent("settings.json")
        loadFromDisk()
    }

    var appSettings: AppSettings {
        settings.appSettings
    }

    /// 실행 at 로그인 활성화 여부를 나타냅니다.
    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func getVolume(for identifier: String) -> Float? {
        settings.appVolumes[identifier]
    }

    func setVolume(for identifier: String, to volume: Float) {
        mutateSettings { $0.appVolumes[identifier] = volume }
    }

    func getDeviceRouting(for identifier: String) -> String? {
        settings.appDeviceRouting[identifier]
    }

    func setDeviceRouting(for identifier: String, deviceUID: String) {
        mutateSettings { $0.appDeviceRouting[identifier] = deviceUID }
    }

    /// following 기본 여부를 반환합니다.
    func isFollowingDefault(for identifier: String) -> Bool {
        settings.appDeviceRouting[identifier] == nil
    }

    /// follow 기본을(를) 설정합니다
    func setFollowDefault(for identifier: String) {
        mutateSettings { $0.appDeviceRouting.removeValue(forKey: identifier) }
    }

    func getMute(for identifier: String) -> Bool? {
        settings.appMutes[identifier]
    }

    func setMute(for identifier: String, to muted: Bool) {
        mutateSettings { $0.appMutes[identifier] = muted }
    }

    func getEQSettings(for appIdentifier: String) -> EQSettings {
        settings.appEQSettings[appIdentifier] ?? .flat
    }

    func setEQSettings(_ eqSettings: EQSettings, for appIdentifier: String) {
        mutateSettings { $0.appEQSettings[appIdentifier] = eqSettings }
    }

    func getDeviceSelectionMode(for identifier: String) -> DeviceSelectionMode? {
        settings.appDeviceSelectionMode[identifier]
    }

    func setDeviceSelectionMode(for identifier: String, to mode: DeviceSelectionMode) {
        mutateSettings { $0.appDeviceSelectionMode[identifier] = mode }
    }

    func getSelectedDeviceUIDs(for identifier: String) -> Set<String>? {
        guard let deviceUIDs = settings.appSelectedDeviceUIDs[identifier] else { return nil }
        return Set(deviceUIDs)
    }

    func setSelectedDeviceUIDs(for identifier: String, to uids: Set<String>) {
        mutateSettings { $0.appSelectedDeviceUIDs[identifier] = uids.sorted() }
    }

    func pinApp(_ identifier: String, info: PinnedAppInfo) {
        mutateSettings {
            $0.pinnedApps.insert(identifier)
            $0.pinnedAppInfo[identifier] = info
        }
    }

    func unpinApp(_ identifier: String) {
        mutateSettings {
            $0.pinnedApps.remove(identifier)
            $0.pinnedAppInfo.removeValue(forKey: identifier)
        }
    }

    func isPinned(_ identifier: String) -> Bool {
        settings.pinnedApps.contains(identifier)
    }

    /// 고정 앱 info을(를) 조회합니다
    func getPinnedAppInfo() -> [PinnedAppInfo] {
        settings.pinnedApps.compactMap { settings.pinnedAppInfo[$0] }
    }

    func getDDCVolume(for deviceUID: String) -> Int? {
        settings.ddcVolumes[deviceUID]
    }

    func setDDCVolume(for deviceUID: String, to volume: Int) {
        mutateSettings { $0.ddcVolumes[deviceUID] = volume }
    }

    func getDDCMuteState(for deviceUID: String) -> Bool {
        settings.ddcMuteStates[deviceUID] ?? false
    }

    func setDDCMuteState(for deviceUID: String, to muted: Bool) {
        mutateSettings { $0.ddcMuteStates[deviceUID] = muted }
    }

    func getDDCSavedVolume(for deviceUID: String) -> Int? {
        settings.ddcSavedVolumes[deviceUID]
    }

    func setDDCSavedVolume(for deviceUID: String, to volume: Int) {
        mutateSettings { $0.ddcSavedVolumes[deviceUID] = volume }
    }

    func updateAppSettings(_ newSettings: AppSettings) {
        if newSettings.launchAtLogin != settings.appSettings.launchAtLogin {
            setLaunchAtLogin(newSettings.launchAtLogin)
        }
        mutateSettings { $0.appSettings = newSettings }
    }

    /// all 설정을(를) 초기화합니다
    func resetAllSettings() {
        settings = Settings()
        try? SMAppService.mainApp.unregister()
        scheduleSave()
        logger.info("모든 설정을 초기화했습니다.")
    }

    /// sync을(를) 즉시 저장합니다
    func flushSync() {
        saveTask?.cancel()
        saveTask = nil
        writeToDisk()
    }

    private static var defaultSettingsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("diodiooodio")
    }

    private func mutateSettings(_ mutation: (inout Settings) -> Void) {
        mutation(&settings)
        scheduleSave()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("로그인 시 자동 실행을 등록했습니다.")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("로그인 시 자동 실행을 해제했습니다.")
            }
        } catch {
            logger.error("로그인 시 자동 실행 설정 실패: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }

        do {
            let data = try Data(contentsOf: settingsURL)
            settings = try JSONDecoder().decode(Settings.self, from: data)
            logger.debug("설정 로드 완료")
        } catch {
            logger.error("설정 로드 실패: \(error.localizedDescription)")
            backupCorruptedFile()
            settings = Settings()
        }
    }

    private func backupCorruptedFile() {
        let backupURL = settingsURL.deletingPathExtension().appendingPathExtension("backup.json")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        logger.warning("손상된 설정 파일을 \(backupURL.lastPathComponent)에 백업했습니다.")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            writeToDisk()
        }
    }

    private func writeToDisk() {
        do {
            let directory = settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: .atomic)
            logger.debug("설정을 저장했습니다.")
        } catch {
            logger.error("설정 저장 실패: \(error.localizedDescription)")
        }
    }
}
