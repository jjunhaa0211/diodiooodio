import Foundation

/// DeviceSelectionMode 열거형를 정의합니다.
enum DeviceSelectionMode: String, Codable, Equatable {
    case single
    case multi
}

/// AppAudioState 구조체를 정의합니다.
struct AppAudioState {
    var volume: Float
    var muted: Bool
    var persistenceIdentifier: String
    var deviceSelectionMode: DeviceSelectionMode = .single
    var selectedDeviceUIDs: Set<String> = []
}

@Observable
@MainActor
final class VolumeState {
    /// 상태 목록입니다.
    private var states: [pid_t: AppAudioState] = [:]
    private let settingsManager: SettingsManager?

    init(settingsManager: SettingsManager? = nil) {
        self.settingsManager = settingsManager
    }

    // MARK: - 조회 볼륨

    func getVolume(for pid: pid_t) -> Float {
        states[pid]?.volume ?? (settingsManager?.appSettings.defaultNewAppVolume ?? 1.0)
    }

    func setVolume(for pid: pid_t, to volume: Float, identifier: String? = nil) {
        if var state = states[pid] {
            state.volume = volume
            if let identifier = identifier {
                state.persistenceIdentifier = identifier
            }
            states[pid] = state
            settingsManager?.setVolume(for: state.persistenceIdentifier, to: volume)
        } else if let identifier = identifier {
            states[pid] = AppAudioState(volume: volume, muted: false, persistenceIdentifier: identifier)
            settingsManager?.setVolume(for: identifier, to: volume)
        }
    }

    func loadSavedVolume(for pid: pid_t, identifier: String) -> Float? {
        ensureState(for: pid, identifier: identifier)
        if let saved = settingsManager?.getVolume(for: identifier) {
            states[pid]?.volume = saved
            return saved
        }
        return nil
    }

    // MARK: - 조회 음소거

    func getMute(for pid: pid_t) -> Bool {
        states[pid]?.muted ?? false
    }

    func setMute(for pid: pid_t, to muted: Bool, identifier: String? = nil) {
        if var state = states[pid] {
            state.muted = muted
            if let identifier = identifier {
                state.persistenceIdentifier = identifier
            }
            states[pid] = state
            settingsManager?.setMute(for: state.persistenceIdentifier, to: muted)
        } else if let identifier = identifier {
            let defaultVolume = settingsManager?.appSettings.defaultNewAppVolume ?? 1.0
            states[pid] = AppAudioState(volume: defaultVolume, muted: muted, persistenceIdentifier: identifier)
            settingsManager?.setMute(for: identifier, to: muted)
        }
    }

    func loadSavedMute(for pid: pid_t, identifier: String) -> Bool? {
        ensureState(for: pid, identifier: identifier)
        if let saved = settingsManager?.getMute(for: identifier) {
            states[pid]?.muted = saved
            return saved
        }
        return nil
    }

    // MARK: - 조회 장치

    func getDeviceSelectionMode(for pid: pid_t) -> DeviceSelectionMode {
        states[pid]?.deviceSelectionMode ?? .single
    }

    func setDeviceSelectionMode(for pid: pid_t, to mode: DeviceSelectionMode, identifier: String? = nil) {
        if var state = states[pid] {
            state.deviceSelectionMode = mode
            if let identifier = identifier {
                state.persistenceIdentifier = identifier
            }
            states[pid] = state
            settingsManager?.setDeviceSelectionMode(for: state.persistenceIdentifier, to: mode)
        } else if let identifier = identifier {
            let defaultVolume = settingsManager?.appSettings.defaultNewAppVolume ?? 1.0
            var newState = AppAudioState(volume: defaultVolume, muted: false, persistenceIdentifier: identifier)
            newState.deviceSelectionMode = mode
            states[pid] = newState
            settingsManager?.setDeviceSelectionMode(for: identifier, to: mode)
        }
    }

    func loadSavedDeviceSelectionMode(for pid: pid_t, identifier: String) -> DeviceSelectionMode? {
        ensureState(for: pid, identifier: identifier)
        if let saved = settingsManager?.getDeviceSelectionMode(for: identifier) {
            states[pid]?.deviceSelectionMode = saved
            return saved
        }
        return nil
    }

    // MARK: - 조회 선택된

    func getSelectedDeviceUIDs(for pid: pid_t) -> Set<String> {
        states[pid]?.selectedDeviceUIDs ?? []
    }

    func setSelectedDeviceUIDs(for pid: pid_t, to uids: Set<String>, identifier: String? = nil) {
        if var state = states[pid] {
            state.selectedDeviceUIDs = uids
            if let identifier = identifier {
                state.persistenceIdentifier = identifier
            }
            states[pid] = state
            settingsManager?.setSelectedDeviceUIDs(for: state.persistenceIdentifier, to: uids)
        } else if let identifier = identifier {
            let defaultVolume = settingsManager?.appSettings.defaultNewAppVolume ?? 1.0
            var newState = AppAudioState(volume: defaultVolume, muted: false, persistenceIdentifier: identifier)
            newState.selectedDeviceUIDs = uids
            states[pid] = newState
            settingsManager?.setSelectedDeviceUIDs(for: identifier, to: uids)
        }
    }

    func loadSavedSelectedDeviceUIDs(for pid: pid_t, identifier: String) -> Set<String>? {
        ensureState(for: pid, identifier: identifier)
        if let saved = settingsManager?.getSelectedDeviceUIDs(for: identifier) {
            states[pid]?.selectedDeviceUIDs = saved
            return saved
        }
        return nil
    }

    // MARK: - 제거 볼륨

    func removeVolume(for pid: pid_t) {
        states.removeValue(forKey: pid)
    }

    func cleanup(keeping pids: Set<pid_t>) {
        states = states.filter { pids.contains($0.key) }
    }

    // MARK: - ensure 상태

    private func ensureState(for pid: pid_t, identifier: String) {
        if states[pid] == nil {
            let defaultVolume = settingsManager?.appSettings.defaultNewAppVolume ?? 1.0
            states[pid] = AppAudioState(volume: defaultVolume, muted: false, persistenceIdentifier: identifier)
        } else if states[pid]?.persistenceIdentifier != identifier {
            states[pid]?.persistenceIdentifier = identifier
        }
    }
}
