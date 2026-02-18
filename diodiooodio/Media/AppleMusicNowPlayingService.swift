import Foundation
import AppKit
import MusicKit
import OSLog

/// Apple Music 미디어 권한을 확인하고 현재 재생 메타데이터를 조회합니다.
@Observable
@MainActor
final class AppleMusicNowPlayingService {
    struct SyncedLyricLine: Hashable {
        let time: TimeInterval
        let text: String
    }

    enum PlaybackState: String {
        case playing
        case paused
        case stopped
        case waiting
        case unknown
    }

    enum AuthorizationState: String {
        case notDetermined
        case denied
        case restricted
        case authorized
        case unknown

        var description: String {
            switch self {
            case .notDetermined: return "권한 확인 필요"
            case .denied: return "권한 거부됨"
            case .restricted: return "권한 제한됨"
            case .authorized: return "권한 허용됨"
            case .unknown: return "권한 상태 알 수 없음"
            }
        }
    }

    struct NowPlayingSnapshot {
        var state: PlaybackState = .waiting
        var title: String = "재생 중인 곡 없음"
        var artist: String = "Apple Music"
        var album: String = ""
        var duration: Double = 0
        var position: Double = 0
        var artworkURL: URL?
        var artworkImage: NSImage?
        var lyricsSnippet: String = ""
        var syncedLyrics: [SyncedLyricLine] = []
        var plainLyrics: [String] = []

        var isPlaying: Bool { state == .playing }
    }

    private enum Polling {
        static let interval: TimeInterval = 1.0
    }

    private enum LyricsLookup {
        static let retryWindow: TimeInterval = 10.0
        static let requestTimeout: TimeInterval = 5.0
        static let fallbackTimeout: TimeInterval = 4.0
    }

    private enum AutoRecovery {
        static let pauseDelay: Duration = .milliseconds(220)
        static let retryDelay: Duration = .milliseconds(320)
        static let retryAttempts = 6
    }

    private enum ArtworkLookup {
        static let retryWindow: TimeInterval = 4.0
        static let requestTimeout: TimeInterval = 4.0
    }

    private enum MusicPlayerNotification {
        static let music = Notification.Name("com.apple.Music.playerInfo")
        static let iTunesLegacy = Notification.Name("com.apple.iTunes.playerInfo")
    }

    private struct ITunesSearchResponse: Decodable {
        struct Item: Decodable {
            let artworkUrl100: String?
        }

        let results: [Item]
    }

    private struct LrcLibResponse: Decodable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private struct LyricsOvhResponse: Decodable {
        let lyrics: String?
    }

    private struct CachedLyrics {
        let snippet: String
        let synced: [SyncedLyricLine]
        let plain: [String]
    }

    private struct CachedArtwork {
        let url: URL?
        let image: NSImage?
    }

    private let lyricsLogger = Logger(subsystem: "com.diodiooodio.app", category: "lyrics")

    /// 타이머는 MainActor에서만 접근하지만 deinit 정리를 위해 비격리 접근을 허용합니다.
    nonisolated(unsafe) private var timer: Timer?
    private let player = ApplicationMusicPlayer.shared
    nonisolated(unsafe) private var distributedObserverTokens: [NSObjectProtocol] = []
    private var lyricsLookupTask: Task<Void, Never>?
    private var lyricsLookupInFlightKey: String?
    private var lyricsCache: [String: CachedLyrics] = [:]
    private var artworkCache: [String: CachedArtwork] = [:]
    private var currentArtworkTrackKey: String?
    private var hasExternalPlayerSnapshot = false
    private var lastExternalUpdateDate: Date?
    private var lastPlaybackTickDate: Date?
    private var lastArtworkLookupKey: String?
    private var lastArtworkLookupDate: Date?
    private var lastLyricsLookupKey: String?
    private var lastLyricsLookupDate: Date?
    private var isAutoRecoveryInProgress = false

    private(set) var snapshot = NowPlayingSnapshot()
    private(set) var authorizationState: AuthorizationState = .notDetermined
    private(set) var lastErrorMessage: String?

    var isPolling: Bool { timer != nil }
    var isAuthorized: Bool { authorizationState == .authorized }

    deinit {
        timer?.invalidate()
        removeDistributedPlayerObservers()
    }

    /// 미디어 상태 폴링을 시작합니다.
    func start() {
        guard timer == nil else { return }
        installDistributedPlayerObservers()
        updateAuthorizationState()
        lastPlaybackTickDate = Date()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: Polling.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// 현재곡 폴링을 중지합니다.
    func stop() {
        timer?.invalidate()
        timer = nil
        lyricsLookupTask?.cancel()
        lyricsLookupTask = nil
        lyricsLookupInFlightKey = nil
        removeDistributedPlayerObservers()
    }

    /// Apple Music 재생 메타데이터를 즉시 갱신합니다.
    func refresh() {
        Task { [weak self] in
            await self?.refreshAsync()
        }
    }

    /// 실제 데이터 갱신 작업을 수행합니다.
    private func refreshAsync() async {
        updateAuthorizationState()

        // 1) 외부 Music 앱 상태/내부 플레이어 상태에서 라이브 스냅샷을 우선 조회합니다.
        if await applyLiveSnapshot() {
            return
        }

        // 2) 외부 스냅샷이 이미 있다면 재생 위치를 틱으로 전진시킵니다.
        if hasExternalPlayerSnapshot {
            advanceExternalPlaybackPosition()
            lastErrorMessage = nil
            return
        }

        // 3) Apple Music 실행 중이면 강제 멈춤 복구 후 라이브 스냅샷을 재시도합니다.
        let shouldRunAutoRecovery = isMusicAppRunning
        if shouldRunAutoRecovery {
            _ = await attemptPauseAndRecoverIfMusicRunning()
            if await applyLiveSnapshotWithRetries(attempts: AutoRecovery.retryAttempts) {
                return
            }
        }

        // 4) 미디어 권한이 있으면 최근 재생 곡을 백업 데이터로 표시합니다.
        if isAuthorized {
            let appliedRecent = await applyRecentlyPlayedSnapshot()
            if appliedRecent {
                return
            }
        }

        snapshot = NowPlayingSnapshot()
        if shouldRunAutoRecovery {
            lastErrorMessage = "현재 재생 정보를 받지 못했습니다. Apple Music 실행 상태에서 자동 멈춤 복구와 재조회까지 시도했지만 아직 데이터를 받지 못했습니다."
        } else {
            lastErrorMessage = "현재 재생 정보를 받지 못했습니다. Apple Music에서 재생/일시정지를 한 번 눌러 알림을 발생시킨 뒤 다시 확인하세요."
        }
    }

    /// 외부/내부 플레이어에서 라이브 스냅샷을 조회해 반영합니다.
    private func applyLiveSnapshot() async -> Bool {
        let appliedExternal = await applyExternalSnapshotFromAppleScript()
        if appliedExternal {
            hasExternalPlayerSnapshot = true
            lastErrorMessage = nil
            return true
        }

        if applyCurrentPlayerSnapshot() {
            hasExternalPlayerSnapshot = false
            lastErrorMessage = nil
            return true
        }

        return false
    }

    private func applyLiveSnapshotWithRetries(attempts: Int) async -> Bool {
        guard attempts > 0 else { return false }
        for index in 0..<attempts {
            if await applyLiveSnapshot() {
                return true
            }
            if index < attempts - 1 {
                try? await Task.sleep(for: AutoRecovery.retryDelay)
            }
        }
        return false
    }

    /// 미디어 라이브러리 접근 권한을 요청합니다.
    func requestMediaPermission() {
        Task { [weak self] in
            guard let self else { return }
            _ = await MusicAuthorization.request()
            await self.refreshAsync()
        }
    }

    /// Apple Music 앱을 엽니다.
    func openMusicApp() {
        if let url = URL(string: "music://") {
            NSWorkspace.shared.open(url)
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// 재생/일시정지를 토글합니다.
    func togglePlayPause() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            lastErrorMessage = nil
            let command = snapshot.isPlaying ? "pause" : "play"
            if executeMusicAppleScript("tell application \"Music\" to \(command)") {
                snapshot.state = snapshot.isPlaying ? .paused : .playing
                await refreshAfterTransportControl()
                return
            }

            do {
                if snapshot.isPlaying {
                    player.pause()
                } else {
                    try await player.play()
                }
                await refreshAfterTransportControl()
            } catch {
                lastErrorMessage = transportControlErrorMessage(defaultText: "재생/일시정지 제어에 실패했습니다.")
            }
        }
    }

    /// 다음 곡으로 이동합니다.
    func skipToNext() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            lastErrorMessage = nil
            if executeMusicAppleScript("tell application \"Music\" to next track") {
                await refreshAfterTransportControl()
                return
            }
            do {
                try await player.skipToNextEntry()
                await refreshAfterTransportControl()
            } catch {
                lastErrorMessage = transportControlErrorMessage(defaultText: "다음 곡 이동에 실패했습니다.")
            }
        }
    }

    /// 이전 곡으로 이동합니다.
    func skipToPrevious() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            lastErrorMessage = nil
            if executeMusicAppleScript("tell application \"Music\" to previous track") {
                await refreshAfterTransportControl()
                return
            }
            do {
                try await player.skipToPreviousEntry()
                await refreshAfterTransportControl()
            } catch {
                lastErrorMessage = transportControlErrorMessage(defaultText: "이전 곡 이동에 실패했습니다.")
            }
        }
    }

    /// 재생 위치를 지정한 시간(초)으로 이동합니다.
    func seek(to seconds: Double) {
        let safeSeconds = seconds.isFinite ? seconds : 0
        let safeDuration = snapshot.duration.isFinite ? max(snapshot.duration, 0) : 0
        let upperBound = safeDuration > 0 ? safeDuration : safeSeconds
        let clamped = max(0, min(safeSeconds, upperBound))
        let secondsText = String(format: "%.3f", clamped)

        Task { @MainActor [weak self] in
            guard let self else { return }
            lastErrorMessage = nil
            if executeMusicAppleScript("tell application \"Music\" to set player position to \(secondsText)") {
                snapshot.position = clamped
                await refreshAfterTransportControl()
                return
            }

            player.playbackTime = clamped
            snapshot.position = clamped
            await refreshAfterTransportControl()
            if abs(snapshot.position - clamped) > 1.5 {
                lastErrorMessage = transportControlErrorMessage(defaultText: "재생 위치 이동이 반영되지 않았습니다.")
            }
        }
    }

    /// 미디어 및 Apple Music 권한 설정 화면을 엽니다.
    func openMediaPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 자동화(Apple Events) 권한 설정 화면을 엽니다.
    func openAutomationPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func refreshAfterTransportControl() async {
        if await applyLiveSnapshotWithRetries(attempts: 3) {
            return
        }
        await refreshAsync()
    }

    private func transportControlErrorMessage(defaultText: String) -> String {
        if !isAuthorized {
            return "\(defaultText) 미디어 권한이 필요합니다. 'Request Media Access'를 먼저 눌러 주세요."
        }
        return "\(defaultText) 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서 이 앱의 Music 제어를 허용해 주세요."
    }

    /// 현재 권한 상태를 조회해 저장합니다.
    private func updateAuthorizationState() {
        let status = MusicAuthorization.currentStatus
        switch status {
        case .notDetermined:
            authorizationState = .notDetermined
        case .denied:
            authorizationState = .denied
        case .restricted:
            authorizationState = .restricted
        case .authorized:
            authorizationState = .authorized
        default:
            authorizationState = .unknown
        }
    }

    /// Music 앱 분산 알림을 구독해 실시간 재생 메타데이터를 받습니다.
    private func installDistributedPlayerObservers() {
        guard distributedObserverTokens.isEmpty else { return }

        let center = DistributedNotificationCenter.default()
        let names: [Notification.Name] = [
            MusicPlayerNotification.music,
            MusicPlayerNotification.iTunesLegacy,
        ]

        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.handleDistributedPlayerInfo(notification.userInfo)
            }
            distributedObserverTokens.append(token)
        }
    }

    /// 분산 알림 옵저버를 해제합니다.
    nonisolated private func removeDistributedPlayerObservers() {
        guard !distributedObserverTokens.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for token in distributedObserverTokens {
            center.removeObserver(token)
        }
        distributedObserverTokens.removeAll()
    }

    /// Music 앱에서 전달된 플레이어 정보를 스냅샷으로 반영합니다.
    private func handleDistributedPlayerInfo(_ userInfo: [AnyHashable: Any]?) {
        guard let userInfo else { return }

        let stateValue = (userInfo["Player State"] as? String)?.lowercased() ?? ""
        let title = (userInfo["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "재생 중인 곡 없음"
        let artist = (userInfo["Artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Apple Music"
        let album = (userInfo["Album"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let totalTimeMS = doubleValue(from: userInfo["Total Time"]) ?? 0
        let duration = max(totalTimeMS / 1000.0, 0)
        let position = max(doubleValue(from: userInfo["Player Position"]) ?? 0, 0)
        let lyrics = (userInfo["Lyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lyricsLogger.info("playerInfo lyrics embedded=\((!lyrics.isEmpty), privacy: .public) title=\(title, privacy: .public) artist=\(artist, privacy: .public)")

        let artworkString = (userInfo["Artwork URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artworkURL = URL(string: artworkString)
        let artworkImage = extractArtworkImage(from: userInfo)

        applySnapshot(
            state: parsePlayerStateString(stateValue),
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            artworkURL: artworkURL,
            artworkImage: artworkImage,
            lyrics: lyrics
        )
        scheduleLyricsLookupIfNeeded(
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )

        hasExternalPlayerSnapshot = snapshot.state != .unknown || title != "재생 중인 곡 없음"
        lastExternalUpdateDate = Date()
        lastPlaybackTickDate = Date()
        lastErrorMessage = nil

        Task { [weak self] in
            await self?.lookupArtworkIfNeeded(title: title, artist: artist)
        }
    }

    /// 현재 ApplicationMusicPlayer 세션에서 메타데이터를 반영합니다.
    private func applyCurrentPlayerSnapshot() -> Bool {
        guard let entry = player.queue.currentEntry else {
            return false
        }

        var title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "재생 중인 곡 없음"
        var artist = entry.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Apple Music"
        var album = ""
        var duration: Double = 0
        var artworkURL: URL?

        if let item = entry.item {
            switch item {
            case .song(let song):
                title = song.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? title
                artist = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? artist
                album = song.albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                duration = max(song.duration ?? 0, 0)
                artworkURL = song.artwork?.url(width: 320, height: 320)

            case .musicVideo(let video):
                title = video.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? title
                artist = video.artistName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? artist
                album = video.albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                duration = max(video.duration ?? 0, 0)
                artworkURL = video.artwork?.url(width: 320, height: 320)
            }
        }

        applySnapshot(
            state: parsePlaybackState(player.state.playbackStatus),
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: max(player.playbackTime, 0),
            artworkURL: artworkURL,
            artworkImage: nil,
            lyrics: ""
        )
        scheduleLyricsLookupIfNeeded(
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
        Task { [weak self] in
            await self?.lookupArtworkIfNeeded(title: title, artist: artist)
        }
        lastPlaybackTickDate = Date()
        return true
    }

    /// 외부 Music 앱 상태를 AppleScript로 조회해 반영합니다.
    private func applyExternalSnapshotFromAppleScript() async -> Bool {
        let separatorScalar = UnicodeScalar(31)!
        let separator = String(separatorScalar)
        let script = """
        tell application "Music"
            if not running then return ""
            set sep to (ASCII character 31)
            set stateText to (player state as text)
            set trackName to ""
            set trackArtist to ""
            set trackAlbum to ""
            set trackLyrics to ""
            set trackDurationMs to 0
            set trackPositionMs to 0

            if current track is not missing value then
                set trackName to (name of current track as text)
                set trackArtist to (artist of current track as text)
                set trackAlbum to (album of current track as text)
                set trackDurationMs to (round ((duration of current track) * 1000))
                try
                    set trackLyrics to (lyrics of current track as text)
                on error
                    set trackLyrics to ""
                end try
            end if

            if stateText is not "stopped" then
                set trackPositionMs to (round ((player position) * 1000))
            end if

            return stateText & sep & trackName & sep & trackArtist & sep & trackAlbum & sep & (trackDurationMs as text) & sep & (trackPositionMs as text) & sep & trackLyrics
        end tell
        """

        guard let raw = executeMusicAppleScriptWithResult(script), !raw.isEmpty else {
            return false
        }

        let fields = raw.components(separatedBy: separator)
        guard fields.count >= 7 else {
            return false
        }

        let state = parsePlayerStateString(fields[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "재생 중인 곡 없음"
        let artist = fields[2].trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Apple Music"
        let album = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = max((Double(fields[4]) ?? 0) / 1000.0, 0)
        let position = max((Double(fields[5]) ?? 0) / 1000.0, 0)
        let lyrics = fields[6].trimmingCharacters(in: .whitespacesAndNewlines)

        applySnapshot(
            state: state,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            artworkURL: nil,
            artworkImage: nil,
            lyrics: lyrics
        )
        scheduleLyricsLookupIfNeeded(
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )

        lastExternalUpdateDate = Date()
        lastPlaybackTickDate = Date()
        await lookupArtworkIfNeeded(title: title, artist: artist)
        return true
    }

    /// 현재 재생 세션이 없을 때 최근 재생 곡 1개를 표시합니다.
    private func applyRecentlyPlayedSnapshot() async -> Bool {
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = 1

        do {
            let response = try await request.response()
            guard let song = response.items.first else {
                return false
            }

        applySnapshot(
            state: .stopped,
            title: song.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "재생 중인 곡 없음",
            artist: song.artistName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Apple Music",
                album: song.albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                duration: max(song.duration ?? 0, 0),
                position: 0,
                artworkURL: song.artwork?.url(width: 320, height: 320),
                artworkImage: nil,
            lyrics: ""
        )
            let currentTitle = snapshot.title
            let currentArtist = snapshot.artist
            let currentAlbum = snapshot.album
            let currentDuration = snapshot.duration

            scheduleLyricsLookupIfNeeded(
                title: currentTitle,
                artist: currentArtist,
                album: currentAlbum,
                duration: currentDuration
            )
            Task { [weak self] in
                await self?.lookupArtworkIfNeeded(title: currentTitle, artist: currentArtist)
            }

            lastPlaybackTickDate = Date()
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = "Apple Music 최근 재생 데이터를 가져오지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    /// 외부 스냅샷만 있을 때 재생 위치를 시간 경과에 따라 전진시킵니다.
    private func advanceExternalPlaybackPosition() {
        guard snapshot.isPlaying else {
            lastPlaybackTickDate = Date()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastPlaybackTickDate ?? now)
        lastPlaybackTickDate = now
        guard elapsed.isFinite, elapsed > 0 else { return }

        let safeDuration = snapshot.duration.isFinite ? max(snapshot.duration, 0) : 0
        let safePosition = snapshot.position.isFinite ? max(snapshot.position, 0) : 0

        if safeDuration > 0 {
            snapshot.position = min(max(safePosition + elapsed, 0), safeDuration)
        } else {
            snapshot.position = max(safePosition + elapsed, 0)
        }
    }

    private func applySnapshot(
        state: PlaybackState,
        title: String,
        artist: String,
        album: String,
        duration: Double,
        position: Double,
        artworkURL: URL?,
        artworkImage: NSImage?,
        lyrics: String
    ) {
        let safeDuration = sanitizedDuration(duration)
        let safePosition = sanitizedPosition(position, duration: safeDuration)
        let previousTrackKey = trackLookupKey(title: snapshot.title, artist: snapshot.artist, duration: snapshot.duration)
        let nextTrackKey = trackLookupKey(title: title, artist: artist, duration: safeDuration)
        let didTrackChange = previousTrackKey != nextTrackKey

        snapshot.state = state
        snapshot.title = title
        snapshot.artist = artist
        snapshot.album = album
        snapshot.duration = safeDuration
        snapshot.position = safePosition

        if title == "재생 중인 곡 없음" {
            snapshot.artworkImage = nil
            snapshot.artworkURL = nil
            currentArtworkTrackKey = nil
            lastArtworkLookupKey = nil
            lastArtworkLookupDate = nil
        } else if let artworkImage {
            snapshot.artworkImage = artworkImage
            if didTrackChange {
                snapshot.artworkURL = nil
            }
            currentArtworkTrackKey = nextTrackKey
            cacheArtwork(for: nextTrackKey, image: artworkImage, url: artworkURL ?? snapshot.artworkURL)
        } else if let artworkURL {
            if didTrackChange {
                snapshot.artworkImage = nil
            }
            snapshot.artworkURL = artworkURL
            currentArtworkTrackKey = nextTrackKey
            cacheArtwork(for: nextTrackKey, image: nil, url: artworkURL)
        } else if didTrackChange {
            if applyCachedArtworkIfAvailable(for: nextTrackKey) {
                currentArtworkTrackKey = nextTrackKey
            } else {
                // 새 트랙은 기존 아트워크를 비우고 재조회합니다.
                snapshot.artworkImage = nil
                snapshot.artworkURL = nil
                currentArtworkTrackKey = nil
            }
        }

        if !lyrics.isEmpty {
            snapshot.lyricsSnippet = lyrics
            let synced = parseLRCSyncedLyrics(lyrics)
            if !synced.isEmpty {
                snapshot.syncedLyrics = synced
                snapshot.plainLyrics = synced.map(\.text)
                cacheLyrics(for: nextTrackKey, synced: synced, plain: snapshot.plainLyrics)
            } else {
                let plain = parsePlainLyrics(lyrics)
                snapshot.syncedLyrics = []
                snapshot.plainLyrics = plain
                cacheLyrics(for: nextTrackKey, synced: [], plain: plain)
            }
        } else if didTrackChange {
            if applyCachedLyricsIfAvailable(for: nextTrackKey) {
                return
            }
            snapshot.lyricsSnippet = fallbackLyricsSnippet()
            snapshot.syncedLyrics = []
            snapshot.plainLyrics = parsePlainLyrics(snapshot.lyricsSnippet)
        }
    }

    /// MusicKit 재생 상태를 내부 상태 값으로 변환합니다.
    private func parsePlaybackState(_ value: MusicPlayer.PlaybackStatus) -> PlaybackState {
        switch value {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .stopped:
            return .stopped
        case .interrupted, .seekingForward, .seekingBackward:
            return .waiting
        @unknown default:
            return .unknown
        }
    }

    /// 분산 알림 문자열 상태를 내부 상태로 변환합니다.
    private func parsePlayerStateString(_ value: String) -> PlaybackState {
        switch value {
        case "playing":
            return .playing
        case "paused":
            return .paused
        case "stopped":
            return .stopped
        case "kpsp":
            return .playing
        case "kpps":
            return .paused
        default:
            return .unknown
        }
    }

    /// Any 값을 Double로 안전 변환합니다.
    private func doubleValue(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            let parsed = number.doubleValue
            return parsed.isFinite ? parsed : nil
        case let double as Double:
            return double.isFinite ? double : nil
        case let int as Int:
            return Double(int)
        case let string as String:
            guard let parsed = Double(string), parsed.isFinite else { return nil }
            return parsed
        default:
            return nil
        }
    }

    private func fallbackLyricsSnippet() -> String {
        "가사 검색 중...\n잠시 후 자동으로 다시 시도합니다."
    }

    private func parsePlainLyrics(_ raw: String) -> [String] {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { line -> String? in
                guard !line.isEmpty else { return nil }
                // LRC 메타 라인([ar:], [ti:] 등)은 제외합니다.
                if line.hasPrefix("["),
                   line.contains(":"),
                   line.hasSuffix("]"),
                   !line.contains("] ") {
                    return nil
                }
                let cleaned = line.replacingOccurrences(
                    of: #"\[\d{1,2}:\d{2}(?:\.\d{1,3})?\]"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
    }

    private func parseLRCSyncedLyrics(_ raw: String) -> [SyncedLyricLine] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let rows = raw.components(separatedBy: .newlines)
        var result: [SyncedLyricLine] = []

        for row in rows {
            let text = row.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            let matches = regex.matches(in: text, options: [], range: range)
            guard !matches.isEmpty else { continue }

            let lyricStart = matches.map { $0.range.location + $0.range.length }.max() ?? 0
            guard lyricStart <= nsText.length else { continue }
            let lyricBody = nsText.substring(from: lyricStart).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyricBody.isEmpty else { continue }

            for match in matches {
                guard match.numberOfRanges >= 4 else { continue }
                let minuteString = nsText.substring(with: match.range(at: 1))
                let secondString = nsText.substring(with: match.range(at: 2))
                let fractionRange = match.range(at: 3)

                guard let minute = Double(minuteString), let second = Double(secondString) else { continue }
                let fraction: Double
                if fractionRange.location != NSNotFound {
                    let fractionString = nsText.substring(with: fractionRange)
                    let divider = pow(10.0, Double(fractionString.count))
                    fraction = (Double(fractionString) ?? 0) / divider
                } else {
                    fraction = 0
                }

                let total = minute * 60 + second + fraction
                result.append(SyncedLyricLine(time: total, text: lyricBody))
            }
        }

        return result.sorted { $0.time < $1.time }
    }

    private func scheduleLyricsLookupIfNeeded(
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) {
        guard !title.isEmpty, title != "재생 중인 곡 없음" else { return }
        guard snapshot.syncedLyrics.isEmpty else { return }
        let key = trackLookupKey(title: title, artist: artist, duration: duration)
        if applyCachedLyricsIfAvailable(for: key) {
            lyricsLogger.info("lyrics cache hit title=\(title, privacy: .public) artist=\(artist, privacy: .public) synced=\(self.snapshot.syncedLyrics.count, privacy: .public) plain=\(self.snapshot.plainLyrics.count, privacy: .public)")
            return
        }

        if lyricsLookupInFlightKey == key, lyricsLookupTask != nil {
            return
        }

        let now = Date()
        if key == lastLyricsLookupKey,
           let lastLookup = lastLyricsLookupDate,
           now.timeIntervalSince(lastLookup) < LyricsLookup.retryWindow {
            return
        }
        lastLyricsLookupKey = key
        lastLyricsLookupDate = now

        if lyricsLookupInFlightKey != key {
            lyricsLookupTask?.cancel()
        }
        lyricsLookupInFlightKey = key
        lyricsLookupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.lyricsLookupInFlightKey == key {
                    self.lyricsLookupInFlightKey = nil
                    self.lyricsLookupTask = nil
                }
            }
            await self.fetchLyricsFromLrcLib(title: title, artist: artist, album: album, duration: duration)
        }
    }

    private func fetchLyricsFromLrcLib(
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) async {
        guard snapshot.title == title, snapshot.artist == artist else { return }
        if Task.isCancelled { return }
        lyricsLogger.info("lyrics lookup start title=\(title, privacy: .public) artist=\(artist, privacy: .public) duration=\(Int(duration.rounded()), privacy: .public)")

        let trackKey = trackLookupKey(title: title, artist: artist, duration: duration)
        if applyCachedLyricsIfAvailable(for: trackKey) {
            lyricsLogger.info("lyrics already cached title=\(title, privacy: .public) artist=\(artist, privacy: .public)")
            return
        }

        if let searchURL = makeLrcLibSearchURL(title: title, artist: artist) {
            let searchResult: Result<[LrcLibResponse], Error> = await fetchDecodableResult(searchURL, timeout: LyricsLookup.requestTimeout)
            switch searchResult {
            case .success(let responses):
                if let best = bestLrcCandidate(from: responses, title: title, artist: artist, duration: duration) {
                    applyLrcResponseIfMatchesTrack(best, title: title, artist: artist)
                }
                if !snapshot.syncedLyrics.isEmpty || !snapshot.plainLyrics.isEmpty {
                    cacheLyrics(for: trackKey, synced: snapshot.syncedLyrics, plain: snapshot.plainLyrics)
                    lyricsLogger.info("lyrics found source=lrclib_search title=\(title, privacy: .public) artist=\(artist, privacy: .public) synced=\(self.snapshot.syncedLyrics.count, privacy: .public) plain=\(self.snapshot.plainLyrics.count, privacy: .public)")
                    return
                }
            case .failure(let error):
                lyricsLogger.error("lyrics source=lrclib_search failed title=\(title, privacy: .public) artist=\(artist, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
            }
        }

        if Task.isCancelled { return }

        if let requestURL = makeLrcLibGetURL(title: title, artist: artist, album: album, duration: duration) {
            let getResult: Result<LrcLibResponse, Error> = await fetchDecodableResult(requestURL, timeout: LyricsLookup.requestTimeout)
            switch getResult {
            case .success(let single):
                applyLrcResponseIfMatchesTrack(single, title: title, artist: artist)
                if !snapshot.syncedLyrics.isEmpty || !snapshot.plainLyrics.isEmpty {
                    cacheLyrics(for: trackKey, synced: snapshot.syncedLyrics, plain: snapshot.plainLyrics)
                    lyricsLogger.info("lyrics found source=lrclib_get title=\(title, privacy: .public) artist=\(artist, privacy: .public) synced=\(self.snapshot.syncedLyrics.count, privacy: .public) plain=\(self.snapshot.plainLyrics.count, privacy: .public)")
                    return
                }
            case .failure(let error):
                lyricsLogger.error("lyrics source=lrclib_get failed title=\(title, privacy: .public) artist=\(artist, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
            }
        }

        if Task.isCancelled { return }

        // 결과가 불안정한 경우를 대비해 q 기반 검색도 시도합니다.
        if let broadSearchURL = makeLrcLibBroadSearchURL(query: "\(artist) \(title)") {
            let broadResult: Result<[LrcLibResponse], Error> = await fetchDecodableResult(broadSearchURL, timeout: LyricsLookup.fallbackTimeout)
            switch broadResult {
            case .success(let responses):
                if let best = bestLrcCandidate(from: responses, title: title, artist: artist, duration: duration) {
                    applyLrcResponseIfMatchesTrack(best, title: title, artist: artist)
                }
                if !snapshot.syncedLyrics.isEmpty || !snapshot.plainLyrics.isEmpty {
                    cacheLyrics(for: trackKey, synced: snapshot.syncedLyrics, plain: snapshot.plainLyrics)
                    lyricsLogger.info("lyrics found source=lrclib_q title=\(title, privacy: .public) artist=\(artist, privacy: .public) synced=\(self.snapshot.syncedLyrics.count, privacy: .public) plain=\(self.snapshot.plainLyrics.count, privacy: .public)")
                    return
                }
            case .failure(let error):
                lyricsLogger.error("lyrics source=lrclib_q failed title=\(title, privacy: .public) artist=\(artist, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
            }
        }

        if Task.isCancelled { return }

        // LRCLIB에 없으면 plain lyric 전용 엔드포인트로 한 번 더 시도합니다.
        guard let lyricsOvhURL = makeLyricsOvhURL(title: title, artist: artist) else { return }
        let ovhResult: Result<LyricsOvhResponse, Error> = await fetchDecodableResult(lyricsOvhURL, timeout: LyricsLookup.fallbackTimeout)
        switch ovhResult {
        case .success(let response):
            if let plainRaw = response.lyrics {
                applyPlainLyricsIfMatchesTrack(plainRaw, title: title, artist: artist)
            }
            if !snapshot.syncedLyrics.isEmpty || !snapshot.plainLyrics.isEmpty {
                cacheLyrics(for: trackKey, synced: snapshot.syncedLyrics, plain: snapshot.plainLyrics)
                lyricsLogger.info("lyrics found source=lyrics_ovh title=\(title, privacy: .public) artist=\(artist, privacy: .public) synced=\(self.snapshot.syncedLyrics.count, privacy: .public) plain=\(self.snapshot.plainLyrics.count, privacy: .public)")
                return
            }
        case .failure(let error):
            lyricsLogger.error("lyrics source=lyrics_ovh failed title=\(title, privacy: .public) artist=\(artist, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
        }

        if snapshot.syncedLyrics.isEmpty && snapshot.plainLyrics.isEmpty {
            lyricsLogger.info("lyrics not found title=\(title, privacy: .public) artist=\(artist, privacy: .public)")
        }
    }

    private func applyLrcResponseIfMatchesTrack(
        _ response: LrcLibResponse,
        title: String,
        artist: String
    ) {
        guard snapshot.title == title, snapshot.artist == artist else { return }

        if let syncedRaw = response.syncedLyrics, !syncedRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let synced = parseLRCSyncedLyrics(syncedRaw)
            if !synced.isEmpty {
                snapshot.syncedLyrics = synced
                snapshot.plainLyrics = synced.map(\.text)
                snapshot.lyricsSnippet = synced.map(\.text).joined(separator: "\n")
                lyricsLogger.info("lyrics applied synced=true lines=\(synced.count, privacy: .public) title=\(title, privacy: .public) artist=\(artist, privacy: .public)")
                return
            }
        }

        if let plainRaw = response.plainLyrics, !plainRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyPlainLyricsIfMatchesTrack(plainRaw, title: title, artist: artist)
        }
    }

    private func applyPlainLyricsIfMatchesTrack(
        _ plainRaw: String,
        title: String,
        artist: String
    ) {
        guard snapshot.title == title, snapshot.artist == artist else { return }
        let plain = parsePlainLyrics(plainRaw)
        guard !plain.isEmpty else { return }
        snapshot.syncedLyrics = []
        snapshot.plainLyrics = plain
        snapshot.lyricsSnippet = plain.joined(separator: "\n")
        lyricsLogger.info("lyrics applied synced=false lines=\(plain.count, privacy: .public) title=\(title, privacy: .public) artist=\(artist, privacy: .public)")
    }

    private func makeLrcLibGetURL(
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 0 {
            let safeDuration = max(Int(duration.rounded()), 1)
            queryItems.append(URLQueryItem(name: "duration", value: "\(safeDuration)"))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private func makeLrcLibSearchURL(title: String, artist: String) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        return components?.url
    }

    private func makeLrcLibBroadSearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
        ]
        return components?.url
    }

    private func makeLyricsOvhURL(title: String, artist: String) -> URL? {
        let allowed: CharacterSet = {
            var set = CharacterSet.urlPathAllowed
            set.remove(charactersIn: "/")
            return set
        }()
        guard let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "https://api.lyrics.ovh/v1/\(encodedArtist)/\(encodedTitle)")
    }

    private func trackLookupKey(title: String, artist: String, duration: Double) -> String {
        let normalizedTitle = normalizedSearchText(title)
        let normalizedArtist = normalizedSearchText(artist)
        let durationToken = duration > 0 ? String(Int(duration.rounded())) : "0"
        return "\(normalizedTitle)|\(normalizedArtist)|\(durationToken)"
    }

    private func sanitizedDuration(_ duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return duration
    }

    private func sanitizedPosition(_ position: Double, duration: Double) -> Double {
        guard position.isFinite else { return 0 }
        let nonNegative = max(position, 0)
        guard duration > 0 else { return nonNegative }
        return min(nonNegative, duration)
    }

    private func cacheArtwork(for key: String, image: NSImage?, url: URL?) {
        let existing = artworkCache[key]
        let mergedImage = image ?? existing?.image
        let mergedURL = url ?? existing?.url
        guard mergedImage != nil || mergedURL != nil else { return }
        artworkCache[key] = CachedArtwork(url: mergedURL, image: mergedImage)
    }

    @discardableResult
    private func applyCachedArtworkIfAvailable(for key: String) -> Bool {
        guard let cached = artworkCache[key] else { return false }
        // 캐시가 가진 값만 반영하고, 없는 값은 nil로 초기화해 이전 곡 아트워크 잔상을 방지합니다.
        snapshot.artworkImage = cached.image
        snapshot.artworkURL = cached.url
        return snapshot.artworkImage != nil || snapshot.artworkURL != nil
    }

    private func cacheLyrics(for key: String, synced: [SyncedLyricLine], plain: [String]) {
        guard !synced.isEmpty || !plain.isEmpty else { return }
        let snippet = synced.isEmpty ? plain.joined(separator: "\n") : synced.map(\.text).joined(separator: "\n")
        lyricsCache[key] = CachedLyrics(snippet: snippet, synced: synced, plain: plain)
    }

    @discardableResult
    private func applyCachedLyricsIfAvailable(for key: String) -> Bool {
        guard let cached = lyricsCache[key] else { return false }
        snapshot.syncedLyrics = cached.synced
        snapshot.plainLyrics = cached.plain
        snapshot.lyricsSnippet = cached.snippet
        return true
    }

    private func bestLrcCandidate(
        from candidates: [LrcLibResponse],
        title: String,
        artist: String,
        duration: Double
    ) -> LrcLibResponse? {
        guard !candidates.isEmpty else { return nil }
        let expectedTitle = normalizedSearchText(title)
        let expectedArtist = normalizedSearchText(artist)

        func score(for candidate: LrcLibResponse) -> Int {
            var score = 0
            let candidateTitle = normalizedSearchText(candidate.trackName ?? "")
            let candidateArtist = normalizedSearchText(candidate.artistName ?? "")

            if candidateTitle == expectedTitle, !candidateTitle.isEmpty {
                score += 90
            } else if !expectedTitle.isEmpty,
                      !candidateTitle.isEmpty,
                      (candidateTitle.contains(expectedTitle) || expectedTitle.contains(candidateTitle)) {
                score += 50
            }

            if candidateArtist == expectedArtist, !candidateArtist.isEmpty {
                score += 90
            } else if !expectedArtist.isEmpty,
                      !candidateArtist.isEmpty,
                      (candidateArtist.contains(expectedArtist) || expectedArtist.contains(candidateArtist)) {
                score += 55
            }

            if duration > 0, let candidateDuration = candidate.duration, candidateDuration > 0 {
                let delta = abs(candidateDuration - duration)
                if delta <= 1 { score += 40 }
                else if delta <= 3 { score += 25 }
                else if delta <= 8 { score += 10 }
            }

            if hasRenderableLyrics(candidate.syncedLyrics) {
                score += 18
            } else if hasRenderableLyrics(candidate.plainLyrics) {
                score += 6
            }

            if candidate.instrumental == true {
                score -= 25
            }

            return score
        }

        return candidates.max { score(for: $0) < score(for: $1) }
    }

    private func hasRenderableLyrics(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func normalizedSearchText(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(
                of: #"\s*\((feat|ft|featuring)\.?[^)]*\)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[^a-z0-9가-힣]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchDecodable<T: Decodable>(_ url: URL, timeout: TimeInterval) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("diodiooodio/1.0 (+https://github.com/jjunhaa/odioodiodio)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetchDecodableResult<T: Decodable>(_ url: URL, timeout: TimeInterval) async -> Result<T, Error> {
        do {
            let value: T = try await fetchDecodable(url, timeout: timeout)
            return .success(value)
        } catch {
            return .failure(error)
        }
    }

    private func extractArtworkImage(from userInfo: [AnyHashable: Any]) -> NSImage? {
        let keys = ["ArtworkData", "Artwork Data", "Cover Artwork", "Artwork"]
        for key in keys {
            if let image = userInfo[key] as? NSImage {
                return image
            }
            if let data = userInfo[key] as? Data,
               let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    private func executeMusicAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }

    private func executeMusicAppleScriptWithResult(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return nil }
        return result.stringValue
    }

    private var isMusicAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    private func attemptPauseAndRecoverIfMusicRunning() async -> Bool {
        guard isMusicAppRunning else { return false }
        guard !isAutoRecoveryInProgress else { return false }
        isAutoRecoveryInProgress = true
        defer {
            isAutoRecoveryInProgress = false
        }

        // Apple Music이 실행 중이면 pause -> play -> pause 순서로 상태 변화를 강제로 발생시킵니다.
        var executedAnyAppleScriptCommand = false
        if executeMusicAppleScript("tell application \"Music\" to pause") {
            executedAnyAppleScriptCommand = true
            try? await Task.sleep(for: AutoRecovery.pauseDelay)
        }
        if executeMusicAppleScript("tell application \"Music\" to play") {
            executedAnyAppleScriptCommand = true
            try? await Task.sleep(for: AutoRecovery.pauseDelay)
        }
        if executeMusicAppleScript("tell application \"Music\" to pause") {
            executedAnyAppleScriptCommand = true
            try? await Task.sleep(for: AutoRecovery.pauseDelay)
        }
        if executedAnyAppleScriptCommand {
            return true
        }

        // AppleScript 제어가 막힌 경우 MusicKit 경로로 pause를 시도합니다.
        do {
            if player.state.playbackStatus == .playing {
                player.pause()
                try? await Task.sleep(for: AutoRecovery.pauseDelay)
                return true
            }
            try await player.play()
            try? await Task.sleep(for: AutoRecovery.pauseDelay)
            player.pause()
            try? await Task.sleep(for: AutoRecovery.pauseDelay)
            return true
        } catch {
            return false
        }
    }

    private func lookupArtworkIfNeeded(title: String, artist: String) async {
        guard !title.isEmpty, title != "재생 중인 곡 없음" else { return }
        let key = trackLookupKey(title: title, artist: artist, duration: snapshot.duration)
        if currentArtworkTrackKey == key, (snapshot.artworkImage != nil || snapshot.artworkURL != nil) {
            return
        }
        if applyCachedArtworkIfAvailable(for: key) {
            currentArtworkTrackKey = key
            return
        }

        let lookupKey = key
        let now = Date()
        if lookupKey == lastArtworkLookupKey,
           let lastLookup = lastArtworkLookupDate,
           now.timeIntervalSince(lastLookup) < ArtworkLookup.retryWindow {
            return
        }
        lastArtworkLookupKey = lookupKey
        lastArtworkLookupDate = now

        let term = "\(artist) \(title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard !term.isEmpty else { return }

        guard let url = URL(string: "https://itunes.apple.com/search?term=\(term)&entity=song&limit=1") else {
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = ArtworkLookup.requestTimeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            guard let http = urlResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }
            let searchResponse = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let artwork = searchResponse.results.first?.artworkUrl100,
                  var artworkURL = URL(string: artwork) else {
                return
            }

            if artworkURL.absoluteString.contains("100x100") {
                let large = artworkURL.absoluteString.replacingOccurrences(of: "100x100", with: "600x600")
                if let largeURL = URL(string: large) {
                    artworkURL = largeURL
                }
            }

            guard snapshot.title == title, snapshot.artist == artist else { return }
            snapshot.artworkImage = nil
            snapshot.artworkURL = artworkURL
            cacheArtwork(for: key, image: nil, url: artworkURL)
            currentArtworkTrackKey = key
        } catch {
            // 아트워크 조회 실패는 UI 동작을 막지 않습니다.
        }
    }
}

private extension String {
    /// 앞뒤 공백 제거 후 비어 있지 않은 문자열만 반환합니다.
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
