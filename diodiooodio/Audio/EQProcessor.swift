import Foundation
import Accelerate
import os

/// EQProcessor 클래스를 정의합니다.
final class EQProcessor: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.diodiooodio.audio", category: "EQProcessor")

    /// delay buffer size 값입니다.
    private static let delayBufferSize = (2 * EQSettings.bandCount) + 2  // 22

    private var sampleRate: Double

    /// 현재 설정 값입니다.
    private var _currentSettings: EQSettings?

    /// 현재 설정 값입니다.
    var currentSettings: EQSettings? { _currentSettings }

    private nonisolated(unsafe) var _eqSetup: vDSP_biquad_Setup?
    private nonisolated(unsafe) var _isEnabled: Bool = true

    private let delayBufferL: UnsafeMutablePointer<Float>
    private let delayBufferR: UnsafeMutablePointer<Float>

    /// 활성화 여부를 나타냅니다.
    var isEnabled: Bool {
        get { _isEnabled }
    }

    init(sampleRate: Double) {
        self.sampleRate = sampleRate

        delayBufferL = UnsafeMutablePointer<Float>.allocate(capacity: Self.delayBufferSize)
        delayBufferL.initialize(repeating: 0, count: Self.delayBufferSize)

        delayBufferR = UnsafeMutablePointer<Float>.allocate(capacity: Self.delayBufferSize)
        delayBufferR.initialize(repeating: 0, count: Self.delayBufferSize)

        updateSettings(EQSettings.flat)
    }

    deinit {
        if let setup = _eqSetup {
            vDSP_biquad_DestroySetup(setup)
        }
        delayBufferL.deallocate()
        delayBufferR.deallocate()
    }

    /// 설정을(를) 갱신합니다
    func updateSettings(_ settings: EQSettings) {
        _isEnabled = settings.isEnabled
        _currentSettings = settings

        let coefficients = BiquadMath.coefficientsForAllBands(
            gains: settings.clampedGains,
            sampleRate: sampleRate
        )

        let newSetup = coefficients.withUnsafeBufferPointer { ptr in
            vDSP_biquad_CreateSetup(ptr.baseAddress!, vDSP_Length(EQSettings.bandCount))
        }

        let oldSetup = _eqSetup
        _eqSetup = newSetup

        if let old = oldSetup {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
                vDSP_biquad_DestroySetup(old)
            }
        }

    }

    /// 샘플 rate을(를) 갱신합니다
    func updateSampleRate(_ newRate: Double) {
        dispatchPrecondition(condition: .onQueue(.main))
        let oldRate = sampleRate
        guard newRate != sampleRate else { return }
        guard let settings = _currentSettings else {
            sampleRate = newRate
            logger.info("[EQ] Sample rate updated: \(oldRate, format: .fixed(precision: 0))Hz → \(newRate, format: .fixed(precision: 0))Hz")
            return
        }

        sampleRate = newRate
        logger.info("[EQ] Sample rate updated: \(oldRate, format: .fixed(precision: 0))Hz → \(newRate, format: .fixed(precision: 0))Hz")

        let coefficients = BiquadMath.coefficientsForAllBands(
            gains: settings.clampedGains,
            sampleRate: newRate
        )

        let newSetup = coefficients.withUnsafeBufferPointer { ptr in
            vDSP_biquad_CreateSetup(ptr.baseAddress!, vDSP_Length(EQSettings.bandCount))
        }

        let oldSetup = _eqSetup
        _eqSetup = newSetup

        if let old = oldSetup {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
                vDSP_biquad_DestroySetup(old)
            }
        }

        memset(delayBufferL, 0, Self.delayBufferSize * MemoryLayout<Float>.size)
        memset(delayBufferR, 0, Self.delayBufferSize * MemoryLayout<Float>.size)
    }

    /// 처리 동작을 처리합니다.
    func process(input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, frameCount: Int) {
        let enabled = _isEnabled
        let setup = _eqSetup

        guard enabled, let setup = setup else {
            memcpy(output, input, frameCount * 2 * MemoryLayout<Float>.size)
            return
        }

        memcpy(output, input, frameCount * 2 * MemoryLayout<Float>.size)

        vDSP_biquad(
            setup,
            delayBufferL,
            output,
            2,
            output,
            2,
            vDSP_Length(frameCount)
        )

        vDSP_biquad(
            setup,
            delayBufferR,
            output.advanced(by: 1),
            2,
            output.advanced(by: 1),
            2,
            vDSP_Length(frameCount)
        )
    }
}
