import SwiftUI

/// 오디오 탭 본문입니다.
struct AudioTabContentView: View {
    @Bindable var audioEngine: AudioEngine
    let language: AppLanguage

    private func t(_ english: String, _ korean: String) -> String {
        language.text(english, korean)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                quickStatCards
                activeAppsCard
            }
            .padding(20)
        }
    }

    private var quickStatCards: some View {
        HStack(spacing: 12) {
            statCard(
                title: t("Active Apps", "활성 앱"),
                value: "\(audioEngine.apps.count)",
                icon: "waveform"
            )
            statCard(
                title: t("Output Devices", "출력 장치"),
                value: "\(audioEngine.outputDevices.count)",
                icon: "hifispeaker.2.fill"
            )
            statCard(
                title: t("Pinned Apps", "고정 앱"),
                value: "\(audioEngine.displayableApps.filter { if case .pinnedInactive = $0 { return true } ; return false }.count)",
                icon: "pin.fill"
            )
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    private var activeAppsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Active Apps", "활성 앱"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            if audioEngine.apps.isEmpty {
                Text(t("No apps are currently playing audio.", "현재 오디오를 재생하는 앱이 없습니다."))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            } else {
                ForEach(audioEngine.apps, id: \.id) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text(app.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        Spacer()
                        Text("\(Int(audioEngine.getVolume(for: app) * 100))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }
}
