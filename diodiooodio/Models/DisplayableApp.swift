import AppKit
import UniformTypeIdentifiers

/// DisplayableApp 열거형를 정의합니다.
enum DisplayableApp: Identifiable {
    case active(AudioApp)
    case pinnedInactive(PinnedAppInfo)

    var id: String {
        switch self {
        case .active(let app):
            return app.persistenceIdentifier
        case .pinnedInactive(let info):
            return info.persistenceIdentifier
        }
    }

    /// 고정 비활성 여부를 나타냅니다.
    var isPinnedInactive: Bool {
        switch self {
        case .active:
            return false
        case .pinnedInactive:
            return true
        }
    }

    var isActive: Bool {
        switch self {
        case .active:
            return true
        case .pinnedInactive:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .active(let app):
            return app.name
        case .pinnedInactive(let info):
            return info.displayName
        }
    }

    var icon: NSImage {
        switch self {
        case .active(let app):
            return app.icon
        case .pinnedInactive(let info):
            return Self.loadIcon(for: info)
        }
    }

    /// 아이콘을(를) 불러옵니다
    private static func loadIcon(for info: PinnedAppInfo) -> NSImage {
        if let bundleID = info.bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
