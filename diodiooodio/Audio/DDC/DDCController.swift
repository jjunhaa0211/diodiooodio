
#if !APP_STORE

import AppKit
import AudioToolbox
import CoreGraphics
import IOKit
import os

@Observable
@MainActor
final class DDCController {
    /// ddc backed 장치 목록입니다.
    private(set) var ddcBackedDevices: Set<AudioDeviceID> = []

    /// probe completed 상태를 나타냅니다.
    private(set) var probeCompleted: Bool = false

    /// cached 볼륨 목록입니다.
    private(set) var cachedVolumes: [AudioDeviceID: Int] = [:]

    private var services: [AudioDeviceID: DDCService] = [:]
    private var deviceUIDs: [AudioDeviceID: String] = [:]
    private var debounceTimers: [AudioDeviceID: DispatchWorkItem] = [:]

    private let ddcQueue = DispatchQueue(label: "com.diodiooodio.ddc", qos: .userInitiated)
    private let settingsManager: SettingsManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "diodiooodio", category: "DDCController")

    /// probe completed 시 실행되는 콜백입니다.
    var onProbeCompleted: (() -> Void)?

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    // MARK: - 시작

    func start() {
        probe()
        setupDisplayChangeObserver()
    }

    // MARK: - is ddcbacked

    /// ddcbacked 여부를 반환합니다.
    func isDDCBacked(_ deviceID: AudioDeviceID) -> Bool {
        ddcBackedDevices.contains(deviceID)
    }

    /// 볼륨을(를) 조회합니다
    func getVolume(for deviceID: AudioDeviceID) -> Int? {
        cachedVolumes[deviceID]
    }

    /// 볼륨을(를) 설정합니다
    func setVolume(for deviceID: AudioDeviceID, to volume: Int) {
        let clamped = max(0, min(100, volume))
        cachedVolumes[deviceID] = clamped

        if let uid = deviceUIDs[deviceID] {
            settingsManager.setDDCVolume(for: uid, to: clamped)
        }

        debounceTimers[deviceID]?.cancel()
        let service = services[deviceID]
        let item = DispatchWorkItem { [weak self] in
            do {
                try service?.setAudioVolume(clamped)
            } catch {
                self?.logger.error("DDC write failed for device \(deviceID): \(error)")
            }
        }
        debounceTimers[deviceID] = item
        ddcQueue.asyncAfter(deadline: .now() + .milliseconds(100), execute: item)
    }

    /// 음소거 동작을 처리합니다.
    func mute(for deviceID: AudioDeviceID) {
        guard let uid = deviceUIDs[deviceID] else { return }
        let currentVolume = cachedVolumes[deviceID] ?? 50
        if currentVolume > 0 {
            settingsManager.setDDCSavedVolume(for: uid, to: currentVolume)
        }
        settingsManager.setDDCMuteState(for: uid, to: true)
        setVolume(for: deviceID, to: 0)
    }

    /// unmute 동작을 처리합니다.
    func unmute(for deviceID: AudioDeviceID) {
        guard let uid = deviceUIDs[deviceID] else { return }
        let savedVolume = settingsManager.getDDCSavedVolume(for: uid) ?? 50
        settingsManager.setDDCMuteState(for: uid, to: false)
        setVolume(for: deviceID, to: savedVolume)
    }

    /// 음소거 여부를 반환합니다.
    func isMuted(for deviceID: AudioDeviceID) -> Bool {
        guard let uid = deviceUIDs[deviceID] else { return false }
        return settingsManager.getDDCMuteState(for: uid)
    }

    // MARK: - probe

    /// probe 동작을 처리합니다.
    private func probe() {
        ddcQueue.async { [weak self] in
            guard let self else { return }

            let discovered = DDCService.discoverServices()
            self.logger.info("DDC probe: found \(discovered.count) DCPAVServiceProxy entries")
            guard !discovered.isEmpty else {
                Task { @MainActor [weak self] in
                    self?.ddcBackedDevices = []
                    self?.services = [:]
                    self?.probeCompleted = true
                    self?.onProbeCompleted?()
                }
                return
            }

            var audioCapable: [(entry: io_service_t, service: DDCService, displayName: String)] = []
            for (index, (entry, service)) in discovered.enumerated() {
                let name = Self.getDisplayName(for: entry)
                self.logger.info("DDC probe: checking display \(index + 1) '\(name)' for VCP 0x62...")
                if service.supportsAudioVolume() {
                    audioCapable.append((entry: entry, service: service, displayName: name))
                    self.logger.info("DDC audio-capable display: '\(name)'")
                } else {
                    self.logger.info("DDC probe: '\(name)' does not support VCP 0x62")
                    IOObjectRelease(entry)
                }
            }

            guard !audioCapable.isEmpty else {
                self.logger.info("DDC probe: no audio-capable displays found")
                Task { @MainActor [weak self] in
                    self?.ddcBackedDevices = []
                    self?.services = [:]
                    self?.probeCompleted = true
                    self?.onProbeCompleted?()
                }
                return
            }

            let coreAudioDevices = self.getCoreAudioOutputDevices()
            for ca in coreAudioDevices {
                self.logger.info("DDC probe: CoreAudio candidate: '\(ca.name)' (uid: \(ca.uid))")
            }

            var matched: [AudioDeviceID: DDCService] = [:]
            var matchedUIDs: [AudioDeviceID: String] = [:]
            var volumes: [AudioDeviceID: Int] = [:]
            var matchedDDCIndices = Set<Int>()

            for caDevice in coreAudioDevices {
                for (i, ddcDisplay) in audioCapable.enumerated() where !matchedDDCIndices.contains(i) {
                    if Self.namesMatch(caDevice.name, ddcDisplay.displayName) {
                        matched[caDevice.id] = ddcDisplay.service
                        matchedUIDs[caDevice.id] = caDevice.uid
                        matchedDDCIndices.insert(i)

                        if let vol = try? ddcDisplay.service.getAudioVolume() {
                            volumes[caDevice.id] = vol.current
                        }

                        self.logger.info("Matched CoreAudio '\(caDevice.name)' → DDC '\(ddcDisplay.displayName)' (by name)")
                        break
                    }
                }
            }

            let displayTransports: Set<TransportType> = [.hdmi, .displayPort, .thunderbolt]
            let unmatchedDisplayDevices = coreAudioDevices.filter { ca in
                !matched.keys.contains(ca.id) && displayTransports.contains(ca.transport)
            }
            let unmatchedDDC = audioCapable.enumerated().filter { !matchedDDCIndices.contains($0.offset) }

            for (i, ddcDisplay) in unmatchedDDC {
                for caDevice in unmatchedDisplayDevices where !matched.keys.contains(caDevice.id) {
                    matched[caDevice.id] = ddcDisplay.service
                    matchedUIDs[caDevice.id] = caDevice.uid
                    matchedDDCIndices.insert(i)

                    if let vol = try? ddcDisplay.service.getAudioVolume() {
                        volumes[caDevice.id] = vol.current
                    }

                    self.logger.info("Matched CoreAudio '\(caDevice.name)' → DDC '\(ddcDisplay.displayName)' (by transport: \(caDevice.transport))")
                    break
                }
            }

            for item in audioCapable {
                IOObjectRelease(item.entry)
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.services = matched
                self.deviceUIDs = matchedUIDs
                self.ddcBackedDevices = Set(matched.keys)

                for (deviceID, uid) in matchedUIDs {
                    if let savedVolume = self.settingsManager.getDDCVolume(for: uid) {
                        self.cachedVolumes[deviceID] = savedVolume
                        let service = matched[deviceID]
                        self.ddcQueue.async {
                            try? service?.setAudioVolume(savedVolume)
                        }
                    } else if let readVolume = volumes[deviceID] {
                        self.cachedVolumes[deviceID] = readVolume
                    }
                }

                self.logger.info("DDC probe complete: \(matched.count) display(s) matched")
                self.probeCompleted = true
                self.onProbeCompleted?()
            }
        }
    }

    // MARK: - CoreAudioDeviceInfo 정의

    private struct CoreAudioDeviceInfo: Sendable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let transport: TransportType
    }

    /// core 오디오 출력 장치을(를) 조회합니다
    private nonisolated func getCoreAudioOutputDevices() -> [CoreAudioDeviceInfo] {
        guard let deviceIDs = try? AudioObjectID.readDeviceList() else { return [] }

        var results: [CoreAudioDeviceInfo] = []
        for deviceID in deviceIDs {
            guard !deviceID.isAggregateDevice(),
                  !deviceID.isVirtualDevice(),
                  deviceID.hasOutputStreams() else { continue }

            guard let uid = try? deviceID.readDeviceUID(),
                  let name = try? deviceID.readDeviceName() else { continue }

            results.append(CoreAudioDeviceInfo(id: deviceID, uid: uid, name: name, transport: deviceID.readTransportType()))
        }
        return results
    }

    // MARK: - names match

    /// names match 동작을 처리합니다.
    private nonisolated static func namesMatch(_ a: String, _ b: String) -> Bool {
        let normA = a.trimmingCharacters(in: .whitespaces).lowercased()
        let normB = b.trimmingCharacters(in: .whitespaces).lowercased()
        if normA == normB { return true }
        if normA.contains(normB) || normB.contains(normA) { return true }
        return false
    }

    // MARK: - 조회 표시

    /// 표시 이름을(를) 조회합니다
    private nonisolated static func getDisplayName(for entry: io_service_t) -> String {
        var current = entry
        IOObjectRetain(current)

        for _ in 0..<10 {
            if let name = displayNameFromEntry(current) {
                IOObjectRelease(current)
                return name
            }

            var next: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &next)
            IOObjectRelease(current)
            guard kr == kIOReturnSuccess else { break }
            current = next
        }

        return "External Display"
    }

    private nonisolated static func displayNameFromEntry(_ entry: io_service_t) -> String? {
        guard let info = IODisplayCreateInfoDictionary(entry, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any],
              let names = info[kDisplayProductName] as? [String: String],
              let name = names.values.first else {
            return nil
        }
        return name
    }

    // MARK: - setup 표시

    private func setupDisplayChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logger.debug("Display configuration changed, re-probing DDC")
                self?.probe()
            }
        }
    }
}

#endif
