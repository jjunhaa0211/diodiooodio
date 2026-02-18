import SwiftUI

// MARK: - 기능: 개요/메인 레이아웃

extension MenuBarPopupView {
    /// 설정 화면을 제외한 메인 콘텐츠입니다.
    @ViewBuilder
    var mainContent: some View {
        overviewBanner

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            SectionHeader(title: t("Output Devices", "출력 장치"))
            devicesSection
        }

        Divider()
            .padding(.vertical, DesignTokens.Spacing.xs)

        if displayableApps.isEmpty {
            emptyStateView
        } else {
            appsSection
        }

        Divider()
            .padding(.vertical, DesignTokens.Spacing.xs)

        quitButton
    }

    /// 현재 기본 출력 장치 이름입니다.
    var defaultOutputDeviceName: String {
        guard let uid = deviceVolumeMonitor.defaultDeviceUID,
              let device = sortedDevices.first(where: { $0.uid == uid }) else {
            return t("No Output", "출력 없음")
        }
        return device.name
    }

    /// 활성/고정 앱 개수 요약입니다.
    var appCountSummary: (active: Int, pinnedInactive: Int) {
        displayableApps.reduce(into: (active: 0, pinnedInactive: 0)) { summary, app in
            switch app {
            case .active:
                summary.active += 1
            case .pinnedInactive:
                summary.pinnedInactive += 1
            }
        }
    }

    /// 상단 메트릭 카드 영역입니다.
    var overviewBanner: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            metricCard(icon: "waveform", title: t("Active", "활성"), value: "\(appCountSummary.active)")
            metricCard(icon: "pin.fill", title: t("Pinned", "고정"), value: "\(appCountSummary.pinnedInactive)")
            metricCard(icon: "hifispeaker.2.fill", title: t("Outputs", "출력"), value: "\(sortedDevices.count)")
        }
    }

    /// 단일 메트릭 카드 컴포넌트입니다.
    func metricCard(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(DesignTokens.Typography.caption)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        }
    }

    /// 팝업 하단 종료 버튼입니다.
    var quitButton: some View {
        HStack(spacing: 8) {
            Button(t("Open MainUI", "MainUI 열기")) {
                openMainUI()
            }
            .buttonStyle(.plain)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .glassButtonStyle()

            Spacer(minLength: 0)

            Button(t("Quit diodiooodio", "diodiooodio 종료")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .glassButtonStyle()
        }
    }
}
