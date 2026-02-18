import AppKit
import AudioToolbox
import os

@Observable
@MainActor
final class AudioProcessMonitor {
    private(set) var activeApps: [AudioApp] = []
    var onAppsChanged: (([AudioApp]) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "diodiooodio", category: "AudioProcessMonitor")

    /// system daemon prefixes 목록입니다.
    private static let systemDaemonPrefixes: [String] = [
        "com.apple.siri",
        "com.apple.Siri",
        "com.apple.assistant",
        "com.apple.audio",
        "com.apple.coreaudio",
        "com.apple.mediaremote",
        "com.apple.accessibility.heard",
        "com.apple.hearingd",
        "com.apple.voicebankingd",
        "com.apple.systemsound",
        "com.apple.FrontBoardServices",
        "com.apple.frontboard",
        "com.apple.springboard",
        "com.apple.notificationcenter",
        "com.apple.NotificationCenter",
        "com.apple.UserNotifications",
        "com.apple.usernotifications",
    ]

    /// system daemon names 목록입니다.
    private static let systemDaemonNames: [String] = [
        "systemsoundserverd",
        "systemsoundserv",
        "coreaudiod",
        "audiomxd",
    ]

    /// system daemon 여부를 반환합니다.
    private func isSystemDaemon(bundleID: String?, name: String) -> Bool {
        if let bundleID {
            if Self.systemDaemonPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                return true
            }
        }

        let lowercaseName = name.lowercased()
        if Self.systemDaemonNames.contains(where: { lowercaseName.hasPrefix($0) }) {
            return true
        }

        return false
    }

    private var processListListenerBlock: AudioObjectPropertyListenerBlock?
    private var processListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var monitoredProcesses: Set<AudioObjectID> = []

    private var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// 내부 동작을 담당합니다.
    private typealias ResponsibilityFunc = @convention(c) (pid_t) -> pid_t

    /// responsible pid을(를) 조회합니다
    private func getResponsiblePID(for pid: pid_t) -> pid_t? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -1), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        let responsiblePID = unsafeBitCast(symbol, to: ResponsibilityFunc.self)(pid)
        return responsiblePID > 0 && responsiblePID != pid ? responsiblePID : nil
    }

    /// find responsible 앱 동작을 처리합니다.
    private func findResponsibleApp(for pid: pid_t, in runningApps: [NSRunningApplication]) -> NSRunningApplication? {
        if let responsiblePID = getResponsiblePID(for: pid),
           let app = runningApps.first(where: { $0.processIdentifier == responsiblePID }),
           app.bundleURL?.pathExtension == "app" {
            return app
        }

        var currentPID = pid
        var visited = Set<pid_t>()

        while currentPID > 1 && !visited.contains(currentPID) {
            visited.insert(currentPID)

            if let app = runningApps.first(where: { $0.processIdentifier == currentPID }),
               app.bundleURL?.pathExtension == "app" {
                return app
            }

            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, currentPID]

            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }

            let parentPID = info.kp_eproc.e_ppid
            if parentPID == currentPID { break }
            currentPID = parentPID
        }

        return nil
    }

    func start() {
        guard processListListenerBlock == nil else { return }

        logger.debug("Starting audio process monitor")

        processListListenerBlock = { [weak self] numberAddresses, addresses in
            Task { @MainActor [weak self] in
                self?.logger.debug("[DIAG] kAudioHardwarePropertyProcessObjectList fired")
                self?.refresh()
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            .system,
            &processListAddress,
            .main,
            processListListenerBlock!
        )

        if status != noErr {
            logger.error("Failed to add process list listener: \(status)")
        }

        refresh()
    }

    func stop() {
        logger.debug("Stopping audio process monitor")

        if let block = processListListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &processListAddress, .main, block)
            processListListenerBlock = nil
        }

        removeAllProcessListeners()
    }

    private func refresh() {
        do {
            let processIDs = try AudioObjectID.readProcessList()
            let runningApps = NSWorkspace.shared.runningApplications
            let myPID = ProcessInfo.processInfo.processIdentifier

            var apps: [AudioApp] = []

            for objectID in processIDs {
                guard objectID.readProcessIsRunning() else { continue }
                guard let pid = try? objectID.readProcessPID(), pid != myPID else { continue }

                let directApp = runningApps.first { $0.processIdentifier == pid }

                let isRealApp = directApp?.bundleURL?.pathExtension == "app"
                let resolvedApp = isRealApp ? directApp : findResponsibleApp(for: pid, in: runningApps)

                let name = resolvedApp?.localizedName
                    ?? objectID.readProcessBundleID()?.components(separatedBy: ".").last
                    ?? "Unknown"
                let icon = resolvedApp?.icon
                    ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
                    ?? NSImage()
                let bundleID = resolvedApp?.bundleIdentifier ?? objectID.readProcessBundleID()

                if isSystemDaemon(bundleID: bundleID, name: name) { continue }

                let app = AudioApp(
                    id: pid,
                    objectID: objectID,
                    name: name,
                    icon: icon,
                    bundleID: bundleID
                )
                apps.append(app)
            }

            updateProcessListeners(for: processIDs)

            activeApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            onAppsChanged?(activeApps)

        } catch {
            logger.error("Failed to refresh process list: \(error.localizedDescription)")
        }
    }

    private func updateProcessListeners(for processIDs: [AudioObjectID]) {
        let currentSet = Set(processIDs)

        let removed = monitoredProcesses.subtracting(currentSet)
        for objectID in removed {
            removeProcessListener(for: objectID)
        }

        let added = currentSet.subtracting(monitoredProcesses)
        for objectID in added {
            addProcessListener(for: objectID)
        }

        monitoredProcesses = currentSet
    }

    private func addProcessListener(for objectID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block)

        if status == noErr {
            processListenerBlocks[objectID] = block
        } else {
            logger.warning("Failed to add isRunning listener for \(objectID): \(status)")
        }
    }

    private func removeProcessListener(for objectID: AudioObjectID) {
        guard let block = processListenerBlocks.removeValue(forKey: objectID) else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
    }

    private func removeAllProcessListeners() {
        for objectID in monitoredProcesses {
            removeProcessListener(for: objectID)
        }
        monitoredProcesses.removeAll()
        processListenerBlocks.removeAll()
    }

    deinit {
    }
}
