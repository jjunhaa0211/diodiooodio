import SwiftUI

// MARK: - 기능: 출력 장치 제어

extension MenuBarPopupView {
    /// 출력 장치 섹션입니다. 장치 수가 많으면 스크롤을 활성화합니다.
    @ViewBuilder
    var devicesSection: some View {
        if sortedDevices.count > Layout.deviceScrollThreshold {
            ScrollView {
                devicesContent
            }
            .scrollIndicators(.never)
            .frame(height: Layout.deviceScrollHeight)
        } else {
            devicesContent
        }
    }

    /// 장치 행 목록입니다.
    var devicesContent: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(sortedDevices) { device in
                DeviceRow(
                    device: device,
                    isDefault: device.id == deviceVolumeMonitor.defaultDeviceID,
                    volume: deviceVolumeMonitor.volumes[device.id] ?? 1.0,
                    isMuted: deviceVolumeMonitor.muteStates[device.id] ?? false,
                    onSetDefault: {
                        deviceVolumeMonitor.setDefaultDevice(device.id)
                    },
                    onVolumeChange: { volume in
                        deviceVolumeMonitor.setVolume(for: device.id, to: volume)
                    },
                    onMuteToggle: {
                        let currentMute = deviceVolumeMonitor.muteStates[device.id] ?? false
                        deviceVolumeMonitor.setMute(for: device.id, to: !currentMute)
                    }
                )
            }
        }
    }

    /// 엔진에서 전달된 장치 목록을 UI 표시용으로 정렬합니다.
    func updateSortedDevices() {
        sortedDevices = audioEngine.outputDevices.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
