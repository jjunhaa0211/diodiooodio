import SwiftUI
import AppKit

/// VisualEffectBackground 구조체를 정의합니다.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Color 정의

extension Color {
    /// popup background overlay 색상입니다.
    static var popupBackgroundOverlay: Color { DesignTokens.Colors.popupOverlay }
}

// MARK: - View 정의

extension View {
    /// dark glass background 동작을 처리합니다.
    func darkGlassBackground() -> some View {
        self
            .background {
                ZStack {
                    VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Color.popupBackgroundOverlay.opacity(0.45)
                }
            }
    }

    /// EQ panel background 동작을 처리합니다.
    func eqPanelBackground() -> some View {
        modifier(EQPanelBackgroundModifier())
    }
}

// MARK: - EQPanelBackgroundModifier 정의

/// EQPanelBackgroundModifier 구조체를 정의합니다.
struct EQPanelBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Dimensions.buttonRadius)
                    .fill(DesignTokens.Colors.recessedBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Dimensions.buttonRadius)
                    .strokeBorder(DesignTokens.Colors.glassBorder, lineWidth: 0.5)
            }
    }
}

// MARK: - 프리뷰

#Preview("Dark Glass Popup Background") {
    VStack(spacing: 16) {
        Text("OUTPUT DEVICES")
            .sectionHeaderStyle()
        Text("Dark frosted glass background")
            .foregroundStyle(.primary)
    }
    .padding(DesignTokens.Spacing.lg)
    .frame(width: 300)
    .darkGlassBackground()
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Dimensions.cornerRadius))
    .environment(\.colorScheme, .dark)
}

#Preview("EQ Panel - Recessed") {
    VStack(spacing: 8) {
        Text("EQ Panel - Recessed")
            .foregroundStyle(.secondary)
        HStack {
            ForEach(0..<5) { _ in
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 20, height: 60)
            }
        }
    }
    .padding()
    .eqPanelBackground()
    .padding()
    .darkGlassBackground()
    .environment(\.colorScheme, .dark)
}
