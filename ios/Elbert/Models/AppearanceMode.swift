import SwiftUI

/// A user-facing appearance choice: follow the system, or pin to one.
///
/// Persisted under `AppearanceMode.storageKey` via `@AppStorage`, which is what makes the choice
/// survive a relaunch and, since `@AppStorage` publishes through SwiftUI's environment, what makes
/// switching it apply immediately rather than needing a foreground/background cycle to notice.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    /// The one place this preference lives on disk.
    static let storageKey = "elbert.appearanceMode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means "do not override": `.preferredColorScheme(nil)` hands control back to the
    /// system, which is exactly what `.system` means here.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
