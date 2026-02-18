import CoreAudio
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: AudioControlViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output Device")
                .font(.headline)

            Picker(
                "Output Device",
                selection: Binding(
                    get: { viewModel.selectedOutputDeviceID },
                    set: { viewModel.setDefaultOutputDevice($0) }
                )
            ) {
                ForEach(viewModel.devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("System Volume")
                    Spacer()
                    Text("\(Int(viewModel.systemVolume * 100))")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.systemVolume) },
                        set: { viewModel.setSystemVolume(Float($0)) }
                    ),
                    in: 0 ... 1
                )
            }

            Divider()

            Text("Audio Devices")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.devices) { device in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: device.isDefault ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(device.isDefault ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(device.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 140)

            Divider()

            Text("Active Apps (MVP model)")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.activeApps) { app in
                        AppRowView(
                            app: app,
                            devices: viewModel.devices,
                            onVolumeChange: { value in
                                viewModel.setAppVolume(bundleId: app.bundleId, value: value)
                            },
                            onMuteToggle: {
                                viewModel.toggleMute(bundleId: app.bundleId)
                            },
                            onRouteChange: { deviceID in
                                viewModel.setRoute(bundleId: app.bundleId, deviceID: deviceID)
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: 220)

            if let lastErrorMessage = viewModel.lastErrorMessage {
                Divider()
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(width: 380)
    }
}

private struct AppRowView: View {
    let app: AppAudioTarget
    let devices: [AudioDevice]
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void
    let onRouteChange: (AudioDeviceID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(app.appName)
                    .font(.subheadline)
                Spacer()
                Button(app.isMuted ? "Unmute" : "Mute") {
                    onMuteToggle()
                }
                .buttonStyle(.bordered)
            }

            Slider(
                value: Binding(
                    get: { Double(app.volume) },
                    set: { onVolumeChange(Float($0)) }
                ),
                in: 0 ... 1
            )

            Picker(
                "Route",
                selection: Binding<AudioDeviceID?>(
                    get: { app.routedDeviceId },
                    set: { onRouteChange($0) }
                )
            ) {
                Text("System Default").tag(Optional<AudioDeviceID>.none)
                ForEach(devices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
