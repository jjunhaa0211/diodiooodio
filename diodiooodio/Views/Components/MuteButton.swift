import SwiftUI

/// MuteButton 구조체를 정의합니다.
struct MuteButton: View {
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        BaseMuteButton(
            isMuted: isMuted,
            mutedIcon: "speaker.slash.fill",
            unmutedIcon: "speaker.wave.2.fill",
            mutedHelp: "Unmute",
            unmutedHelp: "Mute",
            action: action
        )
    }
}

// MARK: - BaseMuteButton 정의

/// BaseMuteButton 구조체를 정의합니다.
private struct BaseMuteButton: View {
    let isMuted: Bool
    let mutedIcon: String
    let unmutedIcon: String
    let mutedHelp: String
    let unmutedHelp: String
    let action: () -> Void

    @State private var isPulsing = false
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? mutedIcon : unmutedIcon)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(buttonColor)
                .scaleEffect(isPulsing ? 1.1 : 1.0)
                .frame(
                    minWidth: DesignTokens.Dimensions.minTouchTarget,
                    minHeight: DesignTokens.Dimensions.minTouchTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(MuteButtonPressStyle())
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isMuted ? mutedHelp : unmutedHelp)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isPulsing)
        .animation(DesignTokens.Animation.hover, value: isHovered)
        .onChange(of: isMuted) { _, _ in
            isPulsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPulsing = false
            }
        }
    }

    private var buttonColor: Color {
        if isMuted {
            return DesignTokens.Colors.mutedIndicator
        } else if isHovered {
            return DesignTokens.Colors.interactiveHover
        } else {
            return DesignTokens.Colors.interactiveDefault
        }
    }
}

/// MuteButtonPressStyle 구조체를 정의합니다.
private struct MuteButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - 프리뷰

#Preview("Mute Button States") {
    ComponentPreviewContainer {
        HStack(spacing: DesignTokens.Spacing.lg) {
            VStack {
                MuteButton(isMuted: false) {}
                Text("Unmuted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                MuteButton(isMuted: true) {}
                Text("Muted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Mute Button Interactive") {
    struct InteractivePreview: View {
        @State private var isMuted = false

        var body: some View {
            ComponentPreviewContainer {
                VStack(spacing: DesignTokens.Spacing.md) {
                    MuteButton(isMuted: isMuted) {
                        isMuted.toggle()
                    }

                    Text(isMuted ? "Muted" : "Playing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    return InteractivePreview()
}
