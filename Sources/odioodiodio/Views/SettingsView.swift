import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AudioControlViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Odio Settings")
                .font(.title2.bold())

            GroupBox("Engine Status") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.engineStatus)
                    Text("MVP: Menu bar, output device switch, system volume control")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Advanced (planned): Virtual device + System Extension for per-app routing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Current Device") {
                let current = viewModel.devices.first(where: { $0.id == viewModel.selectedOutputDeviceID })
                VStack(alignment: .leading, spacing: 4) {
                    Text(current?.name ?? "Unknown")
                    Text(current?.detailText ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(18)
        .frame(minWidth: 420, minHeight: 260)
    }
}
