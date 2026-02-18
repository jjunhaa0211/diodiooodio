import AppKit
import AudioToolbox

// MARK: - AudioDeviceID 정의

extension AudioDeviceID {
    func isAggregateDevice() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyClass,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var classID: AudioClassID = 0
        var size = UInt32(MemoryLayout<AudioClassID>.size)
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &classID)
        guard err == noErr else { return false }
        return classID == kAudioAggregateDeviceClassID
    }

    func isVirtualDevice() -> Bool {
        readTransportType() == .virtual
    }
}

// MARK: - AudioDeviceID 정의

extension AudioDeviceID {
    func readDeviceIcon() -> NSImage? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIcon,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        var iconURL: Unmanaged<CFURL>?
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &iconURL)

        guard err == noErr, let url = iconURL?.takeRetainedValue() as URL? else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    /// suggested 아이콘 symbol 동작을 처리합니다.
    func suggestedIconSymbol() -> String {
        let name = (try? readDeviceName()) ?? ""
        let transport = readTransportType()

        if name.contains("AirPods Pro") { return "airpodspro" }
        if name.contains("AirPods Max") { return "airpodsmax" }
        if name.contains("AirPods") { return "airpods.gen3" }

        if name.contains("HomePod mini") { return "homepodmini" }
        if name.contains("HomePod") { return "homepod" }

        if name.contains("Apple TV") { return "appletv" }

        if name.contains("Beats") { return "beats.headphones" }

        return transport.defaultIconSymbol
    }

}
