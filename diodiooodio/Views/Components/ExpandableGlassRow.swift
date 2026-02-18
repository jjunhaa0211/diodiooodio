import SwiftUI

/// ExpandableGlassRow 구조체를 정의합니다.
struct ExpandableGlassRow<Header: View, ExpandedContent: View>: View {
    let isExpanded: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let expandedContent: () -> ExpandedContent

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header()

            if isExpanded {
                expandedContent()
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        )
                    )
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
                .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
                .strokeBorder(
                    isHovered ? DesignTokens.Colors.glassBorderHover : DesignTokens.Colors.glassBorder,
                    lineWidth: 0.5
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: Color.black.opacity(isHovered ? 0.18 : 0.10),
            radius: isHovered ? 8 : 5,
            x: 0,
            y: isHovered ? 4 : 2
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(DesignTokens.Animation.hover, value: isHovered)
    }
}

// MARK: - 프리뷰

#Preview("Expandable Glass Row - Collapsed") {
    PreviewContainer {
        ExpandableGlassRow(isExpanded: false) {
            HStack {
                Image(systemName: "music.note")
                Text("Spotify")
                Spacer()
                Text("75%")
                    .foregroundStyle(.secondary)
            }
            .frame(height: DesignTokens.Dimensions.rowContentHeight)
        } expandedContent: {
            VStack {
                Text("Expanded Content")
                    .padding()
            }
            .frame(height: 100)
            .background(DesignTokens.Colors.recessedBackground)
        }
    }
}

#Preview("Expandable Glass Row - Expanded") {
    PreviewContainer {
        ExpandableGlassRow(isExpanded: true) {
            HStack {
                Image(systemName: "music.note")
                Text("Spotify")
                Spacer()
                Text("75%")
                    .foregroundStyle(.secondary)
            }
            .frame(height: DesignTokens.Dimensions.rowContentHeight)
        } expandedContent: {
            VStack(spacing: 8) {
                Text("EQ Panel Content")
                HStack(spacing: 16) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary)
                            .frame(width: 4, height: 60)
                    }
                }
            }
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.xs)
        }
    }
}
