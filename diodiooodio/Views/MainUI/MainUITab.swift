import SwiftUI

/// MainUI 탭 정의입니다. 케이스만 추가하면 사이드바와 본문에 자동 반영됩니다.
enum MainUITab: String, CaseIterable, Identifiable {
    case audio
    case media
    case system
    case automation
    case settings

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .audio: return language.text("Audio", "오디오")
        case .media: return language.text("Media", "미디어")
        case .system: return language.text("System", "시스템")
        case .automation: return language.text("Automation", "자동화")
        case .settings: return language.text("Settings", "설정")
        }
    }

    func subtitle(_ language: AppLanguage) -> String {
        switch self {
        case .audio: return language.text("Per-app volume, routing, and device control", "앱별 볼륨, 라우팅, 장치 제어")
        case .media: return language.text("Apple Music and Dynamic Bar controls", "Apple Music 및 다이나믹 바 제어")
        case .system: return language.text("Mac integration extensions", "맥 통합 관리 확장")
        case .automation: return language.text("Rule automation extension point", "자동화 룰 확장")
        case .settings: return language.text("Overall app and widget preferences", "앱/위젯 전체 설정")
        }
    }

    var systemImage: String {
        switch self {
        case .audio: return "speaker.wave.2.fill"
        case .media: return "music.note"
        case .system: return "macbook"
        case .automation: return "bolt.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}
