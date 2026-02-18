import SwiftUI

/// DesignTokens 열거형를 정의합니다.
enum DesignTokens {

    // MARK: - Colors 정의

    enum Colors {
        // MARK: - text primary

        /// text 기본 색상입니다.
        static let textPrimary: Color = .primary

        /// text 보조 색상입니다.
        static let textSecondary: Color = .secondary

        /// text tertiary 값입니다.
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)

        /// text quaternary 값입니다.
        static let textQuaternary = Color(nsColor: .quaternaryLabelColor)

        // MARK: - interactive 기본

        /// interactive 기본 색상입니다.
        static let interactiveDefault: Color = .secondary.opacity(0.9)

        /// interactive hover 색상입니다.
        static let interactiveHover: Color = .primary

        /// interactive 활성 색상입니다.
        static let interactiveActive: Color = .accentColor

        /// accent 기본 색상입니다.
        static let accentPrimary: Color = .accentColor

        /// 음소거 indicator 값입니다.
        static let mutedIndicator = Color(nsColor: .systemRed).opacity(0.85)

        /// 기본 장치 색상입니다.
        static let defaultDevice: Color = .accentColor

        // MARK: - separator

        /// separator 값입니다.
        static let separator = Color(nsColor: .separatorColor)

        /// glass border 값입니다.
        static let glassBorder = Color(nsColor: .separatorColor).opacity(0.3)

        /// glass border hover 값입니다.
        static let glassBorderHover = Color(nsColor: .separatorColor).opacity(0.5)

        // MARK: - 슬라이더 track

        /// 슬라이더 track 색상입니다.
        static let sliderTrack: Color = .primary.opacity(0.14)

        /// 슬라이더 fill 색상입니다.
        static let sliderFill: Color = .accentColor

        /// 슬라이더 thumb 색상입니다.
        static let sliderThumb: Color = .white

        /// unity marker 색상입니다.
        static let unityMarker: Color = .primary.opacity(0.5)

        // MARK: - thumb background

        /// thumb background 색상입니다.
        static let thumbBackground: Color = .white

        /// thumb dot 색상입니다.
        static let thumbDot: Color = .black.opacity(0.7)

        // MARK: - popup overlay

        /// popup overlay 색상입니다.
        static let popupOverlay: Color = Color.black.opacity(0.14)

        /// hero gradient start 색상입니다.
        static let heroGradientStart: Color = Color.white.opacity(0.06)

        /// hero gradient end 색상입니다.
        static let heroGradientEnd: Color = Color.black.opacity(0.08)

        /// warm accent 색상입니다.
        static let warmAccent: Color = .accentColor

        /// cool accent 색상입니다.
        static let coolAccent: Color = .secondary

        /// recessed background 색상입니다.
        static let recessedBackground: Color = Color.black.opacity(0.24)

        // MARK: - menu background

        /// menu background 색상입니다.
        static let menuBackground: Color = .clear

        /// menu border 색상입니다.
        static let menuBorder: Color = .white.opacity(0.14)

        /// menu border hover 색상입니다.
        static let menuBorderHover: Color = .white.opacity(0.22)

        /// 선택기 background 색상입니다.
        static let pickerBackground: Color = .primary.opacity(0.08)

        /// 선택기 hover 색상입니다.
        static let pickerHover: Color = .primary.opacity(0.12)

        // MARK: - vu green

        /// vu green 값입니다.
        static let vuGreen = Color(red: 0.20, green: 0.78, blue: 0.40)

        /// vu yellow 값입니다.
        static let vuYellow = Color(red: 0.95, green: 0.75, blue: 0.20)

        /// vu orange 값입니다.
        static let vuOrange = Color(red: 0.95, green: 0.50, blue: 0.20)

        /// vu red 값입니다.
        static let vuRed = Color(red: 0.90, green: 0.25, blue: 0.25)

        /// vu unlit 색상입니다.
        static let vuUnlit: Color = .primary.opacity(0.08)

        /// vu 음소거 색상입니다.
        static let vuMuted: Color = .primary.opacity(0.35)

    }

    // MARK: - Typography 정의

    enum Typography {
        /// section header 값입니다.
        static let sectionHeader = Font.system(size: 13, weight: .semibold, design: .rounded)

        /// section header tracking 값입니다.
        static let sectionHeaderTracking: CGFloat = 0

        /// 행 이름 값입니다.
        static let rowName = Font.system(size: 13, weight: .regular)

        /// 행 이름 bold 값입니다.
        static let rowNameBold = Font.system(size: 13, weight: .semibold)

        /// percentage 값입니다.
        static let percentage = Font.system(size: 11, weight: .medium, design: .monospaced)

        /// caption 값입니다.
        static let caption = Font.system(size: 10, weight: .regular)

        /// 선택기 text 값입니다.
        static let pickerText = Font.system(size: 11, weight: .regular)

        /// EQ label 값입니다.
        static let eqLabel = Font.system(size: 9, weight: .medium, design: .monospaced)
    }

    // MARK: - Spacing 정의

    enum Spacing {
        /// xxs 값입니다.
        static let xxs: CGFloat = 2

        /// xs 값입니다.
        static let xs: CGFloat = 4

        /// sm 값입니다.
        static let sm: CGFloat = 8

        /// md 값입니다.
        static let md: CGFloat = 12

        /// lg 값입니다.
        static let lg: CGFloat = 16

        /// xl 값입니다.
        static let xl: CGFloat = 20

        /// xxl 값입니다.
        static let xxl: CGFloat = 24
    }

    // MARK: - Dimensions 정의

    enum Dimensions {
        // MARK: - popup width

        /// popup width 값입니다.
        static let popupWidth: CGFloat = 580

        /// content padding 값입니다.
        static var contentPadding: CGFloat { Spacing.lg }

        /// content width 값입니다.
        static var contentWidth: CGFloat {
            popupWidth - (contentPadding * 2)
        }

        // MARK: - max scroll

        /// max scroll height 값입니다.
        static let maxScrollHeight: CGFloat = 400

        // MARK: - corner radius

        /// corner radius 값입니다.
        static let cornerRadius: CGFloat = 12

        /// 행 radius 값입니다.
        static let rowRadius: CGFloat = 10

        /// 버튼 radius 값입니다.
        static let buttonRadius: CGFloat = 6

        /// 아이콘 size 값입니다.
        static let iconSize: CGFloat = 22

        /// 아이콘 size small 값입니다.
        static let iconSizeSmall: CGFloat = 14

        // MARK: - 슬라이더 track

        /// 슬라이더 track height 값입니다.
        static let sliderTrackHeight: CGFloat = 3

        /// 슬라이더 thumb width 값입니다.
        static let sliderThumbWidth: CGFloat = 16

        /// 슬라이더 thumb height 값입니다.
        static let sliderThumbHeight: CGFloat = 10

        /// 슬라이더 thumb size 값입니다.
        static let sliderThumbSize: CGFloat = 12

        /// min touch 대상 값입니다.
        static let minTouchTarget: CGFloat = 16

        /// 행 content height 값입니다.
        static let rowContentHeight: CGFloat = 28

        // MARK: - 슬라이더 width

        /// 슬라이더 width 값입니다.
        static let sliderWidth: CGFloat = 140

        /// 슬라이더 min width 값입니다.
        static let sliderMinWidth: CGFloat = 120

        /// vu meter width 값입니다.
        static let vuMeterWidth: CGFloat = 28

        /// controls width 값입니다.
        static var controlsWidth: CGFloat {
            contentWidth - iconSize - Spacing.sm - 100
        }

        /// percentage width 값입니다.
        static let percentageWidth: CGFloat = 32

        // MARK: - vu meter

        /// vu meter bar height 값입니다.
        static let vuMeterBarHeight: CGFloat = 10

        /// vu meter bar spacing 값입니다.
        static let vuMeterBarSpacing: CGFloat = 2

        /// vu meter bar 개수 개수입니다.
        static let vuMeterBarCount: Int = 8

        // MARK: - 설정

        /// 설정 아이콘 width 값입니다.
        static let settingsIconWidth: CGFloat = 24

        /// 설정 슬라이더 width 값입니다.
        static let settingsSliderWidth: CGFloat = 200

        /// 설정 percentage width 값입니다.
        static let settingsPercentageWidth: CGFloat = 44

        /// 설정 선택기 width 값입니다.
        static let settingsPickerWidth: CGFloat = 120

    }

    // MARK: - Animation 정의

    enum Animation {
        /// quick 값입니다.
        static let quick = SwiftUI.Animation.spring(response: 0.2, dampingFraction: 0.85)

        /// hover 값입니다.
        static let hover = SwiftUI.Animation.easeOut(duration: 0.12)

        /// vu meter 레벨 값입니다.
        static let vuMeterLevel = SwiftUI.Animation.linear(duration: 0.05)
    }

    // MARK: - Timing 정의

    enum Timing {
        /// vu meter update interval 값입니다.
        static let vuMeterUpdateInterval: TimeInterval = 1.0 / 30.0

        /// vu meter 피크 hold 값입니다.
        static let vuMeterPeakHold: TimeInterval = 0.5
    }
}
