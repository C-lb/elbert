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

    /// The role's true line height in points: baseline to baseline.
    var lineHeight: CGFloat { size * leading }

    /// SwiftUI `lineSpacing` is *extra* space added between lines, on top of the font's own
    /// line height, and it cannot go negative. DM Sans has a natural line height of 1.302em,
    /// so for any role whose target leading is looser than that this lands exactly on target.
    var lineSpacing: CGFloat {
        max(0, lineHeight - uiFont.lineHeight)
    }

    /// True when the role's target leading is **tighter** than DM Sans' natural 1.302em, so
    /// `lineSpacing` alone cannot reach it.
    ///
    /// Display, h2 and h3 all fall here, which is precisely where tight leading is the house
    /// look, so leaving them at the natural line height would give up the thing the type
    /// scale exists to protect. `HouseText` renders these through `NSParagraphStyle`
    /// instead, which *can* compress a line box.
    var needsCompressedLeading: Bool {
        lineHeight < uiFont.lineHeight - 0.01
    }

    /// Roles that only ever hold one line: a button label, a tab caption. Their leading of
    /// 1.0 is deliberate and there is no second line for it to collide with.
    var isSingleLine: Bool {
        switch self {
        case .label, .labelSmall: true
        default: false
        }
    }

    /// Space between the descender of one line and the cap height of the next, at the role's
    /// target leading. Must stay positive for any wrapping role or lines collide, which is
    /// what the old clamp at zero was protecting against. Meaningless for `isSingleLine`
    /// roles, which measure slightly negative by design.
    var interlineClearance: CGFloat {
        let font = uiFont
        return lineHeight - abs(font.descender) - font.capHeight
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

// MARK: - Text with a compressed line box

/// House body of text. Use this instead of `Text(...).typeRole(...)` for anything that can
/// wrap, and always for `display`, `h2` and `h3`.
///
/// SwiftUI's `lineSpacing` can only ever *add* space, so it cannot reach a leading tighter
/// than the font's own line height, and DM Sans is a loose 1.302em. For the three tight
/// roles this renders through a `UILabel` carrying an `NSParagraphStyle` with
/// `minimumLineHeight` and `maximumLineHeight` pinned to the role's target, plus a
/// compensating `baselineOffset` so the glyphs stay centred in the compressed line box
/// rather than riding its top edge. Every other role goes down the plain SwiftUI path.
struct HouseText: View {
    let content: String
    var role: TypeRole = .body
    /// Which rung of the ink ladder this text sits on.
    var ink: KeyPath<Palette, ColorToken> = \.ink
    var alignment: TextAlignment = .leading

    init(
        _ content: String,
        role: TypeRole = .body,
        ink: KeyPath<Palette, ColorToken> = \.ink,
        alignment: TextAlignment = .leading
    ) {
        self.content = content
        self.role = role
        self.ink = ink
        self.alignment = alignment
    }

    var body: some View {
        if role.needsCompressedLeading {
            CompressedLeadingLabel(content: content, role: role, ink: ink, alignment: alignment)
        } else {
            Text(content)
                .typeRole(role)
                .multilineTextAlignment(alignment)
                .foregroundStyle(Color(uiColor: Theme.uiColor(ink)))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CompressedLeadingLabel: UIViewRepresentable {
    let content: String
    let role: TypeRole
    let ink: KeyPath<Palette, ColorToken>
    let alignment: TextAlignment

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributedString()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let proposed = proposal.width ?? .greatestFiniteMagnitude
        let width = proposed.isFinite && proposed > 0 ? proposed : .greatestFiniteMagnitude
        let fitted = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: min(fitted.width, width), height: fitted.height)
    }

    private func attributedString() -> NSAttributedString {
        let font = role.uiFont
        let lineHeight = role.lineHeight

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = nsAlignment

        // Compressing the line box from `font.lineHeight` down to `lineHeight` takes the
        // space off the top, which leaves the glyphs sitting low. Half the difference put
        // back on the baseline recentres them, and `baselineOffset` moves text by twice its
        // value against the line box, hence the quarter.
        let offset = (lineHeight - font.lineHeight) / 4

        return NSAttributedString(string: content, attributes: [
            .font: font,
            .foregroundColor: Theme.uiColor(ink),
            .kern: role.trackingPoints,
            .paragraphStyle: paragraph,
            .baselineOffset: offset,
        ])
    }

    private var nsAlignment: NSTextAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .right
        default: .left
        }
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
