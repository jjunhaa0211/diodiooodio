import AudioToolbox
import Foundation
import os
import UserNotifications

@Observable
@MainActor
final class AudioEngine {
    let processMonitor = AudioProcessMonitor()
    let deviceMonitor = AudioDeviceMonitor()
    let deviceVolumeMonitor: DeviceVolumeMonitor
    let volumeState: VolumeState
    let settingsManager: SettingsManager

    #if !APP_STORE
    let ddcController: DDCController
    #endif

    private var taps: [pid_t: ProcessTapController] = [:]
    private var appliedPIDs: Set<pid_t> = []
    private var appDeviceRouting: [pid_t: String] = [:]
    private var followsDefault: Set<pid_t> = []
    private var pendingCleanup: [pid_t: Task<Void, Never>] = [:]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "diodiooodio", category: "AudioEngine")

    var outputDevices: [AudioDevice] {
        #if !APP_STORE
        guard ddcController.probeCompleted else {
            return deviceMonitor.outputDevices
        }
        return deviceMonitor.outputDevices.filter { device in
            device.id.hasOutputVolumeControl() || ddcController.isDDCBacked(device.id)
        }
        #else
        return deviceMonitor.outputDevices
        #endif
    }

    init(settingsManager: SettingsManager? = nil) {
        let manager = settingsManager ?? SettingsManager()
        self.settingsManager = manager
        self.volumeState = VolumeState(settingsManager: manager)

        #if !APP_STORE
        let ddc = DDCController(settingsManager: manager)
        self.ddcController = ddc
        self.deviceVolumeMonitor = DeviceVolumeMonitor(deviceMonitor: deviceMonitor, ddcController: ddc)
        #else
        self.deviceVolumeMonitor = DeviceVolumeMonitor(deviceMonitor: deviceMonitor)
        #endif

        Task { @MainActor in
            processMonitor.start()
            deviceMonitor.start()

            #if !APP_STORE
            ddc.onProbeCompleted = { [weak self] in
                self?.deviceVolumeMonitor.refreshAfterDDCProbe()
            }
            ddc.start()
            #endif

            deviceVolumeMonitor.start()

            // 다중 출력에서는 첫 번째(클럭 소스) 장치를 기준으로 반영한다.
            deviceVolumeMonitor.onVolumeChanged = { [weak self] deviceID, newVolume in
                guard let self else { return }
                guard let deviceUID = self.deviceMonitor.outputDevices.first(where: { $0.id == deviceID })?.uid else { return }
                for (_, tap) in self.taps {
                    if tap.currentDeviceUID == deviceUID {
                        tap.currentDeviceVolume = newVolume
                    }
                }
            }

            deviceVolumeMonitor.onMuteChanged = { [weak self] deviceID, isMuted in
                guard let self else { return }
                guard let deviceUID = self.deviceMonitor.outputDevices.first(where: { $0.id == deviceID })?.uid else { return }
                for (_, tap) in self.taps {
                    if tap.currentDeviceUID == deviceUID {
                        tap.isDeviceMuted = isMuted
                    }
                }
            }

            processMonitor.onAppsChanged = { [weak self] _ in
                self?.cleanupStaleTaps()
                self?.applyPersistedSettings()
            }

            deviceMonitor.onDeviceDisconnected = { [weak self] deviceUID, deviceName in
                self?.handleDeviceDisconnected(deviceUID, name: deviceName)
            }

            deviceMonitor.onDeviceConnected = { [weak self] deviceUID, deviceName in
                self?.handleDeviceConnected(deviceUID, name: deviceName)
            }

            deviceVolumeMonitor.onDefaultDeviceChanged = { [weak self] newDefaultUID in
                self?.handleDefaultDeviceChanged(newDefaultUID)
            }

            applyPersistedSettings()
        }
    }

    var apps: [AudioApp] {
        processMonitor.activeApps
    }


    /// displayable 앱 목록입니다.
    var displayableApps: [DisplayableApp] {
        let activeApps = apps
        let activeIdentifiers = Set(activeApps.map { $0.persistenceIdentifier })
        let nameAscending: (String, String) -> Bool = {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        let pinnedInactiveInfos = settingsManager.getPinnedAppInfo()
            .filter { !activeIdentifiers.contains($0.persistenceIdentifier) }

        let pinnedActive = activeApps
            .filter { settingsManager.isPinned($0.persistenceIdentifier) }
            .sorted { nameAscending($0.name, $1.name) }
            .map { DisplayableApp.active($0) }

        let pinnedInactive = pinnedInactiveInfos
            .sorted { nameAscending($0.displayName, $1.displayName) }
            .map { DisplayableApp.pinnedInactive($0) }

        let unpinnedActive = activeApps
            .filter { !settingsManager.isPinned($0.persistenceIdentifier) }
            .sorted { nameAscending($0.name, $1.name) }
            .map { DisplayableApp.active($0) }

        return pinnedActive + pinnedInactive + unpinnedActive
    }


    /// 앱을(를) 고정합니다
    func pinApp(_ app: AudioApp) {
        let info = PinnedAppInfo(
            persistenceIdentifier: app.persistenceIdentifier,
            displayName: app.name,
            bundleID: app.bundleID
        )
        settingsManager.pinApp(app.persistenceIdentifier, info: info)
    }

    /// 앱을(를) 고정 해제합니다
    func unpinApp(_ identifier: String) {
        settingsManager.unpinApp(identifier)
    }

    /// 고정 여부를 반환합니다.
    func isPinned(_ app: AudioApp) -> Bool {
        settingsManager.isPinned(app.persistenceIdentifier)
    }

    /// 고정 여부를 반환합니다.
    func isPinned(identifier: String) -> Bool {
        settingsManager.isPinned(identifier)
    }


    /// 볼륨 for 비활성을(를) 조회합니다
    func getVolumeForInactive(identifier: String) -> Float {
        settingsManager.getVolume(for: identifier) ?? 1.0
    }

    /// 볼륨 for 비활성을(를) 설정합니다
    func setVolumeForInactive(identifier: String, to volume: Float) {
        settingsManager.setVolume(for: identifier, to: volume)
    }

    /// 음소거 for 비활성을(를) 조회합니다
    func getMuteForInactive(identifier: String) -> Bool {
        settingsManager.getMute(for: identifier) ?? false
    }

    /// 음소거 for 비활성을(를) 설정합니다
    func setMuteForInactive(identifier: String, to muted: Bool) {
        settingsManager.setMute(for: identifier, to: muted)
    }

    /// eqsettings for 비활성을(를) 조회합니다
    func getEQSettingsForInactive(identifier: String) -> EQSettings {
        settingsManager.getEQSettings(for: identifier)
    }

    /// eqsettings for 비활성을(를) 설정합니다
    func setEQSettingsForInactive(_ settings: EQSettings, identifier: String) {
        settingsManager.setEQSettings(settings, for: identifier)
    }

    /// 장치 라우팅 for 비활성을(를) 조회합니다
    func getDeviceRoutingForInactive(identifier: String) -> String? {
        settingsManager.getDeviceRouting(for: identifier)
    }

    /// 장치 라우팅 for 비활성을(를) 설정합니다
    func setDeviceRoutingForInactive(identifier: String, deviceUID: String?) {
        if let deviceUID = deviceUID {
            settingsManager.setDeviceRouting(for: identifier, deviceUID: deviceUID)
        } else {
            settingsManager.setFollowDefault(for: identifier)
        }
    }

    /// following 기본 for 비활성 여부를 반환합니다.
    func isFollowingDefaultForInactive(identifier: String) -> Bool {
        settingsManager.isFollowingDefault(for: identifier)
    }

    /// 장치 선택 모드 for 비활성을(를) 조회합니다
    func getDeviceSelectionModeForInactive(identifier: String) -> DeviceSelectionMode {
        settingsManager.getDeviceSelectionMode(for: identifier) ?? .single
    }

    /// 장치 선택 모드 for 비활성을(를) 설정합니다
    func setDeviceSelectionModeForInactive(identifier: String, to mode: DeviceSelectionMode) {
        settingsManager.setDeviceSelectionMode(for: identifier, to: mode)
    }

    /// 선택된 장치 uids for 비활성을(를) 조회합니다
    func getSelectedDeviceUIDsForInactive(identifier: String) -> Set<String> {
        settingsManager.getSelectedDeviceUIDs(for: identifier) ?? []
    }

    /// 선택된 장치 uids for 비활성을(를) 설정합니다
    func setSelectedDeviceUIDsForInactive(identifier: String, to uids: Set<String>) {
        settingsManager.setSelectedDeviceUIDs(for: identifier, to: uids)
    }

    /// 오디오 레벨 목록입니다.
    var audioLevels: [pid_t: Float] {
        var levels: [pid_t: Float] = [:]
        for (pid, tap) in taps {
            levels[pid] = tap.audioLevel
        }
        return levels
    }

    /// 오디오 레벨을(를) 조회합니다
    func getAudioLevel(for app: AudioApp) -> Float {
        taps[app.id]?.audioLevel ?? 0.0
    }

    func start() {
        // 내부적으로 중복 시작 방어 로직이 있으므로 직접 재호출해도 안전하다.
        processMonitor.start()
        deviceMonitor.start()
        applyPersistedSettings()

        logger.info("AudioEngine started")
    }

    func stop() {
        processMonitor.stop()
        deviceMonitor.stop()
        for tap in taps.values {
            tap.invalidate()
        }
        taps.removeAll()
        logger.info("AudioEngine stopped")
    }

    /// shutdown 동작을 처리합니다.
    func shutdown() {
        stop()
        deviceVolumeMonitor.stop()
        logger.info("AudioEngine shutdown complete")
    }

    func setVolume(for app: AudioApp, to volume: Float) {
        volumeState.setVolume(for: app.id, to: volume, identifier: app.persistenceIdentifier)
        if let deviceUID = appDeviceRouting[app.id] {
            ensureTapExists(for: app, deviceUID: deviceUID)
        }
        taps[app.id]?.volume = volume
    }

    func getVolume(for app: AudioApp) -> Float {
        volumeState.getVolume(for: app.id)
    }

    func setMute(for app: AudioApp, to muted: Bool) {
        volumeState.setMute(for: app.id, to: muted, identifier: app.persistenceIdentifier)
        taps[app.id]?.isMuted = muted
    }

    func getMute(for app: AudioApp) -> Bool {
        volumeState.getMute(for: app.id)
    }

    /// eqsettings을(를) 설정합니다
    func setEQSettings(_ settings: EQSettings, for app: AudioApp) {
        guard let tap = taps[app.id] else { return }
        tap.updateEQSettings(settings)
        settingsManager.setEQSettings(settings, for: app.persistenceIdentifier)
    }

    /// eqsettings을(를) 조회합니다
    func getEQSettings(for app: AudioApp) -> EQSettings {
        return settingsManager.getEQSettings(for: app.persistenceIdentifier)
    }

    /// 장치을(를) 설정합니다
    func setDevice(for app: AudioApp, deviceUID: String?) {
        if let deviceUID = deviceUID {
            // 명시 라우팅 선택 시 기본 출력 추종을 해제한다.
            followsDefault.remove(app.id)
            guard appDeviceRouting[app.id] != deviceUID else { return }
            appDeviceRouting[app.id] = deviceUID
            settingsManager.setDeviceRouting(for: app.persistenceIdentifier, deviceUID: deviceUID)
        } else {
            followsDefault.insert(app.id)
            settingsManager.setFollowDefault(for: app.persistenceIdentifier)

            guard let defaultUID = deviceVolumeMonitor.defaultDeviceUID else {
                logger.warning("No default device available for \(app.name), will route when available")
                return
            }
            guard appDeviceRouting[app.id] != defaultUID else { return }
            appDeviceRouting[app.id] = defaultUID
        }

        guard let targetUID = appDeviceRouting[app.id] else { return }
        if let tap = taps[app.id] {
            Task {
                do {
                    try await tap.switchDevice(to: targetUID)
                    self.restoreTapState(tap, appID: app.id, primaryDeviceUID: targetUID)
                    self.logger.debug("Switched \(app.name) to device: \(targetUID)")
                } catch {
                    self.logger.error("Failed to switch device for \(app.name): \(error.localizedDescription)")
                }
            }
        } else {
            ensureTapExists(for: app, deviceUID: targetUID)
        }
    }

    func getDeviceUID(for app: AudioApp) -> String? {
        appDeviceRouting[app.id]
    }

    /// following 기본 여부를 반환합니다.
    func isFollowingDefault(for app: AudioApp) -> Bool {
        followsDefault.contains(app.id)
    }


    /// 장치 선택 모드을(를) 조회합니다
    func getDeviceSelectionMode(for app: AudioApp) -> DeviceSelectionMode {
        volumeState.getDeviceSelectionMode(for: app.id)
    }

    /// 장치 선택 모드을(를) 설정합니다
    func setDeviceSelectionMode(for app: AudioApp, to mode: DeviceSelectionMode) {
        let previousMode = volumeState.getDeviceSelectionMode(for: app.id)
        volumeState.setDeviceSelectionMode(for: app.id, to: mode, identifier: app.persistenceIdentifier)

        guard previousMode != mode else { return }

        Task {
            await updateTapForCurrentMode(for: app)
        }
    }

    /// 선택된 장치 uids을(를) 조회합니다
    func getSelectedDeviceUIDs(for app: AudioApp) -> Set<String> {
        volumeState.getSelectedDeviceUIDs(for: app.id)
    }

    /// 선택된 장치 uids을(를) 설정합니다
    func setSelectedDeviceUIDs(for app: AudioApp, to uids: Set<String>) {
        let previousUIDs = volumeState.getSelectedDeviceUIDs(for: app.id)
        volumeState.setSelectedDeviceUIDs(for: app.id, to: uids, identifier: app.persistenceIdentifier)

        guard previousUIDs != uids,
              getDeviceSelectionMode(for: app) == .multi else { return }

        Task {
            await updateTapForCurrentMode(for: app)
        }
    }

    /// 탭 for 현재 모드을(를) 갱신합니다
    private func updateTapForCurrentMode(for app: AudioApp) async {
        let mode = getDeviceSelectionMode(for: app)

        let deviceUIDs: [String]
        switch mode {
        case .single:
            if isFollowingDefault(for: app), let defaultUID = deviceVolumeMonitor.defaultDeviceUID {
                deviceUIDs = [defaultUID]
            } else if let deviceUID = appDeviceRouting[app.id] {
                deviceUIDs = [deviceUID]
            } else if let defaultUID = deviceVolumeMonitor.defaultDeviceUID {
                deviceUIDs = [defaultUID]
            } else {
                logger.warning("No device available for \(app.name) in single mode")
                return
            }

        case .multi:
            let selectedUIDs = getSelectedDeviceUIDs(for: app).sorted()
            if selectedUIDs.isEmpty {
                return
            }
            deviceUIDs = selectedUIDs
        }

        if let tap = taps[app.id] {
            if tap.currentDeviceUIDs != deviceUIDs {
                do {
                    try await tap.updateDevices(to: deviceUIDs)
                    restoreTapState(tap, appID: app.id, primaryDeviceUID: deviceUIDs.first)
                    logger.debug("Updated \(app.name) to \(deviceUIDs.count) device(s)")
                } catch {
                    logger.error("Failed to update devices for \(app.name): \(error.localizedDescription)")
                }
            }
        } else {
            ensureTapWithDevices(for: app, deviceUIDs: deviceUIDs)
        }
    }

    /// ensure 탭 with 장치 동작을 처리합니다.
    private func ensureTapWithDevices(for app: AudioApp, deviceUIDs: [String]) {
        guard !deviceUIDs.isEmpty else { return }

        let tap = ProcessTapController(app: app, targetDeviceUIDs: deviceUIDs, deviceMonitor: deviceMonitor)
        tap.volume = volumeState.getVolume(for: app.id)

        syncTapDeviceState(tap, primaryDeviceUID: deviceUIDs.first)

        do {
            try tap.activate()
            taps[app.id] = tap

            let eqSettings = settingsManager.getEQSettings(for: app.persistenceIdentifier)
            tap.updateEQSettings(eqSettings)

            logger.debug("Created tap for \(app.name) on \(deviceUIDs.count) device(s)")
        } catch {
            logger.error("Failed to create tap for \(app.name): \(error.localizedDescription)")
        }
    }

    func applyPersistedSettings() {
        for app in apps {
            guard !appliedPIDs.contains(app.id) else { continue }

            // 저장된 단일/다중 출력 모드 복원
            let savedMode = volumeState.loadSavedDeviceSelectionMode(for: app.id, identifier: app.persistenceIdentifier)
            let mode = savedMode ?? .single

            // 저장된 볼륨/음소거 상태 복원
            let savedVolume = volumeState.loadSavedVolume(for: app.id, identifier: app.persistenceIdentifier)
            let savedMute = volumeState.loadSavedMute(for: app.id, identifier: app.persistenceIdentifier)

            if mode == .multi {
                if let savedUIDs = volumeState.loadSavedSelectedDeviceUIDs(for: app.id, identifier: app.persistenceIdentifier),
                   !savedUIDs.isEmpty {
                    let availableUIDs = savedUIDs.filter { deviceMonitor.device(for: $0) != nil }
                        .sorted()
                    if !availableUIDs.isEmpty {
                        logger.debug("Restoring multi-device mode for \(app.name) with \(availableUIDs.count) device(s)")
                        ensureTapWithDevices(for: app, deviceUIDs: availableUIDs)

                        guard taps[app.id] != nil else { continue }
                        appliedPIDs.insert(app.id)

                        if let tap = taps[app.id] {
                            applyPersistedGainState(to: tap, volume: savedVolume, muted: savedMute)
                        }
                        continue
                    }
                    logger.debug("All multi-mode devices unavailable for \(app.name), falling back to single mode")
                }
            }

            let deviceUID: String
            if settingsManager.isFollowingDefault(for: app.persistenceIdentifier) {
                followsDefault.insert(app.id)
                guard let defaultUID = deviceVolumeMonitor.defaultDeviceUID else {
                    logger.warning("No default device available for \(app.name), deferring setup")
                    continue
                }
                deviceUID = defaultUID
                logger.debug("App \(app.name) follows system default: \(deviceUID)")
            } else if let savedDeviceUID = settingsManager.getDeviceRouting(for: app.persistenceIdentifier),
                      deviceMonitor.device(for: savedDeviceUID) != nil {
                deviceUID = savedDeviceUID
                logger.debug("Applying saved device routing to \(app.name): \(deviceUID)")
            } else {
                followsDefault.insert(app.id)
                guard let defaultUID = deviceVolumeMonitor.defaultDeviceUID else {
                    logger.warning("No default device for \(app.name), deferring setup")
                    continue
                }
                deviceUID = defaultUID
                logger.debug("App \(app.name) device temporarily unavailable, using default: \(deviceUID)")
            }
            appDeviceRouting[app.id] = deviceUID

            ensureTapExists(for: app, deviceUID: deviceUID)

            guard taps[app.id] != nil else { continue }
            appliedPIDs.insert(app.id)

            if let tap = taps[app.id] {
                applyPersistedGainState(to: tap, volume: savedVolume, muted: savedMute, appName: app.name)
            }
        }
    }

    private func ensureTapExists(for app: AudioApp, deviceUID: String) {
        guard taps[app.id] == nil else { return }

        let tap = ProcessTapController(app: app, targetDeviceUID: deviceUID, deviceMonitor: deviceMonitor)
        tap.volume = volumeState.getVolume(for: app.id)

        syncTapDeviceState(tap, primaryDeviceUID: deviceUID)

        do {
            try tap.activate()
            taps[app.id] = tap

            let eqSettings = settingsManager.getEQSettings(for: app.persistenceIdentifier)
            tap.updateEQSettings(eqSettings)

            logger.debug("Created tap for \(app.name)")
        } catch {
            logger.error("Failed to create tap for \(app.name): \(error.localizedDescription)")
        }
    }

    /// 장치 disconnected을(를) 처리합니다
    private func handleDeviceDisconnected(_ deviceUID: String, name deviceName: String) {
        let fallbackDevice: (uid: String, name: String)?
        if let defaultUID = deviceVolumeMonitor.defaultDeviceUID,
           let device = deviceMonitor.device(for: defaultUID) {
            fallbackDevice = (uid: defaultUID, name: device.name)
        } else if let firstDevice = deviceMonitor.outputDevices.first {
            fallbackDevice = (uid: firstDevice.uid, name: firstDevice.name)
        } else {
            fallbackDevice = nil
        }

        var affectedApps: [AudioApp] = []
        var singleModeTapsToSwitch: [(tap: ProcessTapController, fallbackUID: String)] = []
        var multiModeTapsToUpdate: [(tap: ProcessTapController, remainingUIDs: [String])] = []

        for tap in taps.values {
            let app = tap.app
            let mode = getDeviceSelectionMode(for: app)

            guard tap.currentDeviceUIDs.contains(deviceUID) else { continue }

            affectedApps.append(app)

            if mode == .multi && tap.currentDeviceUIDs.count > 1 {
                let remainingUIDs = tap.currentDeviceUIDs.filter { $0 != deviceUID }.sorted()
                if !remainingUIDs.isEmpty {
                    multiModeTapsToUpdate.append((tap: tap, remainingUIDs: remainingUIDs))
                    var currentSelection = volumeState.getSelectedDeviceUIDs(for: app.id)
                    currentSelection.remove(deviceUID)
                    volumeState.setSelectedDeviceUIDs(for: app.id, to: currentSelection, identifier: nil)
                    continue
                }
            }

            if let fallback = fallbackDevice {
                appDeviceRouting[app.id] = fallback.uid
                followsDefault.insert(app.id)
                singleModeTapsToSwitch.append((tap: tap, fallbackUID: fallback.uid))
            } else {
                logger.error("No fallback device available for \(app.name)")
            }
        }

        if !singleModeTapsToSwitch.isEmpty || !multiModeTapsToUpdate.isEmpty {
            Task {
                for (tap, fallbackUID) in singleModeTapsToSwitch {
                    do {
                        try await tap.switchDevice(to: fallbackUID)
                        self.restoreTapState(tap, appID: tap.app.id, primaryDeviceUID: fallbackUID)
                    } catch {
                        self.logger.error("Failed to switch \(tap.app.name) to fallback: \(error.localizedDescription)")
                    }
                }

                for (tap, remainingUIDs) in multiModeTapsToUpdate {
                    do {
                        try await tap.updateDevices(to: remainingUIDs)
                        self.restoreTapState(tap, appID: tap.app.id, primaryDeviceUID: remainingUIDs.first)
                        self.logger.debug("Removed \(deviceName) from \(tap.app.name) multi-device output")
                    } catch {
                        self.logger.error("Failed to update \(tap.app.name) devices: \(error.localizedDescription)")
                    }
                }
            }
        }

        if !affectedApps.isEmpty {
            let fallbackName = fallbackDevice?.name ?? "none"
            logger.info("\(deviceName) disconnected, \(affectedApps.count) app(s) affected")
            if settingsManager.appSettings.showDeviceDisconnectAlerts {
                showDisconnectNotification(deviceName: deviceName, fallbackName: fallbackName, affectedApps: affectedApps)
            }
        }
    }

    /// 장치 connected을(를) 처리합니다
    private func handleDeviceConnected(_ deviceUID: String, name deviceName: String) {
        var affectedApps: [AudioApp] = []
        var tapsToSwitch: [ProcessTapController] = []

        for tap in taps.values {
            let app = tap.app

            guard !settingsManager.isFollowingDefault(for: app.persistenceIdentifier) else { continue }

            let persistedUID = settingsManager.getDeviceRouting(for: app.persistenceIdentifier)
            guard persistedUID == deviceUID else { continue }

            guard appDeviceRouting[app.id] != deviceUID else { continue }

            affectedApps.append(app)
            appDeviceRouting[app.id] = deviceUID
            followsDefault.remove(app.id)
            tapsToSwitch.append(tap)
        }

        if !tapsToSwitch.isEmpty {
            Task {
                for tap in tapsToSwitch {
                    do {
                        try await tap.switchDevice(to: deviceUID)
                        self.restoreTapState(tap, appID: tap.app.id, primaryDeviceUID: deviceUID)
                    } catch {
                        self.logger.error("Failed to switch \(tap.app.name) back to \(deviceName): \(error.localizedDescription)")
                    }
                }
            }
        }

        if !affectedApps.isEmpty {
            logger.info("\(deviceName) reconnected, switched \(affectedApps.count) app(s) back")
            if settingsManager.appSettings.showDeviceDisconnectAlerts {
                showReconnectNotification(deviceName: deviceName, affectedApps: affectedApps)
            }
        }
    }

    private func showReconnectNotification(deviceName: String, affectedApps: [AudioApp]) {
        let content = UNMutableNotificationContent()
        content.title = "Audio Device Reconnected"
        content.body = "\"\(deviceName)\" is back. \(affectedApps.count) app(s) switched back."
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "device-reconnect-\(deviceName)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }

    private func showDisconnectNotification(deviceName: String, fallbackName: String, affectedApps: [AudioApp]) {
        let content = UNMutableNotificationContent()
        content.title = "Audio Device Disconnected"
        content.body = "\"\(deviceName)\" disconnected. \(affectedApps.count) app(s) switched to \(fallbackName)"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "device-disconnect-\(deviceName)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }

    /// 기본 장치 변경을(를) 처리합니다
    private func handleDefaultDeviceChanged(_ newDefaultUID: String) {
        for pid in followsDefault {
            appDeviceRouting[pid] = newDefaultUID
        }

        var tapsToSwitch: [(app: AudioApp, tap: ProcessTapController)] = []
        for app in apps {
            guard followsDefault.contains(app.id) else { continue }
            if let tap = taps[app.id] {
                tapsToSwitch.append((app, tap))
            }
        }

        if !tapsToSwitch.isEmpty {
            Task {
                for (app, tap) in tapsToSwitch {
                    do {
                        try await tap.switchDevice(to: newDefaultUID)
                        self.restoreTapState(tap, appID: app.id, primaryDeviceUID: newDefaultUID)
                    } catch {
                        self.logger.error("Failed to switch \(app.name) to new default: \(error.localizedDescription)")
                    }
                }
            }
        }

        let affectedApps = apps.filter { followsDefault.contains($0.id) }
        if !affectedApps.isEmpty {
            let deviceName = deviceMonitor.device(for: newDefaultUID)?.name ?? "Default Output"
            logger.info("Default changed to \(deviceName), \(affectedApps.count) app(s) following")
            if settingsManager.appSettings.showDeviceDisconnectAlerts {
                showDefaultChangedNotification(newDeviceName: deviceName, affectedApps: affectedApps)
            }
        }
    }

    private func showDefaultChangedNotification(newDeviceName: String, affectedApps: [AudioApp]) {
        let content = UNMutableNotificationContent()
        content.title = "Default Audio Device Changed"
        content.body = "\(affectedApps.count) app(s) switched to \"\(newDeviceName)\""
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "default-device-changed",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }

    /// restore 탭 상태 동작을 처리합니다.
    private func restoreTapState(_ tap: ProcessTapController, appID: pid_t, primaryDeviceUID: String?) {
        tap.volume = volumeState.getVolume(for: appID)
        tap.isMuted = volumeState.getMute(for: appID)
        syncTapDeviceState(tap, primaryDeviceUID: primaryDeviceUID)
    }

    /// 탭 장치 상태을(를) 동기화합니다
    private func syncTapDeviceState(_ tap: ProcessTapController, primaryDeviceUID: String?) {
        guard let primaryDeviceUID,
              let device = deviceMonitor.device(for: primaryDeviceUID) else { return }
        tap.currentDeviceVolume = deviceVolumeMonitor.volumes[device.id] ?? 1.0
        tap.isDeviceMuted = deviceVolumeMonitor.muteStates[device.id] ?? false
    }

    /// persisted gain 상태을(를) 적용합니다
    private func applyPersistedGainState(
        to tap: ProcessTapController,
        volume: Float?,
        muted: Bool?,
        appName: String? = nil
    ) {
        if let volume {
            if let appName {
                let displayPercent = Int(VolumeMapping.gainToSlider(volume) * 200)
                logger.debug("Applying saved volume \(displayPercent)% to \(appName)")
            }
            tap.volume = volume
        }

        if muted == true {
            if let appName {
                logger.debug("Applying saved mute state to \(appName)")
            }
            tap.isMuted = true
        }
    }

    func cleanupStaleTaps() {
        let activePIDs = Set(apps.map { $0.id })
        let stalePIDs = Set(taps.keys).subtracting(activePIDs)

        for pid in activePIDs {
            if let task = pendingCleanup.removeValue(forKey: pid) {
                task.cancel()
                logger.debug("Cancelled pending cleanup for PID \(pid) - app reappeared")
            }
        }

        for pid in stalePIDs {
            guard pendingCleanup[pid] == nil else { continue }

            pendingCleanup[pid] = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                let currentPIDs = Set(self.apps.map { $0.id })
                guard !currentPIDs.contains(pid) else {
                    self.pendingCleanup.removeValue(forKey: pid)
                    return
                }

                if let tap = self.taps.removeValue(forKey: pid) {
                    tap.invalidate()
                    self.logger.debug("Cleaned up stale tap for PID \(pid)")
                }
                self.appDeviceRouting.removeValue(forKey: pid)
                self.followsDefault.remove(pid)
                self.appliedPIDs.remove(pid)
                self.pendingCleanup.removeValue(forKey: pid)
            }
        }

        let pidsToKeep = activePIDs.union(Set(pendingCleanup.keys))
        appliedPIDs = appliedPIDs.intersection(pidsToKeep)
        followsDefault = followsDefault.intersection(pidsToKeep)
        volumeState.cleanup(keeping: pidsToKeep)
    }

}
