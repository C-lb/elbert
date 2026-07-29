import SwiftUI
import UIKit
import CoreText

// MARK: - Variable font construction

/// DM Sans ships as a **variable** font and does not behave like an ordinary face.
///
/// Measured at runtime: it registers as family `"DM Sans"` with PostScript name
/// `DMSans-9ptRegular`, exposes named instances `…_Thin` through `…_Black`, and carries two
/// variation axes, `opsz` (9...40, default **9**) and `wght` (100...1000, default 400).
///
/// Two consequences drive everything below:
///
/// 1. The optical size axis defaults to **9pt**. Only that slice surfaces to iOS, so body text
///    set at 17pt renders with a 9pt optical design: looser tracking, wider letterforms. The
///    house type rules hang on precise tracking, so this has to be corrected rather than lived with.
/// 2. `Font.custom("DM Sans", size:)` plus `.fontWeight()` does not drive the `wght` axis. It
///    picks the nearest registered face instead, which for this file is only Regular.
///
/// So every font is built through Core Text variation axes: a `UIFontDescriptor` carrying
/// `kCTFontVariationAttribute` with both axis tags set explicitly.
enum HouseFont {
    static let familyName = "DM Sans"

    /// Four-character Core Text axis tags, packed big-endian into a `UInt32`.
    /// `'wght'` = 0x77676874, `'opsz'` = 0x6F70737A.
    static let weightAxis: UInt32 = 0x7767_6874
    static let opticalSizeAxis: UInt32 = 0x6F70_737A

    /// The `opsz` axis range the bundled file actually supports.
    static let opticalSizeRange: ClosedRange<CGFloat> = 9...40

    private static let cache = FontCache()

    /// Builds a DM Sans instance with both variation axes set.
    ///
    /// - Parameters:
    ///   - size: rendered point size.
    ///   - weight: `wght` axis value, 100...1000.
    ///   - opticalSize: `opsz` axis value. Defaults to the point size, clamped into 9...40,
    ///     which is the whole point: it makes 17pt body text use the 17pt optical design.
    static func uiFont(size: CGFloat, weight: Double, opticalSize: CGFloat? = nil) -> UIFont {
        let opsz = min(max(opticalSize ?? size, opticalSizeRange.lowerBound), opticalSizeRange.upperBound)
        let key = "\(size)|\(weight)|\(opsz)" as NSString
        if let cached = cache.storage.object(forKey: key) { return cached }

        let font = build(size: size, weight: weight, opticalSize: opsz)
        cache.storage.setObject(font, forKey: key)
        return font
    }

    /// Same, but with the `opsz` axis left at the file's 9pt default. Only used by the
    /// design gallery to demonstrate that setting the axis genuinely changes the rendering.
    static func uiFontWithoutOpticalSize(size: CGFloat, weight: Double) -> UIFont {
        build(size: size, weight: weight, opticalSize: nil)
    }

    private static func build(size: CGFloat, weight: Double, opticalSize: CGFloat?) -> UIFont {
        var variations: [UInt32: CGFloat] = [weightAxis: CGFloat(weight)]
        if let opticalSize {
            variations[opticalSizeAxis] = opticalSize
        }

        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: familyName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations,
        ])
        let font = UIFont(descriptor: descriptor, size: size)

        // If the bundled font failed to register, fall back to the system face at the nearest
        // weight rather than shipping a silently wrong typeface.
        guard font.familyName == familyName else {
            return .systemFont(ofSize: size, weight: systemWeight(for: weight))
        }
        return font
    }

    private static func systemWeight(for weight: Double) -> UIFont.Weight {
        switch weight {
        case ..<250: .light
        case ..<350: .regular
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        default: .heavy
        }
    }

    /// Reports whether the bundled variable font resolved. Surfaced in the design gallery.
    static var isAvailable: Bool {
        UIFont.familyNames.contains(familyName)
    }

    /// The variation axes the registered file actually exposes, for diagnostics.
    static func availableAxes() -> [(name: String, identifier: UInt32, minimum: Double, maximum: Double, defaultValue: Double)] {
        let ctFont = CTFontCreateWithName(familyName as CFString, 17, nil)
        guard let axes = CTFontCopyVariationAxes(ctFont) as? [[String: Any]] else { return [] }
        return axes.compactMap { axis in
            guard
                let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? UInt32,
                let minimum = axis[kCTFontVariationAxisMinimumValueKey as String] as? Double,
                let maximum = axis[kCTFontVariationAxisMaximumValueKey as String] as? Double,
                let defaultValue = axis[kCTFontVariationAxisDefaultValueKey as String] as? Double
            else { return nil }
            let name = axis[kCTFontVariationAxisNameKey as String] as? String ?? tagString(identifier)
            return (name, identifier, minimum, maximum, defaultValue)
        }
    }

    static func tagString(_ tag: UInt32) -> String {
        let bytes = [
            UInt8((tag >> 24) & 0xff),
            UInt8((tag >> 16) & 0xff),
            UInt8((tag >> 8) & 0xff),
            UInt8(tag & 0xff),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// `NSCache` is thread-safe, so this wrapper is safe to hold as a global.
private final class FontCache: @unchecked Sendable {
    let storage = NSCache<NSString, UIFont>()
}

// MARK: - Type roles

/// The house type table, mobile only. Base is 17pt.
///
/// Leading and tracking scale inversely with size: the bigger the type, the tighter both get.
/// Every role carries size, weight, leading and tracking together, so a screen picks a role
/// and never a number.
enum TypeRole: CaseIterable, Sendable {
    /// h1 / display
    case display
    case h2
    case h3
    case lead
    case body
    case bodyStrong
    /// Caption, hint, dense UI rows.
    case caption
    /// Eyebrow, chip. Sentence case, never ALL-CAPS.
    case eyebrow
    /// Single-line label: button, tab, control.
    case label
    /// The small caption under a tab-bar icon.
    case labelSmall

    static let baseSize: CGFloat = 17

    var size: CGFloat {
        switch self {
        case .display: 34
        case .h2: 26
        case .h3: 21
        case .lead: 19
        case .body, .bodyStrong, .label: TypeRole.baseSize
        case .caption, .eyebrow: 14
        case .labelSmall: 12
        }
    }

    /// `wght` axis value, 100...1000.
    var weight: Double {
        switch self {
        case .display: 700
        case .h2: 650
        case .h3: 600
        case .lead: 400
        case .body: 400
        case .bodyStrong: 600
        case .caption: 400
        case .eyebrow: 500
        case .label: 500
        case .labelSmall: 500
        }
    }

    /// Line height as a multiple of the point size.
    var leading: CGFloat {
        switch self {
        case .display: 1.05
        case .h2: 1.12
        case .h3: 1.22
        case .lead: 1.45
        case .body, .bodyStrong: 1.55
        case .caption, .eyebrow: 1.30
        case .label, .labelSmall: 1.0
        }
    }

    /// Tracking in **em**. SwiftUI `.tracking()` takes points, so the modifier multiplies
    /// this by the role's point size.
    var trackingEm: CGFloat {
        switch self {
        case .display: -0.032
        case .h2: -0.026
        case .h3: -0.02
        case .lead: -0.01
        case .body, .bodyStrong: 0
        case .caption: 0.006
        case .eyebrow: 0.012
        case .label, .labelSmall: 0
        }
    }

    var trackingPoints: CGFloat { trackingEm * size }

    var uiFont: UIFont { HouseFont.uiFont(size: size, weight: weight) }

    var font: Font { Font(uiFont) }

    /// SwiftUI `lineSpacing` is *extra* space added between lines, on top of the font's own
    /// line height. To land on the role's true leading we subtract what the font already gives.
    /// Clamped at zero, which is what guarantees no line ever collides with the one above it:
    /// the natural line height of DM Sans is already looser than the display and h2 targets.
    var lineSpacing: CGFloat {
        max(0, size * leading - uiFont.lineHeight)
    }

    var name: String {
        switch self {
        case .display: "display"
        case .h2: "h2"
        case .h3: "h3"
        case .lead: "lead"
        case .body: "body"
        case .bodyStrong: "body strong"
        case .caption: "caption"
        case .eyebrow: "eyebrow"
        case .label: "label"
        case .labelSmall: "label small"
        }
    }
}

// MARK: - Modifiers

private struct TypeRoleModifier: ViewModifier {
    let role: TypeRole

    func body(content: Content) -> some View {
        content
            .font(role.font)
            .tracking(role.trackingPoints)
            .lineSpacing(role.lineSpacing)
    }
}

/// Cap-to-baseline trim, the SwiftUI stand-in for CSS `text-box: trim-both cap alphabetic`.
///
/// Reads the resolved `UIFont` and removes the space above the cap height and below the
/// baseline as negative vertical padding. This is what makes a label sit truly centred
/// against an icon inside a button.
///
/// Trimmed text has had its built-in leading removed, so any stack using it must set an
/// explicit gap of at least `Space.s2`, or the lines really will touch.
private struct CapBaselineTrim: ViewModifier {
    let role: TypeRole

    func body(content: Content) -> some View {
        let font = role.uiFont
        let above = font.ascender - font.capHeight
        let below = abs(font.descender)
        return content
            .padding(.top, -above)
            .padding(.bottom, -below)
    }
}

extension View {
    /// Applies size, weight, leading and tracking for a role in one go.
    func typeRole(_ role: TypeRole) -> some View {
        modifier(TypeRoleModifier(role: role))
    }

    /// Trims the font's leading to cap height and baseline. Single-line labels and headings only.
    func capTrim(_ role: TypeRole) -> some View {
        modifier(CapBaselineTrim(role: role))
    }

    /// Caps running text near 68 characters, past which the eye loses the line return.
    func houseMeasure() -> some View {
        frame(maxWidth: 34 * TypeRole.baseSize, alignment: .leading)
    }
}
