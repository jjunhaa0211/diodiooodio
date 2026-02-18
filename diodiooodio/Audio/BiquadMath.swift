import Foundation

/// BiquadMath 열거형를 정의합니다.
enum BiquadMath {
    /// graphic eqq 값입니다.
    static let graphicEQQ: Double = 1.4

    /// peaking eqcoefficients 동작을 처리합니다.
    static func peakingEQCoefficients(
        frequency: Double,
        gainDB: Float,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let A = pow(10.0, Double(gainDB) / 40.0)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)

        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cosW
        let b2 = 1.0 - alpha * A
        let a0 = 1.0 + alpha / A
        let a1 = -2.0 * cosW
        let a2 = 1.0 - alpha / A

        return [
            b0 / a0,
            b1 / a0,
            b2 / a0,
            a1 / a0,
            a2 / a0
        ]
    }

    /// coefficients for all bands 동작을 처리합니다.
    static func coefficientsForAllBands(
        gains: [Float],
        sampleRate: Double
    ) -> [Double] {
        precondition(gains.count == EQSettings.bandCount)

        var allCoeffs: [Double] = []
        allCoeffs.reserveCapacity(50)

        for (index, frequency) in EQSettings.frequencies.enumerated() {
            let bandCoeffs = peakingEQCoefficients(
                frequency: frequency,
                gainDB: gains[index],
                q: graphicEQQ,
                sampleRate: sampleRate
            )
            allCoeffs.append(contentsOf: bandCoeffs)
        }

        return allCoeffs
    }
}
