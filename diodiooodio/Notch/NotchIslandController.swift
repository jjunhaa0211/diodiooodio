import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 상단 중앙에 표시되는 Dynamic Island 스타일 오버레이를 제어합니다.
@Observable
@MainActor
final class NotchIslandController {
    enum IslandModule: String, CaseIterable {
        case music
        case files
        case time
    }

    enum MoveDirection {
        case up
        case down
    }

    struct StashedPhoto: Identifiable, Hashable {
        let id: UUID
        let originalName: String
        let storedURL: URL
        let createdAt: Date
    }

    private enum Layout {
        static let collapsedSize = CGSize(width: 322, height: 52)
        static let collapsedCompactSize = CGSize(width: 198, height: 36)
        static let expandedSize = CGSize(width: 560, height: 380)
        static let topPadding: CGFloat = 0
        static let maxDroppedFiles = 8
        static let maxStashedPhotos = 24
        static let stashFileSeparator = "__"
    }

    private(set) var isPresented = false
    private(set) var isExpanded = false
    private(set) var droppedFiles: [URL] = []
    private(set) var stashedPhotos: [StashedPhoto] = []
    private(set) var isMusicModuleEnabled = true
    private(set) var isFilesModuleEnabled = true
    private(set) var isTimeModuleEnabled = false
    private(set) var isAutoControlEnabled = true
    private(set) var isExpansionPinned = false
    private(set) var isCompactNowPlayingVisible = true
    private(set) var isCompactPlaybackStatusVisible = true
    private(set) var language: AppLanguage = .english
    private(set) var moduleOrder: [IslandModule] = IslandModule.allCases

    private let musicService: AppleMusicNowPlayingService
    private let settingsManager: SettingsManager
    private let fileManager = FileManager.default
    private let photoStashDirectory: URL
    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isPointerHoveringIsland = false
    private var pendingHoverCollapseTask: Task<Void, Never>?

    init(musicService: AppleMusicNowPlayingService, settingsManager: SettingsManager) {
        self.musicService = musicService
        self.settingsManager = settingsManager
        self.photoStashDirectory = Self.makePhotoStashDirectory()
        applyModuleVisibility(from: settingsManager.appSettings)
        loadStashedPhotos()
    }

    /// 아일랜드 표시 상태를 토글합니다.
    func togglePresented() {
        isPresented ? hide() : show()
    }

    /// 아일랜드 확장 상태를 토글합니다.
    func toggleExpanded() {
        guard isPresented else {
            show()
            return
        }
        guard !isExpansionPinned else {
            isExpanded = true
            updatePanelFrame(animated: true)
            return
        }
        isExpanded.toggle()
        updatePanelFrame(animated: true)
    }

    /// 아일랜드를 표시합니다.
    func show() {
        guard preferredNotchScreen() != nil else {
            isPresented = false
            return
        }
        applyModuleVisibility(from: settingsManager.appSettings)
        if panel == nil {
            panel = makePanel()
        }
        isPointerHoveringIsland = false
        isExpanded = isExpansionPinned
        musicService.start()
        isPresented = true
        startGlobalMouseMonitoringIfNeeded()
        updatePanelFrame(animated: false)
        panel?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: false)
    }

    /// 아일랜드를 숨깁니다.
    func hide() {
        pendingHoverCollapseTask?.cancel()
        pendingHoverCollapseTask = nil
        panel?.orderOut(nil)
        isPresented = false
        stopGlobalMouseMonitoring()
    }

    /// 아일랜드를 축소 상태로 되돌립니다.
    func collapse() {
        guard !isExpansionPinned else { return }
        guard isExpanded else { return }
        isExpanded = false
        updatePanelFrame(animated: true)
    }

    /// Hover 상태에 따라 자동 확장/축소를 제어합니다.
    func handleIslandHoverChanged(_ isHovering: Bool) {
        guard isAutoControlEnabled else { return }
        guard isPresented else { return }
        guard !isExpansionPinned else { return }
        isPointerHoveringIsland = isHovering

        if isHovering {
            pendingHoverCollapseTask?.cancel()
            pendingHoverCollapseTask = nil
            guard !isExpanded else { return }
            isExpanded = true
            updatePanelFrame(animated: true)
            return
        }

        scheduleHoverDrivenCollapse()
    }

    /// 드롭된 파일 목록을 병합/중복제거해 저장합니다.
    func addDroppedFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        var merged = droppedFiles
        for rawURL in urls where rawURL.isFileURL {
            let url = rawURL.standardizedFileURL
            let exists = FileManager.default.fileExists(atPath: url.path)
            guard exists else { continue }
            let alreadyContains = merged.contains { $0.standardizedFileURL.path == url.path }
            if !alreadyContains {
                merged.append(url)
            }
        }

        droppedFiles = Array(merged.prefix(Layout.maxDroppedFiles))
    }

    /// 저장된 드롭 파일 목록을 모두 비웁니다.
    func clearDroppedFiles() {
        droppedFiles.removeAll()
    }

    /// 기본 앱으로 파일을 엽니다.
    func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// 드롭 파일을 AirDrop 공유 서비스로 전송합니다.
    func sendDroppedFilesViaAirDrop() {
        guard !droppedFiles.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: droppedFiles)
    }

    /// 드롭된 파일 중 이미지 파일을 임시 보관함으로 저장합니다.
    func addPhotosToStash(from urls: [URL]) {
        guard !urls.isEmpty else { return }

        var appended: [StashedPhoto] = []

        for rawURL in urls where rawURL.isFileURL {
            let sourceURL = rawURL.standardizedFileURL
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            guard isImageFile(sourceURL) else { continue }

            let destinationURL = makeDestinationURL(for: sourceURL)
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                let photo = StashedPhoto(
                    id: UUID(),
                    originalName: sourceURL.lastPathComponent,
                    storedURL: destinationURL,
                    createdAt: Date()
                )
                appended.append(photo)
            } catch {
                continue
            }
        }

        guard !appended.isEmpty else { return }
        stashedPhotos = (appended + stashedPhotos)
        trimStashedPhotosIfNeeded()
    }

    /// 저장된 사진을 클립보드에 복사합니다.
    @discardableResult
    func copyStashedPhotoToPasteboard(_ photo: StashedPhoto) -> Bool {
        guard fileManager.fileExists(atPath: photo.storedURL.path) else { return false }
        guard let image = NSImage(contentsOf: photo.storedURL) else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if pasteboard.writeObjects([image]) {
            return true
        }

        guard let tiffData = image.tiffRepresentation else { return false }
        let item = NSPasteboardItem()
        item.setData(tiffData, forType: .tiff)
        if let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            item.setData(pngData, forType: .png)
        }
        return pasteboard.writeObjects([item])
    }

    /// 가장 최근 보관한 사진을 클립보드에 복사합니다.
    @discardableResult
    func copyLatestStashedPhotoToPasteboard() -> Bool {
        guard let latest = stashedPhotos.first else { return false }
        return copyStashedPhotoToPasteboard(latest)
    }

    /// 보관된 사진을 Finder에서 선택합니다.
    func revealStashedPhotoInFinder(_ photo: StashedPhoto) {
        guard fileManager.fileExists(atPath: photo.storedURL.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([photo.storedURL])
    }

    /// 특정 보관 사진을 삭제합니다.
    func removeStashedPhoto(_ photo: StashedPhoto) {
        stashedPhotos.removeAll { $0.id == photo.id }
        try? fileManager.removeItem(at: photo.storedURL)
    }

    /// 보관 사진 전체를 삭제합니다.
    func clearPhotoStash() {
        for photo in stashedPhotos {
            try? fileManager.removeItem(at: photo.storedURL)
        }
        stashedPhotos.removeAll()
    }

    /// 모듈 표시 여부를 반환합니다.
    func isModuleEnabled(_ module: IslandModule) -> Bool {
        switch module {
        case .music:
            return isMusicModuleEnabled
        case .files:
            return isFilesModuleEnabled
        case .time:
            return isTimeModuleEnabled
        }
    }

    /// 모듈 표시 여부를 업데이트하고 설정에 저장합니다.
    func setModuleEnabled(_ module: IslandModule, isEnabled: Bool) {
        switch module {
        case .music:
            isMusicModuleEnabled = isEnabled
        case .files:
            isFilesModuleEnabled = isEnabled
        case .time:
            isTimeModuleEnabled = isEnabled
        }
        persistModuleVisibility()
    }

    /// 자동 제어 설정을 업데이트합니다.
    func setAutoControlEnabled(_ isEnabled: Bool) {
        isAutoControlEnabled = isEnabled
        persistModuleVisibility()
        if isEnabled, isPresented {
            startGlobalMouseMonitoringIfNeeded()
        } else if !isEnabled {
            stopGlobalMouseMonitoring()
        }
    }

    /// 설정 파일의 모듈 표시 여부를 다시 로드합니다.
    func reloadModuleVisibility() {
        applyModuleVisibility(from: settingsManager.appSettings)
    }

    /// 확장 화면 고정 여부를 업데이트합니다.
    func setExpansionPinned(_ isEnabled: Bool) {
        isExpansionPinned = isEnabled
        if isPresented {
            if isEnabled {
                isExpanded = true
            }
            updatePanelFrame(animated: true)
        }
        persistModuleVisibility()
    }

    /// 작은 다이나믹 바에서 현재 곡/가사 텍스트 표시 여부를 업데이트합니다.
    func setCompactNowPlayingVisible(_ isEnabled: Bool) {
        isCompactNowPlayingVisible = isEnabled
        updateCollapsedPanelFrameIfNeeded()
        persistModuleVisibility()
    }

    /// 작은 다이나믹 바에서 재생 상태(보라색 막대) 표시 여부를 업데이트합니다.
    func setCompactPlaybackStatusVisible(_ isEnabled: Bool) {
        isCompactPlaybackStatusVisible = isEnabled
        updateCollapsedPanelFrameIfNeeded()
        persistModuleVisibility()
    }

    /// 모듈의 이동 가능 여부를 반환합니다.
    func canMoveModule(_ module: IslandModule, direction: MoveDirection) -> Bool {
        guard let index = moduleOrder.firstIndex(of: module) else { return false }
        switch direction {
        case .up:
            return index > moduleOrder.startIndex
        case .down:
            return index < moduleOrder.index(before: moduleOrder.endIndex)
        }
    }

    /// 모듈 순서를 한 칸 이동합니다.
    func moveModule(_ module: IslandModule, direction: MoveDirection) {
        guard let index = moduleOrder.firstIndex(of: module) else { return }

        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = index - 1
        case .down:
            targetIndex = index + 1
        }
        guard moduleOrder.indices.contains(targetIndex) else { return }

        moduleOrder.swapAt(index, targetIndex)
        persistModuleVisibility()
    }

    /// 모듈 순서를 드래그 방식으로 재정렬합니다.
    func moveModules(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else { return }
        moduleOrder.move(fromOffsets: source, toOffset: destination)
        persistModuleVisibility()
    }

    /// 현재 활성화된 모듈 목록입니다.
    var enabledModules: [IslandModule] {
        moduleOrder.filter { isModuleEnabled($0) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.isMovable = false

        let rootView = NotchIslandView(controller: self, musicService: musicService)
        panel.contentView = NSHostingView(rootView: rootView)
        return panel
    }

    private func updatePanelFrame(animated: Bool) {
        guard let panel else { return }
        guard let screen = preferredNotchScreen() else { return }

        let collapsedSize = usesCompactCollapsedSize ? Layout.collapsedCompactSize : Layout.collapsedSize
        let targetSize = isExpanded ? Layout.expandedSize : collapsedSize

        let display = screen.frame
        let origin = CGPoint(
            x: display.midX - targetSize.width / 2,
            y: display.maxY - targetSize.height - Layout.topPadding
        )
        let frame = CGRect(origin: origin, size: targetSize)

        if animated {
            panel.animator().setFrame(frame, display: true)
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func applyModuleVisibility(from settings: AppSettings) {
        isMusicModuleEnabled = settings.notchShowMusic
        isFilesModuleEnabled = settings.notchShowFiles
        isTimeModuleEnabled = settings.notchShowTime
        isAutoControlEnabled = settings.notchAutoControl
        isExpansionPinned = settings.notchPinExpanded
        isCompactNowPlayingVisible = settings.notchShowCompactNowPlaying
        isCompactPlaybackStatusVisible = settings.notchShowCompactPlaybackStatus
        language = settings.language
        moduleOrder = Self.resolvedModuleOrder(from: settings.notchModuleOrder)
        updateCollapsedPanelFrameIfNeeded()
    }

    private func persistModuleVisibility() {
        var appSettings = settingsManager.appSettings
        appSettings.notchShowMusic = isMusicModuleEnabled
        appSettings.notchShowFiles = isFilesModuleEnabled
        appSettings.notchShowTime = isTimeModuleEnabled
        appSettings.notchAutoControl = isAutoControlEnabled
        appSettings.notchPinExpanded = isExpansionPinned
        appSettings.notchShowCompactNowPlaying = isCompactNowPlayingVisible
        appSettings.notchShowCompactPlaybackStatus = isCompactPlaybackStatusVisible
        appSettings.notchModuleOrder = moduleOrder.map(\.rawValue)
        settingsManager.updateAppSettings(appSettings)
    }

    private var usesCompactCollapsedSize: Bool {
        !isCompactNowPlayingVisible && !isCompactPlaybackStatusVisible
    }

    private func updateCollapsedPanelFrameIfNeeded() {
        guard isPresented, !isExpanded else { return }
        updatePanelFrame(animated: true)
    }

    private func startGlobalMouseMonitoringIfNeeded() {
        guard isAutoControlEnabled else { return }
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }

        let monitorEventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: monitorEventMask
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.collapseIfPointerMovedBelowIsland()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: monitorEventMask
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.collapseIfPointerMovedBelowIsland()
            }
            return event
        }
    }

    private func stopGlobalMouseMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func collapseIfPointerMovedBelowIsland() {
        guard isAutoControlEnabled else { return }
        guard !isExpansionPinned else { return }
        guard isPresented, isExpanded else { return }
        guard let panel else { return }

        let location = NSEvent.mouseLocation
        if !shouldAutoCollapse(for: location, panelFrame: panel.frame) {
            return
        }
        collapse()
    }

    private func scheduleHoverDrivenCollapse() {
        pendingHoverCollapseTask?.cancel()
        pendingHoverCollapseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            guard self.isAutoControlEnabled else { return }
            guard self.isPresented, self.isExpanded else { return }
            guard !self.isExpansionPinned else { return }
            guard !self.isPointerHoveringIsland else { return }
            guard let panel = self.panel else { return }

            let location = NSEvent.mouseLocation
            guard self.shouldAutoCollapse(for: location, panelFrame: panel.frame) else { return }
            self.collapse()
        }
    }

    private func shouldAutoCollapse(for location: CGPoint, panelFrame: CGRect) -> Bool {
        let escapedHorizontally = location.x <= panelFrame.minX - 2 || location.x >= panelFrame.maxX + 2
        let escapedBelow = location.y <= panelFrame.minY - 2
        return escapedHorizontally || escapedBelow
    }

    private func preferredNotchScreen() -> NSScreen? {
        let builtInDisplays = NSScreen.screens.filter(Self.isBuiltInDisplay)
        guard !builtInDisplays.isEmpty else { return nil }
        if let notched = builtInDisplays.first(where: Self.isNotchDisplay) {
            return notched
        }
        return builtInDisplays.first
    }

    private static func isBuiltInDisplay(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    private static func isNotchDisplay(_ screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            let left = screen.auxiliaryTopLeftArea ?? .zero
            let right = screen.auxiliaryTopRightArea ?? .zero
            return !left.isEmpty && !right.isEmpty
        }
        return false
    }

    private static func resolvedModuleOrder(from rawOrder: [String]) -> [IslandModule] {
        var resolved: [IslandModule] = []
        for raw in rawOrder {
            guard let module = IslandModule(rawValue: raw) else { continue }
            if !resolved.contains(module) {
                resolved.append(module)
            }
        }
        for module in IslandModule.allCases where !resolved.contains(module) {
            resolved.append(module)
        }
        return resolved
    }

    private static func makePhotoStashDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diodiooodio-photo-stash", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return FileManager.default.temporaryDirectory
        }

        return directory
    }

    private func loadStashedPhotos() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: photoStashDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            stashedPhotos = []
            return
        }

        let photos = urls.compactMap { url -> StashedPhoto? in
            guard isImageFile(url) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let createdAt = values?.contentModificationDate ?? .distantPast
            return StashedPhoto(
                id: UUID(),
                originalName: extractOriginalName(from: url),
                storedURL: url,
                createdAt: createdAt
            )
        }

        stashedPhotos = photos.sorted { $0.createdAt > $1.createdAt }
        trimStashedPhotosIfNeeded()
    }

    private func trimStashedPhotosIfNeeded() {
        guard stashedPhotos.count > Layout.maxStashedPhotos else { return }

        let exceeded = stashedPhotos.suffix(from: Layout.maxStashedPhotos)
        for photo in exceeded {
            try? fileManager.removeItem(at: photo.storedURL)
        }
        stashedPhotos = Array(stashedPhotos.prefix(Layout.maxStashedPhotos))
    }

    private func makeDestinationURL(for sourceURL: URL) -> URL {
        let prefix = UUID().uuidString
        let fileName = "\(prefix)\(Layout.stashFileSeparator)\(sourceURL.lastPathComponent)"
        return photoStashDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func extractOriginalName(from storedURL: URL) -> String {
        let name = storedURL.lastPathComponent
        guard let range = name.range(of: Layout.stashFileSeparator) else { return name }
        return String(name[range.upperBound...])
    }

    private func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .image)
    }
}
