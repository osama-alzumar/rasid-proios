import SwiftUI

enum Theme {
    /// rasid.pro brand-500 (#00d1a0) / brand-600 (#00a37d).
    static let brand = Color("AccentColor")
    static let brandDeep = Color(red: 0, green: 0.639, blue: 0.490)
    static let card = Color(.secondarySystemGroupedBackground)
    static let background = Color(.systemGroupedBackground)
}

/// The user's light/dark choice, stored in UserDefaults.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "تلقائي (حسب الجهاز)"
        case .light: return "فاتح"
        case .dark: return "ليلي"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
