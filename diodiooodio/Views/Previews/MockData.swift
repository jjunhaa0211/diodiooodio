import AppKit
import AudioToolbox

/// MockData 열거형를 정의합니다.
enum MockData {

    // MARK: - sample 앱 목록

    static let sampleApps: [AudioApp] = [
        AudioApp(
            id: 1001,
            objectID: AudioObjectID(1001),
            name: "Spotify",
            icon: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage(),
            bundleID: "com.spotify.client"
        ),
        AudioApp(
            id: 1002,
            objectID: AudioObjectID(1002),
            name: "Chrome",
            icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage(),
            bundleID: "com.google.Chrome"
        ),
        AudioApp(
            id: 1003,
            objectID: AudioObjectID(1003),
            name: "Zoom",
            icon: NSImage(systemSymbolName: "video", accessibilityDescription: nil) ?? NSImage(),
            bundleID: "us.zoom.xos"
        ),
        AudioApp(
            id: 1004,
            objectID: AudioObjectID(1004),
            name: "Discord",
            icon: NSImage(systemSymbolName: "message", accessibilityDescription: nil) ?? NSImage(),
            bundleID: "com.hnc.Discord"
        ),
        AudioApp(
            id: 1005,
            objectID: AudioObjectID(1005),
            name: "Music",
            icon: NSImage(systemSymbolName: "music.quarternote.3", accessibilityDescription: nil) ?? NSImage(),
            bundleID: "com.apple.Music"
        )
    ]

    // MARK: - sample 장치 목록

    static let sampleDevices: [AudioDevice] = [
        AudioDevice(
            id: AudioDeviceID(100),
            uid: "BuiltInSpeakerDevice",
            name: "MacBook Pro Speakers",
            icon: NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil)
        ),
        AudioDevice(
            id: AudioDeviceID(101),
            uid: "AirPodsProDevice",
            name: "AirPods Pro",
            icon: NSImage(systemSymbolName: "airpodspro", accessibilityDescription: nil)
        ),
        AudioDevice(
            id: AudioDeviceID(102),
            uid: "HDMIDisplayDevice",
            name: "LG UltraFine Display",
            icon: NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        ),
        AudioDevice(
            id: AudioDeviceID(103),
            uid: "HomePodDevice",
            name: "Living Room HomePod",
            icon: NSImage(systemSymbolName: "homepod", accessibilityDescription: nil)
        )
    ]

    // MARK: - 기본 장치

    static var defaultDevice: AudioDevice {
        sampleDevices[0]
    }

    // MARK: - sample 볼륨

    static let sampleVolumes: [pid_t: Float] = [
        1001: 0.75,
        1002: 1.0,
        1003: 0.5,
        1004: 0.85,
        1005: 0.6
    ]

    // MARK: - sample 오디오

    static let sampleAudioLevels: [pid_t: Float] = [
        1001: 0.65,
        1002: 0.0,
        1003: 0.35,
        1004: 0.45,
        1005: 0.55
    ]

    // MARK: - random 볼륨

    static func randomVolume() -> Float {
        Float.random(in: 0...1)
    }

    static func randomAudioLevel() -> Float {
        Float.random(in: 0...0.8)
    }
}
