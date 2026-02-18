import CoreAudio
import Foundation

struct AppAudioTarget: Identifiable, Hashable {
    let bundleId: String
    var appName: String
    var volume: Float
    var isMuted: Bool
    var routedDeviceId: AudioDeviceID?

    var id: String { bundleId }
}
