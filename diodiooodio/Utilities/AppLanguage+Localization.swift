import Foundation

extension AppLanguage {
    var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US")
        case .korean:
            return Locale(identifier: "ko_KR")
        }
    }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .korean:
            return "한국어"
        }
    }

    func text(_ english: String, _ korean: String) -> String {
        switch self {
        case .english:
            return english
        case .korean:
            return korean
        }
    }
}
