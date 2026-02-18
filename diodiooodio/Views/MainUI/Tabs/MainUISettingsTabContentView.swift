import SwiftUI

/// MainUI 내 총괄 설정 탭입니다.
struct MainUISettingsTabContentView: View {
    @Binding var settings: AppSettings
    @Bindable var notchController: NotchIslandController

    private var language: AppLanguage { settings.language }

    private func t(_ english: String, _ korean: String) -> String {
        language.text(english, korean)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewCard
                dynamicBarBehaviorCard
                moduleOrderCard
            }
            .padding(20)
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Overall Settings", "총괄 세팅"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text(t("Language changes are reflected immediately in the MainUI and widgets.", "언어를 바꾸면 MainUI와 위젯 문구에 즉시 반영됩니다."))
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            HStack {
                Text(t("Language", "언어"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            HStack {
                Text(t("Launch at Login", "로그인 시 자동 실행"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: $settings.launchAtLogin)
                    .labelsHidden()
            }
        }
        .cardShell()
    }

    private var dynamicBarBehaviorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Dynamic Bar Behavior", "다이나믹 바 동작"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            behaviorRow(
                title: t("Hover Auto Expand/Collapse", "호버 자동 확장/축소"),
                description: t("Expands on hover and collapses when the pointer leaves.", "마우스를 올리면 확장되고 벗어나면 축소됩니다."),
                toggle: Binding(
                    get: { notchController.isAutoControlEnabled },
                    set: { notchController.setAutoControlEnabled($0) }
                )
            )

            behaviorRow(
                title: t("Pin Expanded Layout", "확장 화면 고정"),
                description: t("When enabled, reopening keeps the bar expanded.", "켜두면 닫았다 다시 열어도 확장 상태를 유지합니다."),
                toggle: Binding(
                    get: { notchController.isExpansionPinned },
                    set: { notchController.setExpansionPinned($0) }
                )
            )

            behaviorRow(
                title: t("Show Compact Song/Lyrics", "작은 화면 곡/가사 표시"),
                description: t("Shows artist/title and lyric line in the collapsed Dynamic Bar.", "축소된 다이나믹 바에 가수/제목과 가사 한 줄을 표시합니다."),
                toggle: Binding(
                    get: { notchController.isCompactNowPlayingVisible },
                    set: { notchController.setCompactNowPlayingVisible($0) }
                )
            )

            behaviorRow(
                title: t("Show Compact Playback Status", "작은 화면 재생 상태 표시"),
                description: t("Shows the purple now-playing indicator in the collapsed Dynamic Bar.", "축소된 다이나믹 바에 보라색 재생 상태 표시를 보여줍니다."),
                toggle: Binding(
                    get: { notchController.isCompactPlaybackStatusVisible },
                    set: { notchController.setCompactPlaybackStatusVisible($0) }
                )
            )
        }
        .cardShell()
    }

    private var moduleOrderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Widget Order", "위젯 순서"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text(t("Drag rows to reorder modules. The top item becomes the default first widget.", "행을 드래그해 순서를 바꿀 수 있습니다. 맨 위 모듈이 기본 첫 위젯이 됩니다."))
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            List {
                ForEach(notchController.moduleOrder, id: \.self) { module in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)

                        Label(moduleTitle(module), systemImage: moduleIcon(module))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        Spacer()

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { notchController.isModuleEnabled(module) },
                                set: { notchController.setModuleEnabled(module, isEnabled: $0) }
                            )
                        )
                        .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    notchController.moveModules(from: from, to: to)
                }
            }
            .listStyle(.plain)
            .frame(height: 150)
            .scrollContentBackground(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
            )
        }
        .cardShell()
    }

    private func behaviorRow(title: String, description: String, toggle: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: toggle)
                .labelsHidden()
        }
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

    private func moduleIcon(_ module: NotchIslandController.IslandModule) -> String {
        switch module {
        case .music:
            return "music.note"
        case .files:
            return "folder"
        case .time:
            return "clock"
        }
    }
}

private extension View {
    func cardShell() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
            )
    }
}
