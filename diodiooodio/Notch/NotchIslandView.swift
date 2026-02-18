import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Dynamic Island 스타일 상단 오버레이 UI입니다.
struct NotchIslandView: View {
    @Bindable var controller: NotchIslandController
    @Bindable var musicService: AppleMusicNowPlayingService

    @State private var isAirDropTargeted = false
    @State private var isPhotoDropTargeted = false
    @State private var selectedSection: NotchIslandController.IslandModule = .music
    @State private var feedbackMessage: String?
    @State private var isSeeking = false
    @State private var isSeekCommitPending = false
    @State private var seekCommitDeadline: Date = .distantPast
    @State private var seekPosition: Double = 0
    @State private var isIslandHovering = false
    @State private var lyricAnchorPosition: Double = 0
    @State private var lyricAnchorDate: Date = .distantPast

    private var language: AppLanguage { controller.language }

    private func t(_ english: String, _ korean: String) -> String {
        language.text(english, korean)
    }

    var body: some View {
        let snapshot = musicService.snapshot
        let isMinimalCompact = !controller.isExpanded
            && !controller.isCompactNowPlayingVisible
            && !controller.isCompactPlaybackStatusVisible

        VStack(alignment: .leading, spacing: 11) {
            compactHeader(snapshot)

            if controller.isExpanded {
                if controller.enabledModules.isEmpty {
                    emptyModuleState
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        sectionToggleRail

                        Group {
                            switch selectedSection {
                            case .music:
                                musicSection(snapshot)
                            case .files:
                                filesSection
                            case .time:
                                timeSection
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.leading, controller.isExpanded ? 16 : (isMinimalCompact ? 8 : 12))
        .padding(.trailing, controller.isExpanded ? 16 : (isMinimalCompact ? 10 : 18))
        .padding(.top, controller.isExpanded ? 12 : (isMinimalCompact ? 7 : 10))
        .padding(.bottom, controller.isExpanded ? 12 : (isMinimalCompact ? 1 : 2))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(islandBackground)
        .overlay(islandHoverSelectionOverlay)
        .onTapGesture {
            guard !controller.isAutoControlEnabled else { return }
            controller.toggleExpanded()
        }
        .onHover { hovering in
            isIslandHovering = hovering
            controller.handleIslandHoverChanged(hovering)
        }
        .onAppear {
            syncSelectedSectionToEnabledModules()
        }
        .onChange(of: controller.isExpanded) { _, expanded in
            if expanded {
                syncSelectedSectionToEnabledModules()
            }
        }
        .onChange(of: controller.isMusicModuleEnabled) { _, _ in
            syncSelectedSectionToEnabledModules()
        }
        .onChange(of: controller.isFilesModuleEnabled) { _, _ in
            syncSelectedSectionToEnabledModules()
        }
        .onChange(of: controller.isTimeModuleEnabled) { _, _ in
            syncSelectedSectionToEnabledModules()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: controller.isExpanded)
    }

    private var islandBackground: some View {
        let corner = controller.isExpanded ? 28.0 : 20.0
        let baseFill = Color.black.opacity(controller.isExpanded ? 0.93 : 0.96)
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: corner,
                bottomTrailing: corner,
                topTrailing: 0
            ),
            style: .continuous
        )

        return shape
            .fill(baseFill)
    }

    private var islandHoverSelectionOverlay: some View {
        let corner = controller.isExpanded ? 28.0 : 20.0
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: corner,
                bottomTrailing: corner,
                topTrailing: 0
            ),
            style: .continuous
        )
        let shouldHighlight = isIslandHovering && !controller.isExpanded

        return shape
            .fill(shouldHighlight ? Color.white.opacity(0.04) : Color.clear)
            .overlay(
                shape
                    .strokeBorder(
                        shouldHighlight ? DesignTokens.Colors.accentPrimary.opacity(0.45) : Color.clear,
                        lineWidth: 0.8
                    )
            )
            .animation(.easeOut(duration: 0.16), value: shouldHighlight)
            .allowsHitTesting(false)
    }

    private func compactHeader(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> some View {
        Group {
            if controller.isExpanded {
                expandedHeader(snapshot)
            } else {
                collapsedHeader(snapshot)
            }
        }
    }

    private func expandedHeader(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> some View {
        return HStack(spacing: 10) {
            Circle()
                .fill(snapshot.isPlaying ? DesignTokens.Colors.accentPrimary : DesignTokens.Colors.textTertiary)
                .frame(width: 9, height: 9)
            Spacer(minLength: 0)
            pinToggleButton
        }
    }

    private func collapsedHeader(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> some View {
        let showsTitle = controller.isCompactNowPlayingVisible
        let showsPlaybackStatus = controller.isCompactPlaybackStatusVisible
        let headerHeight: CGFloat = showsTitle ? (showsPlaybackStatus ? 32 : 34) : (showsPlaybackStatus ? 20 : 8)
        let titleTopInset: CGFloat = showsPlaybackStatus ? 4 : 20

        return HStack(alignment: .top, spacing: 8) {
            if showsTitle {
                VStack(alignment: .leading, spacing: 2) {
                    if showsPlaybackStatus {
                        playbackPulseBars(isPlaying: snapshot.isPlaying)
                            .frame(width: 34, height: 14)
                    }

                    LoopingMarqueeText(
                        text: nowPlayingBannerText(snapshot),
                        font: .system(size: 11, weight: .semibold),
                        textColor: DesignTokens.Colors.textPrimary,
                        speed: 28,
                        gap: 24,
                        holdTime: 0.8
                    )
                    .padding(.top, titleTopInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if showsPlaybackStatus {
                playbackPulseBars(isPlaying: snapshot.isPlaying)
                    .frame(width: 34, height: 14)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: headerHeight, maxHeight: headerHeight, alignment: .topLeading)
        .padding(.top, showsTitle ? (showsPlaybackStatus ? 1 : 2) : 0)
        .padding(.horizontal, 4)
    }

    private func playbackPulseBars(isPlaying: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 0.11)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.4) {
                ForEach(0..<8, id: \.self) { index in
                    let wave = abs(sin(now * 2.9 + Double(index) * 0.82))
                    let height = isPlaying ? 4.5 + (wave * 9.0) : 5.0
                    Capsule(style: .continuous)
                        .fill(
                            Color(red: 0.57, green: 0.33, blue: 0.95)
                                .opacity(isPlaying ? (index == 0 ? 1.0 : 0.72) : (index == 0 ? 0.88 : 0.24))
                        )
                        .frame(width: 3, height: height)
                }
            }
            .frame(width: 34, height: 14, alignment: .leading)
        }
    }

    private var pinToggleButton: some View {
        Button {
            let pinned = !controller.isExpansionPinned
            controller.setExpansionPinned(pinned)
            showFeedback(pinned ? t("Expanded state pinned.", "확장 상태를 고정했습니다.") : t("Pin disabled.", "고정이 해제되었습니다."))
        } label: {
            ZStack {
                Circle()
                    .fill(controller.isExpansionPinned ? DesignTokens.Colors.accentPrimary.opacity(0.22) : Color.white.opacity(0.1))
                    .frame(width: 24, height: 24)

                Image(systemName: controller.isExpansionPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(controller.isExpansionPinned ? DesignTokens.Colors.accentPrimary : DesignTokens.Colors.textSecondary)
            }
            .frame(width: 26, height: 24, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func nowPlayingBannerText(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> String {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && artist.isEmpty {
            return t("Now Playing", "지금 재생 중")
        }
        if artist.isEmpty {
            return title
        }
        if title.isEmpty {
            return artist
        }
        return "\(title) - \(artist)"
    }

    private func expandedNowPlayingText(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> some View {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? t("No Track Playing", "재생 중인 곡 없음") : title

        return VStack(alignment: .leading, spacing: 2) {
            Text(displayTitle)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
    }

    private var sectionToggleRail: some View {
        VStack(spacing: 8) {
            ForEach(controller.enabledModules, id: \.self) { module in
                sectionToggleButton(for: module)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(minWidth: 76, idealWidth: 76, maxWidth: 76, minHeight: 260, alignment: .top)
        .background(cardBackground(corner: 14))
    }

    private func sectionToggleButton(for module: NotchIslandController.IslandModule) -> some View {
        let isSelected = selectedSection == module

        return Button {
            selectedSection = module
        } label: {
            VStack(spacing: 4) {
                Image(systemName: moduleIcon(module))
                    .font(.system(size: 12, weight: .semibold))
                Text(moduleTitle(module))
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.black : DesignTokens.Colors.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.92) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyModuleState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("활성화된 모듈이 없습니다")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text("MainUI > Media > Notch Modules에서 Music, Files, Time 모듈을 켜주세요.")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground(corner: 12))
    }

    private func musicSection(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            expandedNowPlayingText(snapshot)

            HStack(alignment: .top, spacing: 12) {
                artworkView(snapshot)
                    .frame(width: 120, height: 120)

                lyricsPanel(snapshot)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 120)
            }
            .frame(height: 120)
            .clipped()

            seekBar(snapshot)

            HStack {
                Text(formatTime(isSeeking ? seekPosition : snapshot.position))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Spacer()

                Text(formatTime(snapshot.duration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            HStack(spacing: 16) {
                musicControlButton("backward.fill") {
                    musicService.skipToPrevious()
                }

                musicControlButton(snapshot.isPlaying ? "pause.fill" : "play.fill") {
                    musicService.togglePlayPause()
                }

                musicControlButton("forward.fill") {
                    musicService.skipToNext()
                }

                Spacer()

                Button("Apple Music") {
                    musicService.openMusicApp()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.accentPrimary)
            }

            if let error = musicService.lastErrorMessage {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(cardBackground(corner: 14))
    }

    private func seekBar(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> some View {
        let safeDuration = snapshot.duration.isFinite ? max(snapshot.duration, 0) : 0
        let safeRangeUpper = max(safeDuration, 0.1)

        return AppleMusicSeekBar(
            value: Binding(
                get: {
                    let shouldLockToSeekPosition = isSeeking || isSeekCommitPending
                    let raw = shouldLockToSeekPosition ? seekPosition : snapshot.position
                    return raw.isFinite ? raw : 0
                },
                set: { seekPosition = $0.isFinite ? $0 : 0 }
            ),
            range: 0...safeRangeUpper,
            isEnabled: safeDuration > 0
        ) { editing in
            isSeeking = editing
            if !editing {
                isSeekCommitPending = true
                seekCommitDeadline = Date().addingTimeInterval(0.9)
                musicService.seek(to: seekPosition)
            }
        }
        .onAppear {
            seekPosition = snapshot.position.isFinite ? snapshot.position : 0
        }
        .onChange(of: snapshot.position) { _, newValue in
            guard !isSeeking else { return }
            let safeIncoming = newValue.isFinite ? newValue : 0

            if isSeekCommitPending {
                let deadlinePassed = Date() >= seekCommitDeadline
                let converged = abs(safeIncoming - seekPosition) <= 1.0
                if converged || deadlinePassed {
                    isSeekCommitPending = false
                    seekPosition = safeIncoming
                }
                return
            }

            seekPosition = safeIncoming
        }
        .onChange(of: snapshot.duration) { _, newDuration in
            if !isSeeking {
                let safeDuration = newDuration.isFinite ? max(newDuration, 0) : 0
                seekPosition = min(max(seekPosition.isFinite ? seekPosition : 0, 0), safeDuration)
            }
        }
        .onChange(of: snapshot.title) { _, _ in
            isSeekCommitPending = false
        }
        .onChange(of: snapshot.artist) { _, _ in
            isSeekCommitPending = false
        }
    }

    private func artworkView(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> some View {
        let artworkReloadID = artworkIdentity(snapshot)

        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let artworkImage = snapshot.artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else if let artworkURL = snapshot.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .empty:
                        placeholderArtwork
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderArtwork
                    @unknown default:
                        placeholderArtwork
                    }
                }
            } else {
                placeholderArtwork
            }

            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.accentPrimary)
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .padding(6)
        }
        .id(artworkReloadID)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func artworkIdentity(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> String {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationToken = Int(snapshot.duration.rounded())
        let urlToken = snapshot.artworkURL?.absoluteString ?? "no-url"
        let hasImage = snapshot.artworkImage != nil ? "img" : "no-img"
        return "\(title)|\(artist)|\(durationToken)|\(urlToken)|\(hasImage)"
    }

    private var placeholderArtwork: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
        )
    }

    private func lyricsPanel(_ snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> some View {
        let lines = lyricLines(from: snapshot)
        let isFallback = isFallbackLyricLines(lines)
        let centerSlot = 1

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let position = interpolatedLyricPosition(snapshot: snapshot, now: context.date)
            let activeIndex = activeLyricsLineIndex(lines: lines, snapshot: snapshot, position: position)
            let window = lyricWindow(lines: lines, activeIndex: activeIndex, radius: centerSlot)

            ZStack {
                if isFallback {
                    fallbackLyricsView(lines: lines)
                } else {
                    VStack(spacing: 4) {
                        ForEach(window) { item in
                            lyricLineView(
                                text: item.text,
                                slot: item.slot,
                                centerSlot: centerSlot,
                                isPlaceholder: item.index == nil
                            )
                            .id(item.index ?? -(item.slot + 1))
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                        }
                    }
                    .animation(.spring(response: 0.36, dampingFraction: 0.88), value: activeIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .mask(lyricsEdgeMask)
            .clipped()
        }
        .onAppear {
            updateLyricAnchor(from: snapshot)
        }
        .onChange(of: snapshot.position) { _, _ in
            updateLyricAnchor(from: snapshot)
        }
        .onChange(of: snapshot.isPlaying) { _, _ in
            updateLyricAnchor(from: snapshot)
        }
    }

    private func lyricLines(from snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) -> [String] {
        if !snapshot.syncedLyrics.isEmpty {
            return snapshot.syncedLyrics.map(\.text)
        }

        if !snapshot.plainLyrics.isEmpty {
            return snapshot.plainLyrics
        }

        let snippet = snapshot.lyricsSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snippet.isEmpty {
            let lines = snippet
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                return lines
            }
        }

        return [
            fallbackLyricLines[0],
            fallbackLyricLines[1],
        ]
    }

    private var fallbackLyricLines: [String] {
        [
            "가사 검색 중...",
            "잠시 후 자동으로 다시 시도합니다.",
        ]
    }

    private func isFallbackLyricLines(_ lines: [String]) -> Bool {
        guard lines.count == fallbackLyricLines.count else { return false }
        return zip(lines, fallbackLyricLines).allSatisfy { lhs, rhs in
            lhs.trimmingCharacters(in: .whitespacesAndNewlines) == rhs
        }
    }

    private func activeLyricsLineIndex(
        lines: [String],
        snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot,
        position: Double? = nil
    ) -> Int {
        if !snapshot.syncedLyrics.isEmpty {
            let leadTime: TimeInterval = 0.42
            let target = max(position ?? snapshot.position, 0)
            if let exact = snapshot.syncedLyrics.lastIndex(where: { $0.time <= target + leadTime }) {
                return exact
            }
            return 0
        }

        let nonEmptyLines = lines.enumerated().filter { !$0.element.isEmpty }
        guard !nonEmptyLines.isEmpty else { return 0 }

        let activeNonEmptyIndex: Int
        if snapshot.duration > 0 {
            let current = position ?? snapshot.position
            let ratio = min(max(current / snapshot.duration, 0), 1)
            activeNonEmptyIndex = Int((Double(nonEmptyLines.count - 1) * ratio).rounded())
        } else {
            activeNonEmptyIndex = snapshot.isPlaying
                ? Int((position ?? snapshot.position).rounded(.down)) % nonEmptyLines.count
                : 0
        }

        let boundedIndex = min(max(activeNonEmptyIndex, 0), nonEmptyLines.count - 1)
        return nonEmptyLines[boundedIndex].offset
    }

    private func lyricLineView(
        text: String,
        slot: Int,
        centerSlot: Int,
        isPlaceholder: Bool
    ) -> some View {
        let distance = abs(slot - centerSlot)
        let isActive = distance == 0 && !isPlaceholder
        let fontSize: CGFloat = isActive ? 15 : 12.5
        let fontWeight: Font.Weight = isActive ? .bold : .semibold
        let opacity: Double
        if isPlaceholder {
            opacity = 0
        } else if isActive {
            opacity = 0.95
        } else if distance == 1 {
            opacity = 0.42
        } else {
            opacity = 0.30
        }
        let blurRadius: CGFloat = isActive ? 0 : 0.65
        let scale: CGFloat = isActive ? 1.0 : 0.97
        let shadowColor = Color.black.opacity(isActive ? 0.22 : 0)
        let shadowRadius: CGFloat = isActive ? 4 : 0
        let rowHeight: CGFloat = isActive ? 72 : 18
        let lineLimit = isActive ? 4 : 2

        return Text(wrappedLyricLine(text, isActive: isActive))
            .font(.system(size: fontSize, weight: fontWeight))
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.center)
            .lineSpacing(isActive ? 1.0 : 0)
            .foregroundStyle(Color.white.opacity(opacity))
            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .center)
            .scaleEffect(scale)
            .blur(radius: blurRadius)
            .shadow(color: shadowColor, radius: shadowRadius, y: 1)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.22), value: slot)
    }

    private func fallbackLyricsView(lines: [String]) -> some View {
        VStack(spacing: 10) {
            Text(lines.first ?? fallbackLyricLines[0])
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            Text(lines.dropFirst().first ?? fallbackLyricLines[1])
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .transition(.opacity)
    }

    private var lyricsEdgeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .white, location: 0.15),
                .init(color: .white, location: 0.85),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func wrappedLyricLine(_ text: String, isActive: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let maxLines = isActive ? 4 : 2
        let targetCharsPerLine = isActive ? 22 : 20
        let normalized = trimmed.replacingOccurrences(of: "\n", with: " ")
        let words = normalized
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        guard !words.isEmpty else { return normalized }

        var tokens: [String] = []
        for word in words {
            if word.count > targetCharsPerLine {
                tokens.append(contentsOf: chunkWord(word, chunkSize: targetCharsPerLine))
            } else {
                tokens.append(word)
            }
        }

        var lines: [String] = []
        var currentLine = ""

        for token in tokens {
            let candidate = currentLine.isEmpty ? token : "\(currentLine) \(token)"
            if candidate.count <= targetCharsPerLine || currentLine.isEmpty {
                currentLine = candidate
                continue
            }

            lines.append(currentLine)
            currentLine = token
            if lines.count >= maxLines - 1 {
                break
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
        }

        return lines.joined(separator: "\n")
    }

    private func chunkWord(_ word: String, chunkSize: Int) -> [String] {
        guard chunkSize > 0 else { return [word] }
        var result: [String] = []
        var start = word.startIndex
        while start < word.endIndex {
            let end = word.index(start, offsetBy: chunkSize, limitedBy: word.endIndex) ?? word.endIndex
            result.append(String(word[start..<end]))
            start = end
        }
        return result
    }

    private func lyricWindow(
        lines: [String],
        activeIndex: Int,
        radius: Int
    ) -> [LyricWindowItem] {
        guard radius >= 0 else { return [] }

        return Array((-radius...radius).enumerated()).map { slot, delta in
            let index = activeIndex + delta
            if lines.indices.contains(index) {
                return LyricWindowItem(slot: slot, index: index, text: lines[index])
            }
            return LyricWindowItem(slot: slot, index: nil, text: " ")
        }
    }

    private func updateLyricAnchor(from snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot) {
        lyricAnchorPosition = max(snapshot.position, 0)
        lyricAnchorDate = Date()
    }

    private func interpolatedLyricPosition(
        snapshot: AppleMusicNowPlayingService.NowPlayingSnapshot,
        now: Date
    ) -> Double {
        guard snapshot.isPlaying else { return max(snapshot.position, 0) }
        guard lyricAnchorDate != .distantPast else { return max(snapshot.position, 0) }

        let elapsed = max(now.timeIntervalSince(lyricAnchorDate), 0)
        let projected = lyricAnchorPosition + elapsed
        let limited = snapshot.duration > 0 ? min(projected, snapshot.duration) : projected
        return max(limited, 0)
    }

    private func musicControlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
                )
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let spacing: CGFloat = 10
                let total = max(proxy.size.width - spacing, 0)
                let airDropWidth = floor(total * 0.25)
                let stashWidth = total - airDropWidth

                HStack(spacing: spacing) {
                    airDropCard
                        .frame(width: airDropWidth)
                        .frame(maxHeight: .infinity)

                    photoStashCard
                        .frame(width: stashWidth)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(height: 230)

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.accentPrimary)
            }
        }
    }

    private var airDropCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(t("AirDrop", "에어드랍"), systemImage: "airplayaudio")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("\(controller.droppedFiles.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            if !controller.droppedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(Array(controller.droppedFiles.prefix(5)), id: \.self) { fileURL in
                                airDropFilePreview(fileURL)
                            }
                        }
                    }

                    ForEach(Array(controller.droppedFiles.prefix(2)), id: \.self) { fileURL in
                        Text(fileURL.lastPathComponent)
                            .font(.system(size: 10, weight: .regular))
                            .lineLimit(1)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            }

            airDropDropZone

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    controller.sendDroppedFilesViaAirDrop()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignTokens.Colors.accentPrimary.opacity(0.18))
                            .frame(width: 30, height: 30)

                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(width: 38, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.accentPrimary)
                .disabled(controller.droppedFiles.isEmpty)

                Button {
                    controller.clearDroppedFiles()
                    showFeedback(t("Cleared dropped files.", "파일 목록을 비웠습니다."))
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 30, height: 30)

                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(width: 38, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .disabled(controller.droppedFiles.isEmpty)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(10)
        .background(cardBackground(corner: 12))
    }

    private var airDropDropZone: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(isAirDropTargeted ? 0.13 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isAirDropTargeted ? DesignTokens.Colors.accentPrimary.opacity(0.9) : Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.0, dash: [5, 4])
                    )
            )
            .overlay(
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.right")
                    Text(t("Drop files for AirDrop", "에어드랍 파일 드롭"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            )
            .frame(height: 56)
            .onDrop(of: [UTType.fileURL], isTargeted: $isAirDropTargeted, perform: handleAirDropDrop)
    }

    private var photoStashCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(t("Temporary Photo Stash", "사진 임시 보관함"), systemImage: "photo.stack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("\(controller.stashedPhotos.count)장")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            photoDropZone

            if controller.stashedPhotos.isEmpty {
                Text(t("Dropped photos are stored immediately and can be copied later.", "드롭한 사진은 바로 보관되며 나중에 복사할 수 있습니다."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(controller.stashedPhotos.prefix(8))) { photo in
                            photoThumbnail(photo)
                        }
                    }
                }

                HStack {
                    Button(t("Copy Latest Photo", "최근 사진 복사")) {
                        let copied = controller.copyLatestStashedPhotoToPasteboard()
                        showFeedback(copied ? t("Copied the latest photo.", "최근 사진을 클립보드에 복사했습니다.") : t("Failed to copy photo.", "사진 복사에 실패했습니다."))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentPrimary)
                    .disabled(controller.stashedPhotos.isEmpty)

                    Spacer()

                    Button {
                        controller.clearPhotoStash()
                        showFeedback(t("Cleared photo stash.", "사진 보관함을 비웠습니다."))
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 28, height: 28)

                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(width: 36, height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .disabled(controller.stashedPhotos.isEmpty)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(10)
        .background(cardBackground(corner: 12))
    }

    private var photoDropZone: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(isPhotoDropTargeted ? 0.13 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isPhotoDropTargeted ? DesignTokens.Colors.accentPrimary.opacity(0.9) : Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.0, dash: [5, 4])
                    )
            )
            .overlay(
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text(t("Drop photo files", "사진 파일 드롭"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            )
            .frame(height: 56)
            .onDrop(of: [UTType.fileURL], isTargeted: $isPhotoDropTargeted, perform: handlePhotoStashDrop)
    }

    private func airDropFilePreview(_ fileURL: URL) -> some View {
        ZStack {
            if isImageURL(fileURL), let image = NSImage(contentsOf: fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .overlay(
                        Image(systemName: "doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    )
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func photoThumbnail(_ photo: NotchIslandController.StashedPhoto) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image = NSImage(contentsOf: photo.storedURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        )
                }
            }
            .frame(width: 88, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    let copied = controller.copyStashedPhotoToPasteboard(photo)
                    showFeedback(copied ? t("Photo copied.", "사진을 복사했습니다.") : t("Failed to copy photo.", "사진 복사에 실패했습니다."))
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)

                Button {
                    controller.revealStashedPhotoInFinder(photo)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.92))

                Button {
                    controller.removeStashedPhoto(photo)
                    showFeedback(t("Photo removed.", "사진을 삭제했습니다."))
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.92))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.32))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Time Module Coming Soon", "Time 모듈 준비 중"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text(t("Clock, date, and schedule widgets will be added here.", "향후 시계, 날짜, 일정 위젯을 이 영역에 넣을 수 있습니다."))
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(cardBackground(corner: 14))
    }

    private func handleAirDropDrop(_ providers: [NSItemProvider]) -> Bool {
        handleFileDrop(providers) { url in
            controller.addDroppedFiles([url])
        }
    }

    private func handlePhotoStashDrop(_ providers: [NSItemProvider]) -> Bool {
        handleFileDrop(providers) { url in
            controller.addPhotosToStash(from: [url])
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider], onFileURL: @escaping (URL) -> Void) -> Bool {
        var hasDropItem = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            hasDropItem = true

            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = extractFileURL(from: item) else { return }
                DispatchQueue.main.async {
                    onFileURL(url)
                }
            }
        }

        return hasDropItem
    }

    private func extractFileURL(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let url = item as? URL {
            return url
        }

        if let nsURL = item as? NSURL {
            return nsURL as URL
        }

        if let raw = item as? String {
            return URL(string: raw)
        }

        return nil
    }

    private func isImageURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private func syncSelectedSectionToEnabledModules() {
        let enabled = controller.enabledModules
        if let first = enabled.first, !enabled.contains(selectedSection) {
            selectedSection = first
        }
    }

    private func showFeedback(_ message: String) {
        feedbackMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard feedbackMessage == message else { return }
            feedbackMessage = nil
        }
    }

    private func moduleTitle(_ module: NotchIslandController.IslandModule) -> String {
        switch module {
        case .music: return t("Music", "음악")
        case .files: return t("Files", "파일")
        case .time: return t("Time", "시간")
        }
    }

    private func moduleIcon(_ module: NotchIslandController.IslandModule) -> String {
        switch module {
        case .music: return "music.note"
        case .files: return "folder"
        case .time: return "clock"
        }
    }

    private func cardBackground(corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color.white.opacity(0.06))
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let seconds = Int(value.rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func progressBar(position: Double, duration: Double) -> some View {
        let ratio: Double
        if duration > 0 {
            ratio = min(max(position / duration, 0), 1)
        } else {
            ratio = 0
        }

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 5)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [DesignTokens.Colors.accentPrimary.opacity(0.9), Color.white.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * ratio, height: 5)
            }
        }
        .frame(height: 5)
    }
}

private struct LyricWindowItem: Identifiable {
    let slot: Int
    let index: Int?
    let text: String

    var id: Int { slot }
}

private struct AppleMusicSeekBar: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let isEnabled: Bool
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false
    @State private var isHovering = false

    private var normalizedValue: Double {
        guard range.lowerBound.isFinite, range.upperBound.isFinite, value.isFinite else { return 0 }
        guard range.upperBound > range.lowerBound else { return 0 }
        let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = normalizedValue
            let rawFillWidth = width * progress
            let fillWidth = rawFillWidth.isFinite ? max(4, rawFillWidth) : 4
            let knobVisible = (isDragging || isHovering) && isEnabled
            let trackHeight: CGFloat = isDragging ? 5.0 : 4.0
            let knobSize: CGFloat = isDragging ? 14 : 11
            let rawKnobOffset = fillWidth - (knobSize / 2)
            let knobOffset = rawKnobOffset.isFinite
                ? min(max(rawKnobOffset, 0), width - knobSize)
                : 0

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .frame(height: trackHeight)

                Capsule(style: .continuous)
                    .fill(DesignTokens.Colors.accentPrimary.opacity(0.95))
                    .frame(width: fillWidth, height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: Color.black.opacity(0.24), radius: 6, y: 1)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
                    )
                    .offset(x: knobOffset)
                    .opacity(knobVisible ? 1 : 0)
                    .scaleEffect(knobVisible ? 1 : 0.85)
            }
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        updateValue(with: gesture.location.x, width: width)
                    }
                    .onEnded { gesture in
                        guard isEnabled else { return }
                        updateValue(with: gesture.location.x, width: width)
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .onHover { hovering in
                isHovering = hovering
            }
            .opacity(isEnabled ? 1.0 : 0.45)
        }
        .frame(height: 24)
    }

    private func updateValue(with locationX: CGFloat, width: CGFloat) {
        let clampedX = min(max(locationX, 0), width)
        let ratio = Double(clampedX / width)
        guard ratio.isFinite else { return }
        let nextValue = range.lowerBound + ((range.upperBound - range.lowerBound) * ratio)
        value = nextValue.isFinite ? nextValue : range.lowerBound
    }
}

private struct LoopingMarqueeText: View {
    let text: String
    let font: Font
    let textColor: Color
    var speed: CGFloat = 30
    var gap: CGFloat = 28
    var holdTime: Double = 0.9

    @State private var measuredTextWidth: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let containerWidth = proxy.size.width

            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context -> AnyView in
                if measuredTextWidth == 0 || measuredTextWidth <= containerWidth {
                    return AnyView(
                        marqueeLabel
                            .frame(maxWidth: .infinity, alignment: .center)
                    )
                }

                let scrollDistance = measuredTextWidth + gap
                let scrollDuration = max(Double(scrollDistance / speed), 0.01)
                let cycleDuration = holdTime + scrollDuration + holdTime
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)

                let offset: CGFloat
                if phase < holdTime {
                    offset = 0
                } else if phase < holdTime + scrollDuration {
                    offset = -CGFloat(phase - holdTime) * speed
                } else {
                    offset = -scrollDistance
                }

                return AnyView(
                    HStack(spacing: gap) {
                        marqueeLabel
                        marqueeLabel
                    }
                    .offset(x: offset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
            }
            .clipped()
        }
        .frame(height: 16)
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(textColor)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: MarqueeTextWidthPreferenceKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(MarqueeTextWidthPreferenceKey.self) { measuredTextWidth = $0 }
    }
}

private struct MarqueeTextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
