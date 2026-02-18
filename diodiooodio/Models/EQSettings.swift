import Foundation

struct EQSettings: Codable, Equatable {
    static let bandCount = 10
    static let maxGainDB: Float = 12.0
    static let minGainDB: Float = -12.0

    /// frequencies 목록입니다.
    static let frequencies: [Double] = [
        31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]

    /// band gains 목록입니다.
    var bandGains: [Float]

    /// 활성화 여부를 나타냅니다.
    var isEnabled: Bool

    init(bandGains: [Float] = Array(repeating: 0, count: 10), isEnabled: Bool = true) {
        self.bandGains = bandGains
        self.isEnabled = isEnabled
    }

    /// clamped gains 목록입니다.
    var clampedGains: [Float] {
        bandGains.map { max(Self.minGainDB, min(Self.maxGainDB, $0)) }
    }

    /// flat 값입니다.
    static let flat = EQSettings()
}
