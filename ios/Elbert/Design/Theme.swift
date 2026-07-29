import SwiftUI
import UIKit

// MARK: - Raw token

/// A colour as stored data, so a `Palette` stays a plain `Sendable` value type.
/// `hex` is 0xRRGGBB, `alpha` is 0...1.
struct ColorToken: Sendable, Equatable {
    let hex: UInt32
    let alpha: Double

    init(_ hex: UInt32, alpha: Double = 1) {
        self.hex = hex
        self.alpha = alpha
    }

    var uiColor: UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: CGFloat(alpha)
        )
    }

    var color: Color { Color(uiColor: uiColor) }

    /// WCAG relative luminance, 0 (black) to 1 (white), ignoring alpha.
    ///
    /// The surface ladder is a contract (`canvas` < `surface1` < `surface2` < `surface3`)
    /// and this is what lets a test assert it rather than trusting the hex values by eye.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let red = linear(Double((hex >> 16) & 0xff) / 255)
        let green = linear(Double((hex >> 8) & 0xff) / 255)
        let blue = linear(Double(hex & 0xff) / 255)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

// MARK: - Palette

/// Every colour in the app, for one appearance.
///
/// Dark is the primary appearance and its values are carried over verbatim from the web
/// app's `src/styles.css`, except for the info and warning triples, which the web app
/// never had. Surfaces step *lighter* than the canvas in dark, which is the house rule.
struct Palette: Sendable {
    // Structure
    let canvas: ColorToken
    let surface1: ColorToken
    let surface2: ColorToken
    let surface3: ColorToken
    let stroke: ColorToken

    // Ink ladder
    let ink: ColorToken
    let ink2: ColorToken
    let ink3: ColorToken

    // The single accent
    let accent: ColorToken
    let accentInk: ColorToken
    let accentSoft: ColorToken

    // Semantic triples: base (text/icon), soft (tint fill), line (hairline ring)
    let danger: ColorToken
    let dangerSoft: ColorToken
    let dangerLine: ColorToken

    let success: ColorToken
    let successSoft: ColorToken
    let successLine: ColorToken

    let info: ColorToken
    let infoSoft: ColorToken
    let infoLine: ColorToken

    let warn: ColorToken
    let warnSoft: ColorToken
    let warnLine: ColorToken

    // Shadow ink, tinted to the ground it falls on
    let shadowCard: ColorToken
    let shadowPop: ColorToken
}

extension Palette {
    /// Dark is primary. `canvas` < `surface1` < `surface2` < `surface3` in lightness,
    /// in **both** appearances. `PaletteTests` asserts it, so the ladder cannot drift.
    static let dark = Palette(
        canvas: ColorToken(0x111113),
        surface1: ColorToken(0x1a1a1e),
        surface2: ColorToken(0x222226),
        surface3: ColorToken(0x2b2b30),
        stroke: ColorToken(0xffffff, alpha: 0.08),

        ink: ColorToken(0xf4f4f5),
        ink2: ColorToken(0xb8b6bd),
        ink3: ColorToken(0x7c7a83),

        accent: ColorToken(0x5865f2),
        accentInk: ColorToken(0xf4f4f8),
        accentSoft: ColorToken(0x5865f2, alpha: 0.16),

        danger: ColorToken(0xe0685f),
        dangerSoft: ColorToken(0xe0685f, alpha: 0.14),
        dangerLine: ColorToken(0xe0685f, alpha: 0.30),

        success: ColorToken(0x6bbf8b),
        successSoft: ColorToken(0x6bbf8b, alpha: 0.14),
        successLine: ColorToken(0x6bbf8b, alpha: 0.30),

        // Blue, muted so it sits on a dark ground and reads apart from the blurple accent.
        info: ColorToken(0x5aa6d6),
        infoSoft: ColorToken(0x5aa6d6, alpha: 0.14),
        infoLine: ColorToken(0x5aa6d6, alpha: 0.30),

        // Amber, not yellow. Pure yellow is illegible on dark.
        warn: ColorToken(0xd8a24a),
        warnSoft: ColorToken(0xd8a24a, alpha: 0.14),
        warnLine: ColorToken(0xd8a24a, alpha: 0.30),

        shadowCard: ColorToken(0x000000, alpha: 0.55),
        shadowPop: ColorToken(0x000000, alpha: 0.70)
    )

    /// Light appearance. Flat off-white canvas, surfaces step toward white but never reach it.
    ///
    /// The ladder runs the same direction as dark: each surface is *lighter* than the one
    /// below it. That means the canvas has to be the darkest value here, not a mid one, or
    /// there is no headroom left above `surface2` for `surface3` to occupy.
    static let light = Palette(
        canvas: ColorToken(0xececed),
        surface1: ColorToken(0xf4f4f6),
        surface2: ColorToken(0xf9f9fb),
        surface3: ColorToken(0xfdfdfe),
        stroke: ColorToken(0x000000, alpha: 0.08),

        ink: ColorToken(0x17171a),
        ink2: ColorToken(0x55535c),
        ink3: ColorToken(0x85838c),

        accent: ColorToken(0x5865f2),
        accentInk: ColorToken(0xf4f4f8),
        accentSoft: ColorToken(0x5865f2, alpha: 0.12),

        danger: ColorToken(0xc0463c),
        dangerSoft: ColorToken(0xc0463c, alpha: 0.12),
        dangerLine: ColorToken(0xc0463c, alpha: 0.26),

        success: ColorToken(0x2f8f5b),
        successSoft: ColorToken(0x2f8f5b, alpha: 0.12),
        successLine: ColorToken(0x2f8f5b, alpha: 0.26),

        // Cyan-leaning so it cannot be confused with the blurple accent.
        info: ColorToken(0x1c6f9c),
        infoSoft: ColorToken(0x1c6f9c, alpha: 0.12),
        infoLine: ColorToken(0x1c6f9c, alpha: 0.26),

        warn: ColorToken(0x9a6608),
        warnSoft: ColorToken(0x9a6608, alpha: 0.12),
        warnLine: ColorToken(0x9a6608, alpha: 0.26),

        shadowCard: ColorToken(0x101014, alpha: 0.16),
        shadowPop: ColorToken(0x101014, alpha: 0.24)
    )

    static func resolved(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark
}

extension EnvironmentValues {
    /// Raw token values for the current appearance. Injected by `.housePalette()`,
    /// which `RootView` applies once at the top of the tree.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

private struct PaletteInjector: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.palette, Palette.resolved(for: scheme))
    }
}

extension View {
    /// Resolves `\.palette` off the SwiftUI environment colour scheme.
    func housePalette() -> some View { modifier(PaletteInjector()) }
}

// MARK: - Theme

/// The tokens screens actually reach for.
///
/// Each colour is a dynamic `Color`, so it resolves off the current appearance without
/// the call site knowing which one it is. `\.palette` is there for the rare case that
/// needs the raw value (a `UIColor`, a gradient stop, a computed contrast check).
enum Theme {
    /// A `UIColor` that resolves off the trait collection it is drawn in, for the few places
    /// that need UIKit rather than SwiftUI (`HouseText`'s label, chiefly).
    static func uiColor(_ path: KeyPath<Palette, ColorToken>) -> UIColor {
        UIColor { trait in
            let palette: Palette = trait.userInterfaceStyle == .dark ? .dark : .light
            return palette[keyPath: path].uiColor
        }
    }

    private static func dynamic(_ path: KeyPath<Palette, ColorToken>) -> Color {
        Color(uiColor: uiColor(path))
    }

    static let canvas = dynamic(\.canvas)
    static let surface1 = dynamic(\.surface1)
    static let surface2 = dynamic(\.surface2)
    static let surface3 = dynamic(\.surface3)
    static let stroke = dynamic(\.stroke)

    static let ink = dynamic(\.ink)
    static let ink2 = dynamic(\.ink2)
    static let ink3 = dynamic(\.ink3)

    static let accent = dynamic(\.accent)
    static let accentInk = dynamic(\.accentInk)
    static let accentSoft = dynamic(\.accentSoft)

    static let danger = dynamic(\.danger)
    static let dangerSoft = dynamic(\.dangerSoft)
    static let dangerLine = dynamic(\.dangerLine)

    static let success = dynamic(\.success)
    static let successSoft = dynamic(\.successSoft)
    static let successLine = dynamic(\.successLine)

    static let info = dynamic(\.info)
    static let infoSoft = dynamic(\.infoSoft)
    static let infoLine = dynamic(\.infoLine)

    static let warn = dynamic(\.warn)
    static let warnSoft = dynamic(\.warnSoft)
    static let warnLine = dynamic(\.warnLine)

    /// Shadow ink is dynamic for the same reason every other token is: a view that never
    /// saw `.housePalette()` still has to render the right appearance. Reading the shadow
    /// off `\.palette` instead made an un-injected screen draw light-mode colours under a
    /// dark-mode shadow.
    static let shadowCard = dynamic(\.shadowCard)
    static let shadowPop = dynamic(\.shadowPop)
}

// MARK: - Semantic role

/// The four meanings colour is allowed to carry. Nothing decorative uses these.
enum SemanticRole: CaseIterable, Sendable {
    case info, success, warning, danger

    var base: Color {
        switch self {
        case .info: Theme.info
        case .success: Theme.success
        case .warning: Theme.warn
        case .danger: Theme.danger
        }
    }

    var soft: Color {
        switch self {
        case .info: Theme.infoSoft
        case .success: Theme.successSoft
        case .warning: Theme.warnSoft
        case .danger: Theme.dangerSoft
        }
    }

    var line: Color {
        switch self {
        case .info: Theme.infoLine
        case .success: Theme.successLine
        case .warning: Theme.warnLine
        case .danger: Theme.dangerLine
        }
    }

    var label: String {
        switch self {
        case .info: "Info"
        case .success: "Success"
        case .warning: "Warning"
        case .danger: "Danger"
        }
    }
}

// MARK: - Spacing

/// The 4px scale. Never invent a one-off value.
enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    static let s8: CGFloat = 64
}

// MARK: - Radius

enum Radius {
    /// Small controls: buttons, menu rows, chips.
    static let sm: CGFloat = 10
    /// Medium controls: fields, larger buttons.
    static let md: CGFloat = 14
    /// Cards, sheets, the study card face.
    static let card: CGFloat = 20
    /// Fully rounded.
    static let pill: CGFloat = 999
}

// MARK: - Shadow

/// Soft and diffuse: large blur, low opacity, tinted to the ground. Never a hard slab.
enum Elevation {
    /// A card resting on the canvas.
    case card
    /// Anything floating *above* a card: menus, popovers, toasts, a floating button.
    case pop
    /// No shadow. Repeating rows in a list.
    case flat
}

/// `.shadow` propagates down to every leaf drawing primitive, so without a compositing
/// group each glyph inside a shadowed container casts its own shadow and the text sits in a
/// grey smudge. `.compositingGroup()` flattens the subtree first, so the shadow is cast by
/// the assembled silhouette (in practice the background shape) and by nothing else.
///
/// It is invisible in dark mode, where a black shadow falls on a near-black card, which is
/// exactly why it survived review.
private struct HouseShadow: ViewModifier {
    let elevation: Elevation

    func body(content: Content) -> some View {
        switch elevation {
        case .flat:
            content
        case .card:
            content
                .compositingGroup()
                .shadow(color: Theme.shadowCard, radius: 17, x: 0, y: 10)
        case .pop:
            content
                .compositingGroup()
                .shadow(color: Theme.shadowPop, radius: 24, x: 0, y: 16)
                .shadow(color: Theme.shadowCard, radius: 6, x: 0, y: 2)
        }
    }
}

extension View {
    func houseShadow(_ elevation: Elevation) -> some View {
        modifier(HouseShadow(elevation: elevation))
    }
}

// MARK: - Z ladder

/// One ladder. Never a made-up 9999.
enum ZLayer {
    static let base: Double = 0
    static let stickyChrome: Double = 40
    static let scrim: Double = 60
    static let menu: Double = 70
    static let toast: Double = 80
}

// MARK: - Surfaces

/// A card: one level of padding, flat fill, soft shadow, optional dim hairline.
struct HouseCard<Content: View>: View {
    var elevation: Elevation = .card
    var padding: CGFloat = Space.s4
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .houseShadow(elevation)
    }
}
