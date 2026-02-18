import SwiftUI

/// 미디어 탭 본문입니다.
struct MediaTabContentView: View {
    @Bindable var musicService: AppleMusicNowPlayingService
    @Bindable var notchController: NotchIslandController
    let language: AppLanguage

    private func t(_ english: String, _ korean: String) -> String {
        language.text(english, korean)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                nowPlayingCard
                islandModulesCard
                islandControlCard
            }
            .padding(20)
        }
    }

    private var nowPlayingCard: some View {
        let snapshot = musicService.snapshot

        return VStack(alignment: .leading, spacing: 12) {
            Text(t("Apple Music", "Apple Music"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Text(snapshot.artist)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(musicService.isAuthorized ? DesignTokens.Colors.accentPrimary : DesignTokens.Colors.mutedIndicator)
                    .frame(width: 8, height: 8)
                Text(musicService.authorizationState.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            HStack(spacing: 14) {
                Button(t("Open Apple Music", "Apple Music 열기")) {
                    musicService.openMusicApp()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.accentPrimary)

                Spacer()

                if !musicService.isAuthorized {
                    Button(t("Request Media Access", "미디어 권한 요청")) {
                        musicService.requestMediaPermission()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.Colors.accentPrimary)
                }

                Button(t("Privacy Settings", "권한 설정")) {
                    musicService.openMediaPrivacySettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.accentPrimary)

                Button(t("Automation Settings", "자동화 설정")) {
                    musicService.openAutomationPrivacySettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.accentPrimary)

                Button(t("Refresh", "새로고침")) {
                    musicService.refresh()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.accentPrimary)
            }

            if let error = musicService.lastErrorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.mutedIndicator)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
        .onTapGesture {
            if !notchController.isPresented {
                notchController.show()
            }
            if !notchController.isExpanded {
                notchController.toggleExpanded()
            }
        }
    }

    private var islandControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Dynamic Bar (Notch)", "다이나믹 바 (노치)"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text(t("Use this panel to show, hide, and control the Dynamic Bar behavior.", "이 패널에서 다이나믹 바 표시/숨김과 동작 방식을 제어할 수 있습니다."))
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Hover Auto", "자동 제어"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(t("Expand on hover and collapse when leaving the area", "Hover 시 자동 확장, 아래로 벗어나면 자동 축소"))
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { notchController.isAutoControlEnabled },
                        set: { notchController.setAutoControlEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Pin Expanded State", "확장 상태 고정"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(t("Reopening keeps the expanded layout if enabled", "켜면 닫았다가 다시 열어도 확장 상태를 유지합니다"))
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { notchController.isExpansionPinned },
                        set: { notchController.setExpansionPinned($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Compact Song/Lyrics", "작은 화면 곡/가사 표시"))
                        .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(t("Shows artist/title and one lyric line in collapsed mode", "축소 화면에서 가수/제목과 가사 한 줄을 표시합니다"))
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { notchController.isCompactNowPlayingVisible },
                        set: { notchController.setCompactNowPlayingVisible($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Compact Playback Status", "작은 화면 재생 상태 표시"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(t("Shows the purple now-playing indicator in collapsed mode", "축소 화면에 보라색 재생 상태 표시를 보여줍니다"))
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { notchController.isCompactPlaybackStatusVisible },
                        set: { notchController.setCompactPlaybackStatusVisible($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                Button(notchController.isPresented ? t("Hide Bar", "바 숨기기") : t("Show Bar", "바 표시")) {
                    notchController.togglePresented()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(DesignTokens.Colors.accentPrimary.opacity(0.2)))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

                Button(t("Open Large View", "큰 화면 열기")) {
                    if !notchController.isPresented {
                        notchController.show()
                    }
                    if !notchController.isExpanded {
                        notchController.toggleExpanded()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    private var islandModulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Widget Modules", "위젯 모듈"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text(t("Customize module visibility and order for the Dynamic Bar.", "다이나믹 바 모듈의 표시 여부와 순서를 커스텀할 수 있습니다."))
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            ForEach(notchController.moduleOrder, id: \.self) { module in
                moduleToggleRow(
                    title: moduleTitle(module),
                    description: moduleDescription(module),
                    isOn: Binding(
                        get: { notchController.isModuleEnabled(module) },
                        set: { notchController.setModuleEnabled(module, isEnabled: $0) }
                    ),
                    canMoveUp: notchController.canMoveModule(module, direction: .up),
                    canMoveDown: notchController.canMoveModule(module, direction: .down),
                    onMoveUp: { notchController.moveModule(module, direction: .up) },
                    onMoveDown: { notchController.moveModule(module, direction: .down) }
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    private func moduleToggleRow(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)

            HStack(spacing: 6) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .opacity(canMoveUp ? 1 : 0.35)
                .disabled(!canMoveUp)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .opacity(canMoveDown ? 1 : 0.35)
                .disabled(!canMoveDown)
            }
        }
        .padding(.vertical, 2)
    }

    private func moduleTitle(_ module: NotchIslandController.IslandModule) -> String {
        switch module {
        case .music:
            return t("Music", "음악")
        case .files:
            return t("Files", "파일")
        case .time:
            return t("Time", "시간")
        }
    }

    private func moduleDescription(_ module: NotchIslandController.IslandModule) -> String {
        switch module {
        case .music:
            return t("Album art, progress, and controls", "앨범 아트, 진행바, 재생 제어")
        case .files:
            return t("AirDrop and temporary photo stash", "AirDrop + 사진 임시 보관함")
        case .time:
            return t("Reserved for future time/schedule cards", "추후 시간/일정 카드 확장용")
        }
    }

}
