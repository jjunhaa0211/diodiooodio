import AppKit
import AudioToolbox
import os

@Observable
@MainActor
final class AudioDeviceMonitor {
    // MARK: - 출력 장치 목록

    private(set) var outputDevices: [AudioDevice] = []

    /// 장치 by UID 식별자입니다.
    private(set) var devicesByUID: [String: AudioDevice] = [:]

    /// 장치 by ID 식별자입니다.
    private(set) var devicesByID: [AudioDeviceID: AudioDevice] = [:]

    /// 장치 disconnected 시 실행되는 콜백입니다.
    var onDeviceDisconnected: ((_ uid: String, _ name: String) -> Void)?

    /// 장치 connected 시 실행되는 콜백입니다.
    var onDeviceConnected: ((_ uid: String, _ name: String) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "diodiooodio", category: "AudioDeviceMonitor")

    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var knownDeviceUIDs: Set<String> = []
    func start() {
        guard deviceListListenerBlock == nil else { return }

        logger.debug("Starting audio device monitor")

        refresh()

        deviceListListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDeviceListChanged()
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            .system,
            &deviceListAddress,
            .main,
            deviceListListenerBlock!
        )

        if status != noErr {
            logger.error("Failed to add device list listener: \(status)")
        }
    }

    func stop() {
        logger.debug("Stopping audio device monitor")

        if let block = deviceListListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &deviceListAddress, .main, block)
            deviceListListenerBlock = nil
        }
    }

    /// 장치 동작을 처리합니다.
    func device(for uid: String) -> AudioDevice? {
        devicesByUID[uid]
    }

    /// 장치 동작을 처리합니다.
    func device(for id: AudioDeviceID) -> AudioDevice? {
        devicesByID[id]
    }

    private func refresh() {
        do {
            let deviceIDs = try AudioObjectID.readDeviceList()
            var outputDeviceList: [AudioDevice] = []

            for deviceID in deviceIDs {
                guard !deviceID.isAggregateDevice() else { continue }

                guard let uid = try? deviceID.readDeviceUID(),
                      let name = try? deviceID.readDeviceName() else {
                    continue
                }

                if deviceID.hasOutputStreams() && !deviceID.isVirtualDevice() {
                    let icon = DeviceIconCache.shared.icon(for: uid) {
                        deviceID.readDeviceIcon()
                    } ?? NSImage(systemSymbolName: deviceID.suggestedIconSymbol(), accessibilityDescription: name)

                    let device = AudioDevice(
                        id: deviceID,
                        uid: uid,
                        name: name,
                        icon: icon
                    )
                    outputDeviceList.append(device)
                }

            }

            outputDevices = outputDeviceList.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            knownDeviceUIDs = Set(outputDeviceList.map(\.uid))
            devicesByUID = Dictionary(uniqueKeysWithValues: outputDevices.map { ($0.uid, $0) })
            devicesByID = Dictionary(uniqueKeysWithValues: outputDevices.map { ($0.id, $0) })

        } catch {
            logger.error("Failed to refresh device list: \(error.localizedDescription)")
        }
    }

    private func handleDeviceListChanged() {
        let previousOutputUIDs = knownDeviceUIDs

        var outputDeviceNames: [String: String] = [:]
        for device in outputDevices {
            outputDeviceNames[device.uid] = device.name
        }

        refresh()

        let currentOutputUIDs = knownDeviceUIDs
        let disconnectedOutputUIDs = previousOutputUIDs.subtracting(currentOutputUIDs)
        for uid in disconnectedOutputUIDs {
            let name = outputDeviceNames[uid] ?? uid
            logger.info("Output device disconnected: \(name) (\(uid))")
            onDeviceDisconnected?(uid, name)
        }
        let connectedOutputUIDs = currentOutputUIDs.subtracting(previousOutputUIDs)
        for uid in connectedOutputUIDs {
            if let device = devicesByUID[uid] {
                logger.info("Output device connected: \(device.name) (\(uid))")
                onDeviceConnected?(uid, device.name)
            }
        }
    }

    deinit {
    }
}
