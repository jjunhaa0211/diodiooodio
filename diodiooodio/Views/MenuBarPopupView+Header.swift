import SwiftUI

// MARK: - 기능: 상단 헤더

extension MenuBarPopupView {
    /// 상단 헤더 영역입니다.
    var topBar: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            if isSettingsOpen {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Audio Settings", "오디오 설정"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(t("Tune startup, gain limits, and routing behavior", "실행 옵션, 게인 한도, 라우팅 동작을 조정합니다"))
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            } else {
                headerIdentity
            }

            Spacer()
            settingsButton
        }
    }

    /// 앱 이름/현재 기본 출력 장치를 보여주는 식별 카드입니다.
    var headerIdentity: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("diodiooodio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(t("Audio-first app mixer", "오디오 중심 앱 믹서"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Spacer(minLength: 8)

            Label(defaultOutputDeviceName, systemImage: "hifispeaker.fill")
                .font(DesignTokens.Typography.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    /// 설정 화면 열기/닫기 버튼입니다.
    var settingsButton: some View {
        Button {
            toggleSettings()
        } label: {
            Image(systemName: isSettingsOpen ? "xmark" : "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Colors.interactiveDefault)
                .rotationEffect(.degrees(isSettingsOpen ? 90 : 0))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSettingsOpen)
    }
}
