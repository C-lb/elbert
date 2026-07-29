import Foundation

/// The four places the app goes. One set of items, one order, everywhere.
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case decks
    case study
    case settings

    var id: String { rawValue }

    var icon: Icon {
        switch self {
        case .home: .home
        case .decks: .decks
        case .study: .study
        case .settings: .settings
        }
    }

    /// Sentence case, plain nouns. These are captions under an icon, not headings.
    var title: String {
        switch self {
        case .home: "Home"
        case .decks: "Decks"
        case .study: "Study"
        case .settings: "Settings"
        }
    }
}
