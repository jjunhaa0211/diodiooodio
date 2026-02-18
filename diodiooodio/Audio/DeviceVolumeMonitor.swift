import AudioToolbox
import os

@Observable
@MainActor
final class DeviceVolumeMonitor {
    // MARK: - 볼륨

    /// 볼륨 목록입니다.
    private(set) var volumes: [AudioDeviceID: Float] = [:]

    /// 음소거 상태 상태를 나타냅니다.
    private(set) var muteStates: [AudioDeviceID: Bool] = [:]

    /// 기본 장치 ID 식별자입니다.
    private(set) var defaultDeviceID: AudioDeviceID = .unknown

    /// 기본 장치 UID 식별자입니다.
    private(set) var defaultDeviceUID: String?

    /// 볼륨 변경 시 실행되는 콜백입니다.
    var onVolumeChanged: ((AudioDeviceID, Float) -> Void)?

    /// 음소거 변경 시 실행되는 콜백입니다.
    var onMuteChanged: ((AudioDeviceID, Bool) -> Void)?

    /// 기본 장치 변경 시 실행되는 콜백입니다.
    var onDefaultDeviceChanged: ((String) -> Void)?

    private let deviceMonitor: AudioDeviceMonitor
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "diodiooodio", category: "DeviceVolumeMonitor")

    #if !APP_STORE
    private let ddcController: DDCController?
    #endif

    /// 볼륨 리스너 목록입니다.
    private var volumeListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    /// 음소거 리스너 목록입니다.
    private var muteListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    /// observing 장치 목록 여부를 나타냅니다.
    private var isObservingDeviceList = false

    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    #if !APP_STORE
    init(deviceMonitor: AudioDeviceMonitor, ddcController: DDCController? = nil) {
        self.deviceMonitor = deviceMonitor
        self.ddcController = ddcController
    }
    #else
    init(deviceMonitor: AudioDeviceMonitor) {
        self.deviceMonitor = deviceMonitor
    }
    #endif

    func start() {
        guard defaultDeviceListenerBlock == nil else { return }

        logger.debug("Starting device volume monitor")

        refreshDefaultDevice()

        refreshDeviceListeners()

        defaultDeviceListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDefaultDeviceChanged()
            }
        }

        let defaultDeviceStatus = AudioObjectAddPropertyListenerBlock(
            .system,
            &defaultDeviceAddress,
            .main,
            defaultDeviceListenerBlock!
        )

        if defaultDeviceStatus != noErr {
            logger.error("Failed to add default device listener: \(defaultDeviceStatus)")
        }

        startObservingDeviceList()
    }

    func stop() {
        logger.debug("Stopping device volume monitor")

        isObservingDeviceList = false

        if let block = defaultDeviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &defaultDeviceAddress, .main, block)
            defaultDeviceListenerBlock = nil
        }

        for deviceID in Array(volumeListeners.keys) {
            removeVolumeListener(for: deviceID)
        }

        for deviceID in Array(muteListeners.keys) {
            removeMuteListener(for: deviceID)
        }

        volumes.removeAll()
        muteStates.removeAll()
    }

    /// 볼륨을(를) 설정합니다
    func setVolume(for deviceID: AudioDeviceID, to volume: Float) {
        guard deviceID.isValid else {
            logger.warning("Cannot set volume: invalid device ID")
            return
        }

        let success = deviceID.setOutputVolumeScalar(volume)
        if success {
            volumes[deviceID] = volume
        } else {
            #if !APP_STORE
            if let ddcController, ddcController.isDDCBacked(deviceID) {
                let ddcVolume = Int(round(volume * 100))
                ddcController.setVolume(for: deviceID, to: ddcVolume)
                volumes[deviceID] = volume
            } else {
                logger.warning("Failed to set volume on device \(deviceID)")
            }
            #else
            logger.warning("Failed to set volume on device \(deviceID)")
            #endif
        }
    }

    /// 기본 장치을(를) 설정합니다
    func setDefaultDevice(_ deviceID: AudioDeviceID) {
        guard deviceID.isValid else {
            logger.warning("Cannot set default device: invalid device ID")
            return
        }

        do {
            try AudioDeviceID.setDefaultOutputDevice(deviceID)
            logger.debug("Set default output device to \(deviceID)")
        } catch {
            logger.error("Failed to set default device: \(error.localizedDescription)")
        }
    }

    /// 음소거을(를) 설정합니다
    func setMute(for deviceID: AudioDeviceID, to muted: Bool) {
        guard deviceID.isValid else {
            logger.warning("Cannot set mute: invalid device ID")
            return
        }

        let success = deviceID.setMuteState(muted)
        if success {
            muteStates[deviceID] = muted
        } else {
            #if !APP_STORE
            if let ddcController, ddcController.isDDCBacked(deviceID) {
                if muted {
                    ddcController.mute(for: deviceID)
                } else {
                    ddcController.unmute(for: deviceID)
                }
                muteStates[deviceID] = muted
            } else {
                logger.warning("Failed to set mute on device \(deviceID)")
            }
            #else
            logger.warning("Failed to set mute on device \(deviceID)")
            #endif
        }
    }

    #if !APP_STORE
    /// refresh after ddcprobe 동작을 처리합니다.
    func refreshAfterDDCProbe() {
        readAllStates()
    }
    #endif

    // MARK: - refresh 기본

    private func refreshDefaultDevice() {
        do {
            let newDeviceID: AudioDeviceID = try AudioObjectID.system.read(
                kAudioHardwarePropertyDefaultOutputDevice,
                defaultValue: AudioDeviceID.unknown
            )

            if newDeviceID.isValid {
                defaultDeviceID = newDeviceID
                defaultDeviceUID = try? newDeviceID.readDeviceUID()
                logger.debug("Default device ID: \(self.defaultDeviceID), UID: \(self.defaultDeviceUID ?? "nil")")
            } else {
                logger.warning("Default output device is invalid")
                defaultDeviceID = .unknown
                defaultDeviceUID = nil
            }

        } catch {
            logger.error("Failed to read default output device: \(error.localizedDescription)")
        }
    }

    private func handleDefaultDeviceChanged() {
        let oldUID = defaultDeviceUID
        logger.debug("Default output device changed")
        refreshDefaultDevice()
        if let newUID = defaultDeviceUID, newUID != oldUID {
            onDefaultDeviceChanged?(newUID)
        }
    }

    /// refresh 장치 리스너 동작을 처리합니다.
    private func refreshDeviceListeners() {
        let currentDeviceIDs = Set(deviceMonitor.outputDevices.map(\.id))
        let trackedVolumeIDs = Set(volumeListeners.keys)
        let trackedMuteIDs = Set(muteListeners.keys)

        let newDeviceIDs = currentDeviceIDs.subtracting(trackedVolumeIDs)
        for deviceID in newDeviceIDs {
            addVolumeListener(for: deviceID)
            addMuteListener(for: deviceID)
        }

        let staleVolumeIDs = trackedVolumeIDs.subtracting(currentDeviceIDs)
        for deviceID in staleVolumeIDs {
            removeVolumeListener(for: deviceID)
            volumes.removeValue(forKey: deviceID)
        }

        let staleMuteIDs = trackedMuteIDs.subtracting(currentDeviceIDs)
        for deviceID in staleMuteIDs {
            removeMuteListener(for: deviceID)
            muteStates.removeValue(forKey: deviceID)
        }

        readAllStates()
    }

    private func addVolumeListener(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        guard volumeListeners[deviceID] == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleVolumeChanged(for: deviceID)
            }
        }

        volumeListeners[deviceID] = block

        var address = volumeAddress
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            .main,
            block
        )

        if status != noErr {
            logger.warning("Failed to add volume listener for device \(deviceID): \(status)")
            volumeListeners.removeValue(forKey: deviceID)
        }
    }

    private func removeVolumeListener(for deviceID: AudioDeviceID) {
        guard let block = volumeListeners[deviceID] else { return }

        var address = volumeAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        volumeListeners.removeValue(forKey: deviceID)
    }

    private func handleVolumeChanged(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }

        #if !APP_STORE
        if let ddcController, ddcController.isDDCBacked(deviceID) { return }
        #endif

        let newVolume = deviceID.readOutputVolumeScalar()
        volumes[deviceID] = newVolume
        onVolumeChanged?(deviceID, newVolume)
        logger.debug("Volume changed for device \(deviceID): \(newVolume)")
    }

    private func addMuteListener(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        guard muteListeners[deviceID] == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleMuteChanged(for: deviceID)
            }
        }

        muteListeners[deviceID] = block

        var address = muteAddress
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            .main,
            block
        )

        if status != noErr {
            logger.warning("Failed to add mute listener for device \(deviceID): \(status)")
            muteListeners.removeValue(forKey: deviceID)
        }
    }

    private func removeMuteListener(for deviceID: AudioDeviceID) {
        guard let block = muteListeners[deviceID] else { return }

        var address = muteAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        muteListeners.removeValue(forKey: deviceID)
    }

    private func handleMuteChanged(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        let newMuteState = deviceID.readMuteState()
        muteStates[deviceID] = newMuteState
        onMuteChanged?(deviceID, newMuteState)
        logger.debug("Mute changed for device \(deviceID): \(newMuteState)")
    }

    /// read all 상태 동작을 처리합니다.
    private func readAllStates() {
        for device in deviceMonitor.outputDevices {
            #if !APP_STORE
            if let ddcController, ddcController.isDDCBacked(device.id) {
                if let ddcVolume = ddcController.getVolume(for: device.id) {
                    volumes[device.id] = Float(ddcVolume) / 100.0
                } else {
                    volumes[device.id] = 0.5
                }
                muteStates[device.id] = ddcController.isMuted(for: device.id)
                continue
            }
            #endif

            let volume = device.id.readOutputVolumeScalar()
            volumes[device.id] = volume

            let muted = device.id.readMuteState()
            muteStates[device.id] = muted

            let transportType = device.id.readTransportType()
            if transportType == .bluetooth || transportType == .bluetoothLE {
                let deviceID = device.id
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let self, self.volumes.keys.contains(deviceID) else { return }
                    let confirmedVolume = deviceID.readOutputVolumeScalar()
                    let confirmedMute = deviceID.readMuteState()
                    self.volumes[deviceID] = confirmedVolume
                    self.muteStates[deviceID] = confirmedMute
                    self.logger.debug("Bluetooth device \(deviceID) confirmed volume: \(confirmedVolume), muted: \(confirmedMute)")
                }
            }
        }
    }

    /// observing 장치 목록을(를) 시작합니다
    private func startObservingDeviceList() {
        guard !isObservingDeviceList else { return }
        isObservingDeviceList = true

        func observe() {
            guard isObservingDeviceList else { return }
            withObservationTracking {
                _ = self.deviceMonitor.outputDevices
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isObservingDeviceList else { return }
                    self.logger.debug("Device list changed, refreshing volume listeners")
                    self.refreshDeviceListeners()
                    observe()
                }
            }
        }
        observe()
    }

    deinit {
    }
}
