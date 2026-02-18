import AudioToolbox

/// AudioScope 열거형를 정의합니다.
enum AudioScope: Sendable {
    case global
    case input
    case output

    var propertyScope: AudioObjectPropertyScope {
        switch self {
        case .global: return kAudioObjectPropertyScopeGlobal
        case .input:  return kAudioObjectPropertyScopeInput
        case .output: return kAudioObjectPropertyScopeOutput
        }
    }
}
