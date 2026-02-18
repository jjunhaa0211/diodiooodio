import SwiftUI

/// DeviceRow 구조체를 정의합니다.
struct DeviceRow: View {
    let device: AudioDevice
    let isDefault: Bool
    let volume: Float
    let isMuted: Bool
    let onSetDefault: () -> Void
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    @State private var sliderValue: Double
    @State private var isEditing = false

    /// 표시 음소거 아이콘 상태를 나타냅니다.
    private var showMutedIcon: Bool { isMuted || sliderValue == 0 }

    /// 기본 unmute 볼륨 값입니다.
    private let defaultUnmuteVolume: Double = 0.5

    init(
        device: AudioDevice,
        isDefault: Bool,
        volume: Float,
        isMuted: Bool,
        onSetDefault: @escaping () -> Void,
        onVolumeChange: @escaping (Float) -> Void,
        onMuteToggle: @escaping () -> Void
    ) {
        self.device = device
        self.isDefault = isDefault
        self.volume = volume
        self.isMuted = isMuted
        self.onSetDefault = onSetDefault
        self.onVolumeChange = onVolumeChange
        self.onMuteToggle = onMuteToggle
        self._sliderValue = State(initialValue: Double(volume))
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            RadioButton(isSelected: isDefault, action: onSetDefault)

            Group {
                if let icon = device.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "speaker.wave.2")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: DesignTokens.Dimensions.iconSize, height: DesignTokens.Dimensions.iconSize)

            Text(device.name)
                .font(isDefault ? DesignTokens.Typography.rowNameBold : DesignTokens.Typography.rowName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            MuteButton(isMuted: showMutedIcon) {
                if showMutedIcon {
                    if sliderValue == 0 {
                        sliderValue = defaultUnmuteVolume
                    }
                    if isMuted {
                        onMuteToggle()
                    }
                } else {
                    onMuteToggle()
                }
            }

            LiquidGlassSlider(
                value: $sliderValue,
                onEditingChanged: { editing in
                    isEditing = editing
                }
            )
            .opacity(showMutedIcon ? 0.5 : 1.0)
            .onChange(of: sliderValue) { _, newValue in
                onVolumeChange(Float(newValue))
                if isMuted && newValue > 0 {
                    onMuteToggle()
                }
            }

            EditablePercentage(
                percentage: Binding(
                    get: { Int(round(sliderValue * 100)) },
                    set: { sliderValue = Double($0) / 100.0 }
                ),
                range: 0...100
            )
        }
        .frame(height: DesignTokens.Dimensions.rowContentHeight)
        .hoverableRow()
        .onChange(of: volume) { _, newValue in
            guard !isEditing else { return }
            sliderValue = Double(newValue)
        }
    }
}

// MARK: - 프리뷰

#Preview("Device Row - Default") {
    PreviewContainer {
        VStack(spacing: 0) {
            DeviceRow(
                device: MockData.sampleDevices[0],
                isDefault: true,
                volume: 0.75,
                isMuted: false,
                onSetDefault: {},
                onVolumeChange: { _ in },
                onMuteToggle: {}
            )

            DeviceRow(
                device: MockData.sampleDevices[1],
                isDefault: false,
                volume: 1.0,
                isMuted: false,
                onSetDefault: {},
                onVolumeChange: { _ in },
                onMuteToggle: {}
            )

            DeviceRow(
                device: MockData.sampleDevices[2],
                isDefault: false,
                volume: 0.5,
                isMuted: true,
                onSetDefault: {},
                onVolumeChange: { _ in },
                onMuteToggle: {}
            )
        }
    }
}
