import AudioToolbox
import os

/// CrossfadeError 열거형를 정의합니다.
enum CrossfadeError: LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case deviceNotReady
    case timeout
    case secondaryTapFailed
    case noTapDescription

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let status):
            return "Failed to create process tap: \(status)"
        case .aggregateCreationFailed(let status):
            return "Failed to create aggregate device: \(status)"
        case .deviceNotReady:
            return "Device not ready within timeout"
        case .timeout:
            return "Crossfade timed out"
        case .secondaryTapFailed:
            return "Secondary tap invalid after timeout"
        case .noTapDescription:
            return "No tap description available"
        }
    }
}

/// CrossfadeConfig 열거형를 정의합니다.
enum CrossfadeConfig {
    /// 기본 duration 값입니다.
    static let defaultDuration: TimeInterval = 0.050

    static var duration: TimeInterval {
        let custom = UserDefaults.standard.double(forKey: "diodiooodioCrossfadeDuration")
        return custom > 0 ? custom : defaultDuration
    }

    static func totalSamples(at sampleRate: Double) -> Int64 {
        Int64(sampleRate * duration)
    }
}

/// CrossfadeOrchestrator 열거형를 정의합니다.
enum CrossfadeOrchestrator {
    /// destroy 탭 동작을 처리합니다.
    static func destroyTap(
        aggregateID: AudioObjectID,
        deviceProcID: AudioDeviceIOProcID?,
        tapID: AudioObjectID
    ) {
        if aggregateID.isValid {
            AudioDeviceStop(aggregateID, deviceProcID)
            if let procID = deviceProcID {
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
        }
    }
}
