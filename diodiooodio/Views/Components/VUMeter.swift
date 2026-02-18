import SwiftUI

/// VUMeter 구조체를 정의합니다.
struct VUMeter: View {
    let level: Float
    var isMuted: Bool = false

    @State private var peakLevel: Float = 0
    @State private var peakHoldTimer: Timer?

    private let barCount = DesignTokens.Dimensions.vuMeterBarCount

    var body: some View {
        HStack(spacing: DesignTokens.Dimensions.vuMeterBarSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                VUMeterBar(
                    index: index,
                    level: level,
                    peakLevel: peakLevel,
                    barCount: barCount,
                    isMuted: isMuted
                )
            }
        }
        .frame(width: DesignTokens.Dimensions.vuMeterWidth)
        .onChange(of: level) { _, newLevel in
            if newLevel > peakLevel {
                peakLevel = newLevel
                startPeakDecayTimer()
            } else if peakLevel > newLevel && peakHoldTimer == nil {
                startPeakDecayTimer()
            }
        }
        .onDisappear {
            peakHoldTimer?.invalidate()
            peakHoldTimer = nil
        }
    }

    private func startPeakDecayTimer() {
        peakHoldTimer?.invalidate()
        peakHoldTimer = Timer.scheduledTimer(withTimeInterval: DesignTokens.Timing.vuMeterPeakHold, repeats: false) { [self] _ in
            startGradualDecay()
        }
    }

    private func startGradualDecay() {
        peakHoldTimer?.invalidate()
        peakHoldTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [self] timer in
            let decayRate: Float = 0.012
            if peakLevel > level {
                withAnimation(DesignTokens.Animation.vuMeterLevel) {
                    peakLevel = max(level, peakLevel - decayRate)
                }
            } else {
                timer.invalidate()
                peakHoldTimer = nil
            }
        }
    }
}

/// VUMeterBar 구조체를 정의합니다.
private struct VUMeterBar: View {
    let index: Int
    let level: Float
    let peakLevel: Float
    let barCount: Int
    var isMuted: Bool = false

    /// db thresholds 목록입니다.
    private static let dbThresholds: [Float] = [-40, -30, -20, -14, -10, -6, -3, 0]

    /// threshold 값입니다.
    private var threshold: Float {
        let db = Self.dbThresholds[min(index, Self.dbThresholds.count - 1)]
        return powf(10, db / 20)
    }

    /// lit 여부를 나타냅니다.
    private var isLit: Bool {
        level >= threshold
    }

    /// 피크 indicator 여부를 나타냅니다.
    private var isPeakIndicator: Bool {
        var peakBarIndex = 0
        for i in 0..<Self.dbThresholds.count {
            let thresh = powf(10, Self.dbThresholds[i] / 20)
            if peakLevel >= thresh {
                peakBarIndex = i
            }
        }
        return index == peakBarIndex && peakLevel > level
    }

    /// bar color 색상입니다.
    private var barColor: Color {
        if isMuted {
            return DesignTokens.Colors.vuMuted
        }
        if index < 4 {
            return DesignTokens.Colors.vuGreen
        } else if index < 6 {
            return DesignTokens.Colors.vuYellow
        } else if index < 7 {
            return DesignTokens.Colors.vuOrange
        } else {
            return DesignTokens.Colors.vuRed
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(isLit || isPeakIndicator ? barColor : DesignTokens.Colors.vuUnlit)
            .frame(
                width: (DesignTokens.Dimensions.vuMeterWidth - CGFloat(barCount - 1) * DesignTokens.Dimensions.vuMeterBarSpacing) / CGFloat(barCount),
                height: DesignTokens.Dimensions.vuMeterBarHeight
            )
            .animation(DesignTokens.Animation.vuMeterLevel, value: isLit)
    }
}

// MARK: - 프리뷰

#Preview("VU Meter - Horizontal") {
    ComponentPreviewContainer {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("0%")
                    .font(.caption)
                VUMeter(level: 0)
            }

            HStack {
                Text("25%")
                    .font(.caption)
                VUMeter(level: 0.25)
            }

            HStack {
                Text("50%")
                    .font(.caption)
                VUMeter(level: 0.5)
            }

            HStack {
                Text("75%")
                    .font(.caption)
                VUMeter(level: 0.75)
            }

            HStack {
                Text("100%")
                    .font(.caption)
                VUMeter(level: 1.0)
            }
        }
    }
}

#Preview("VU Meter - Animated") {
    struct AnimatedPreview: View {
        @State private var level: Float = 0

        var body: some View {
            ComponentPreviewContainer {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    VUMeter(level: level)

                    Slider(value: Binding(
                        get: { Double(level) },
                        set: { level = Float($0) }
                    ))
                }
            }
        }
    }
    return AnimatedPreview()
}
