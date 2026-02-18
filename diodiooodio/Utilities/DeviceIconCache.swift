import AppKit

/// DeviceIconCache 클래스를 정의합니다.
@MainActor
final class DeviceIconCache {
    static let shared = DeviceIconCache()

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private let maxSize: Int

    init(maxSize: Int = 30) {
        self.maxSize = maxSize
    }

    /// 아이콘 동작을 처리합니다.
    func icon(for uid: String, loader: () -> NSImage?) -> NSImage? {
        if let cached = cache[uid] {
            moveToFront(uid)
            return cached
        }
        guard let icon = loader() else { return nil }
        insert(uid, icon)
        return icon
    }

    /// clear 동작을 처리합니다.
    func clear() {
        cache.removeAll()
        order.removeAll()
    }

    private func moveToFront(_ uid: String) {
        order.removeAll { $0 == uid }
        order.insert(uid, at: 0)
    }

    private func insert(_ uid: String, _ icon: NSImage) {
        cache[uid] = icon
        order.insert(uid, at: 0)

        while order.count > maxSize {
            if let removed = order.popLast() {
                cache.removeValue(forKey: removed)
            }
        }
    }
}
