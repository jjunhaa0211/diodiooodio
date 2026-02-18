import SwiftUI

// MARK: - 기능: 앱 믹서

extension MenuBarPopupView {
    /// 재생 중인 앱이 없을 때 보여주는 빈 상태 뷰입니다.
    @ViewBuilder
    var emptyStateView: some View {
        HStack {
            Spacer()
            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "speaker.slash")
                    .font(.title)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(t("No apps playing audio", "재생 중인 앱이 없습니다"))
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(t("Start music or video to control it here", "음악이나 영상을 재생하면 여기서 제어할 수 있어요"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.xl)
    }

    /// 앱 믹서 섹션 루트입니다.
    @ViewBuilder
    var appsSection: some View {
        HStack {
            SectionHeader(title: t("App Mixer", "앱 믹서"))
            Spacer()
            Text(t("Per-app volume, mute, routing, EQ", "앱별 볼륨, 음소거, 라우팅, EQ"))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(.bottom, DesignTokens.Spacing.xs)

        ScrollViewReader { scrollProxy in
            if displayableApps.count > Layout.appScrollThreshold {
                ScrollView {
                    appsContent(scrollProxy: scrollProxy)
                }
                .scrollIndicators(.never)
                .frame(height: Layout.appScrollHeight)
            } else {
                appsContent(scrollProxy: scrollProxy)
            }
        }
    }

    /// 활성/비활성 앱 행을 공통 컨테이너에서 렌더링합니다.
    func appsContent(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            ForEach(displayableApps) { displayableApp in
                switch displayableApp {
                case .active(let app):
                    activeAppRow(app: app, displayableApp: displayableApp, scrollProxy: scrollProxy)
                case .pinnedInactive(let info):
                    inactiveAppRow(info: info, displayableApp: displayableApp, scrollProxy: scrollProxy)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 활성 앱 행을 생성합니다.
    @ViewBuilder
    func activeAppRow(app: AudioApp, displayableApp: DisplayableApp, scrollProxy: ScrollViewProxy) -> some View {
        if let deviceUID = audioEngine.getDeviceUID(for: app) {
            AppRowWithLevelPolling(
                app: app,
                volume: audioEngine.getVolume(for: app),
                isMuted: audioEngine.getMute(for: app),
                devices: audioEngine.outputDevices,
                selectedDeviceUID: deviceUID,
                selectedDeviceUIDs: audioEngine.getSelectedDeviceUIDs(for: app),
                isFollowingDefault: audioEngine.isFollowingDefault(for: app),
                defaultDeviceUID: deviceVolumeMonitor.defaultDeviceUID,
                deviceSelectionMode: audioEngine.getDeviceSelectionMode(for: app),
                maxVolumeBoost: audioEngine.settingsManager.appSettings.maxVolumeBoost,
                isPinned: audioEngine.isPinned(app),
                getAudioLevel: { audioEngine.getAudioLevel(for: app) },
                isPopupVisible: isPopupVisible,
                onVolumeChange: { volume in
                    audioEngine.setVolume(for: app, to: volume)
                },
                onMuteChange: { muted in
                    audioEngine.setMute(for: app, to: muted)
                },
                onDeviceSelected: { newDeviceUID in
                    audioEngine.setDevice(for: app, deviceUID: newDeviceUID)
                },
                onDevicesSelected: { uids in
                    audioEngine.setSelectedDeviceUIDs(for: app, to: uids)
                },
                onDeviceModeChange: { mode in
                    audioEngine.setDeviceSelectionMode(for: app, to: mode)
                },
                onSelectFollowDefault: {
                    audioEngine.setDevice(for: app, deviceUID: nil)
                },
                onAppActivate: {
                    activateApp(pid: app.id, bundleID: app.bundleID)
                },
                onPinToggle: {
                    if audioEngine.isPinned(app) {
                        audioEngine.unpinApp(app.persistenceIdentifier)
                    } else {
                        audioEngine.pinApp(app)
                    }
                },
                eqSettings: audioEngine.getEQSettings(for: app),
                onEQChange: { settings in
                    audioEngine.setEQSettings(settings, for: app)
                },
                isEQExpanded: expandedEQAppID == displayableApp.id,
                onEQToggle: {
                    toggleEQ(for: displayableApp.id, scrollProxy: scrollProxy)
                }
            )
            .id(displayableApp.id)
        }
    }

    /// 비활성(고정) 앱 행을 생성합니다.
    @ViewBuilder
    func inactiveAppRow(info: PinnedAppInfo, displayableApp: DisplayableApp, scrollProxy: ScrollViewProxy) -> some View {
        let identifier = info.persistenceIdentifier
        InactiveAppRow(
            appInfo: info,
            icon: displayableApp.icon,
            volume: audioEngine.getVolumeForInactive(identifier: identifier),
            devices: audioEngine.outputDevices,
            selectedDeviceUID: audioEngine.getDeviceRoutingForInactive(identifier: identifier),
            selectedDeviceUIDs: audioEngine.getSelectedDeviceUIDsForInactive(identifier: identifier),
            isFollowingDefault: audioEngine.isFollowingDefaultForInactive(identifier: identifier),
            defaultDeviceUID: deviceVolumeMonitor.defaultDeviceUID,
            deviceSelectionMode: audioEngine.getDeviceSelectionModeForInactive(identifier: identifier),
            isMuted: audioEngine.getMuteForInactive(identifier: identifier),
            maxVolumeBoost: audioEngine.settingsManager.appSettings.maxVolumeBoost,
            onVolumeChange: { volume in
                audioEngine.setVolumeForInactive(identifier: identifier, to: volume)
            },
            onMuteChange: { muted in
                audioEngine.setMuteForInactive(identifier: identifier, to: muted)
            },
            onDeviceSelected: { newDeviceUID in
                audioEngine.setDeviceRoutingForInactive(identifier: identifier, deviceUID: newDeviceUID)
            },
            onDevicesSelected: { uids in
                audioEngine.setSelectedDeviceUIDsForInactive(identifier: identifier, to: uids)
            },
            onDeviceModeChange: { mode in
                audioEngine.setDeviceSelectionModeForInactive(identifier: identifier, to: mode)
            },
            onSelectFollowDefault: {
                audioEngine.setDeviceRoutingForInactive(identifier: identifier, deviceUID: nil)
            },
            onUnpin: {
                audioEngine.unpinApp(identifier)
            },
            eqSettings: audioEngine.getEQSettingsForInactive(identifier: identifier),
            onEQChange: { settings in
                audioEngine.setEQSettingsForInactive(settings, identifier: identifier)
            },
            isEQExpanded: expandedEQAppID == displayableApp.id,
            onEQToggle: {
                toggleEQ(for: displayableApp.id, scrollProxy: scrollProxy)
            }
        )
        .id(displayableApp.id)
    }

    /// EQ 패널 확장 상태를 앱 단위로 토글합니다.
    func toggleEQ(for appID: String, scrollProxy: ScrollViewProxy) {
        guard !isEQAnimating else { return }
        isEQAnimating = true

        let isExpanding = expandedEQAppID != appID
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            expandedEQAppID = (expandedEQAppID == appID) ? nil : appID
            if isExpanding {
                scrollProxy.scrollTo(appID, anchor: .top)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isEQAnimating = false
        }
    }

    /// 앱을 전면으로 올리고 최소화된 창이 있으면 복원합니다.
    func activateApp(pid: pid_t, bundleID: String?) {
        NSWorkspace.shared.runningApplications
            .first { $0.processIdentifier == pid }?
            .activate()

        if let bundleID {
            let script = NSAppleScript(source: """
                tell application id "\(bundleID)"
                    reopen
                    activate
                end tell
                """)
            script?.executeAndReturnError(nil)
        }
    }
}
