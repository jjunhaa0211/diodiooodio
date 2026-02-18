import Foundation

/// VolumeMapping 열거형를 정의합니다.
enum VolumeMapping {
    /// 슬라이더 to gain 동작을 처리합니다.
    static func sliderToGain(_ slider: Double, maxBoost: Float = 2.0) -> Float {
        if slider <= 0.5 {
            return Float(slider * 2)
        } else {
            let t = (slider - 0.5) / 0.5
            return 1.0 + Float(t) * (maxBoost - 1.0)
        }
    }

    /// gain to 슬라이더 동작을 처리합니다.
    static func gainToSlider(_ gain: Float, maxBoost: Float = 2.0) -> Double {
        if gain <= 1.0 {
            return Double(gain * 0.5)
        } else {
            let t = (gain - 1.0) / (maxBoost - 1.0)
            return 0.5 + Double(t) * 0.5
        }
    }
}
