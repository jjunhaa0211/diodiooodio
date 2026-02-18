@preconcurrency import AppKit
import CoreAudio
import Foundation

@MainActor
final class AudioControlViewModel: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var activeApps: [AppAudioTarget] = []
    @Published private(set) var engineStatus: String = "CoreAudio MVP active"
    @Published var selectedOutputDeviceID: AudioDeviceID = .zero
    @Published var systemVolume: Float = 0
    @Published var lastErrorMessage: String?

    private let audioService: AudioHardwareControlling
    private var workspaceObservers: [NSObjectProtocol] = []

    init(audioService: AudioHardwareControlling = CoreAudioService()) {
        self.audioService = audioService
        bindObservers()
        refresh()
    }

    func refresh() {
        refreshAudio()
        refreshActiveApps()
    }

    func setDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        do {
            try audioService.setDefaultOutputDevice(deviceID)
            selectedOutputDeviceID = deviceID
            refreshAudio()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setSystemVolume(_ value: Float) {
        let normalized = max(0, min(1, value))
        do {
            try audioService.setSystemVolume(normalized)
            systemVolume = normalized
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setAppVolume(bundleId: String, value: Float) {
        updateApp(bundleId: bundleId) { app in
            app.volume = max(0, min(1, value))
        }
    }

    func toggleMute(bundleId: String) {
        updateApp(bundleId: bundleId) { app in
            app.isMuted.toggle()
        }
    }

    func setRoute(bundleId: String, deviceID: AudioDeviceID?) {
        updateApp(bundleId: bundleId) { app in
            app.routedDeviceId = deviceID
        }
    }

    func outputDeviceName(for deviceID: AudioDeviceID?) -> String {
        guard let deviceID else { return "System Default" }
        return devices.first(where: { $0.id == deviceID })?.name ?? "Unknown Device"
    }

    private func refreshAudio() {
        do {
            let fetchedDevices = try audioService.outputDevices()
            let defaultID = try audioService.defaultOutputDeviceID()
            let volume = try audioService.systemVolume()

            devices = fetchedDevices
            selectedOutputDeviceID = defaultID
            systemVolume = volume
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func refreshActiveApps() {
        let previousState = Dictionary(uniqueKeysWithValues: activeApps.map { ($0.bundleId, $0) })

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppAudioTarget? in
                guard let bundleId = app.bundleIdentifier else { return nil }
                let appName = app.localizedName ?? bundleId

                if let existing = previousState[bundleId] {
                    var updated = existing
                    updated.appName = appName
                    return updated
                }

                return AppAudioTarget(
                    bundleId: bundleId,
                    appName: appName,
                    volume: 1,
                    isMuted: false,
                    routedDeviceId: nil
                )
            }
            .sorted { lhs, rhs in
                lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }

        activeApps = apps
    }

    private func updateApp(bundleId: String, transform: (inout AppAudioTarget) -> Void) {
        guard let index = activeApps.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        var app = activeApps[index]
        transform(&app)
        activeApps[index] = app
    }

    private func bindObservers() {
        audioService.startObservingChanges { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshAudio()
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshActiveApps()
            }
        }
        let terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshActiveApps()
            }
        }
        workspaceObservers = [launchObserver, terminateObserver]
    }
}
