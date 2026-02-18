import AudioToolbox
import CoreFoundation

// MARK: - AudioObjectID 정의

extension AudioObjectID {
    /// 장치 alive 여부를 반환합니다.
    func isDeviceAlive() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isAlive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &isAlive)
        return status == noErr && isAlive != 0
    }

    /// wait until ready 동작을 처리합니다.
    func waitUntilReady(timeout: TimeInterval = 1.0, pollInterval: TimeInterval = 0.01) -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout

        while CFAbsoluteTimeGetCurrent() < deadline {
            if isDeviceAlive() {
                return true
            }
            CFRunLoopRunInMode(.defaultMode, pollInterval, false)
        }

        return false
    }

    /// valid 출력 streams 여부를 반환합니다.
    func hasValidOutputStreams() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size)
        return status == noErr && size > UInt32(MemoryLayout<AudioBufferList>.size)
    }
}
