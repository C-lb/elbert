import SwiftUI

/// Every SF Symbol the app uses, named exactly once.
///
/// Wave 1 set only. A rename is a single edit here, and a screen never types a symbol
/// string. Deliberately SF Symbols rather than the Phosphor default used elsewhere,
/// because this app's chrome is otherwise fully native.
enum Icon: String, CaseIterable, Sendable {
    case home = "house"
    case decks = "rectangle.stack"
    case study = "graduationcap"
    case settings = "gearshape"
    case add = "plus"
    case edit = "pencil"
    case delete = "trash"
    case due = "clock"
    case confirm = "checkmark"
    case dismiss = "xmark"
    case stats = "chart.bar"
    case synced = "checkmark.icloud"
    /// iCloud sync is off. Distinct from `synced` rather than a dimmed copy of it, so the two
    /// states cannot be told apart only by colour.
    case cloudOff = "icloud.slash"
    /// Semantic, for a warning notice. Distinct from `dismiss` on purpose: a red xmark
    /// beside a grey xmark dismiss button is two identical glyphs meaning different things.
    case caution = "exclamationmark.triangle"
    /// Semantic, for an error notice.
    case problem = "exclamationmark.octagon"
    /// Bringing outside content in. Points down and into a tray, the platform's own direction for
    /// an import, and deliberately not the up-arrow share glyph, which reads as sending out.
    case importDeck = "square.and.arrow.down"

    /// The outline symbol, used at rest.
    var symbol: String { rawValue }

    /// The solid counterpart, used for the current tab and for pressed state.
    ///
    /// Several glyphs have no `.fill` variant worth using: `plus`, `pencil`, `checkmark`,
    /// `xmark` are strokes with nothing to fill in SF Symbols, and `icloud.slash` is a status
    /// glyph that is never shown filled, so all five resolve back to the outline. None of them
    /// appear in the tab bar, where the fill swap is the state signal.
    var filledSymbol: String {
        switch self {
        case .add, .edit, .confirm, .dismiss, .cloudOff: rawValue
        default: rawValue + ".fill"
        }
    }

    /// True when `filledSymbol` is a genuinely different glyph.
    var hasDistinctFill: Bool { filledSymbol != rawValue }

    func image(filled: Bool = false) -> Image {
        Image(systemName: filled ? filledSymbol : symbol)
    }

    var name: String {
        switch self {
        case .home: "home"
        case .decks: "decks"
        case .study: "study"
        case .settings: "settings"
        case .add: "add"
        case .edit: "edit"
        case .delete: "delete"
        case .due: "due"
        case .confirm: "confirm"
        case .dismiss: "dismiss"
        case .stats: "stats"
        case .synced: "synced"
        case .cloudOff: "cloud-off"
        case .caution: "caution"
        case .problem: "problem"
        case .importDeck: "import-deck"
        }
    }
}

/// An icon sized against the text it sits beside, so a row shares one optical centre line.
///
/// A leading icon is 1em of the role's size. A trailing affordance runs about 0.85em and one
/// ink step quieter. A loader beside a caption runs about 1.15em.
struct HouseIcon: View {
    let icon: Icon
    var filled: Bool = false
    var role: TypeRole = .body
    var scale: CGFloat = 1

    var body: some View {
        icon.image(filled: filled)
            .font(.system(size: role.size * scale, weight: .regular))
            .frame(width: role.size * scale, height: role.size * scale)
            .fixedSize()
    }
}

extension HouseIcon {
    /// A trailing chevron-style affordance: smaller and quieter than the label it follows.
    static func trailing(_ icon: Icon, role: TypeRole = .body) -> some View {
        HouseIcon(icon: icon, role: role, scale: 0.85)
            .foregroundStyle(Theme.ink3)
    }
}
