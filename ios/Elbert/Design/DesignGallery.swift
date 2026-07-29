import SwiftUI
import UIKit

/// A scratch screen that renders the whole design system so it can be reviewed against the
/// house non-negotiables and screenshotted in both appearances.
///
/// Not shipped in any real navigation, and it goes away in task 9 when the real shell lands.
/// Sections are deliberately sized to fit one phone screen so each can be captured whole.
/// Pick one with a launch argument, which lands in `UserDefaults` automatically:
///
/// ```
/// xcrun simctl launch booted com.calebl.elbert -gallerySection 2
/// ```
struct DesignGallery: View {
    @State private var section: GallerySection = GallerySection.fromLaunchArguments()
    @State private var toasts = ToastCentre()

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    header

                    switch section {
                    case .colour: ColourSection()
                    case .scale: ScaleSection()
                    case .typeLarge: TypeSection(roles: [.display, .h2, .h3, .lead])
                    case .typeSmall: TypeSection(roles: [.body, .bodyStrong, .caption, .eyebrow, .label, .labelSmall])
                    case .typeTrim: TrimSection()
                    case .buttonStates: ButtonStatesSection()
                    case .buttonContext: ButtonContextSection()
                    case .icons: IconSection()
                    case .toasts: ToastSection(toasts: toasts)
                    case .loaders: LoaderSection()
                    case .opticalSize: OpticalSizeSection()
                    case .weightAxis: WeightAxisSection()
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s5)
            }
        }
        .housePalette()
        .houseToast(toasts)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Design system")
                .typeRole(.eyebrow)
                .foregroundStyle(Theme.ink2)
            Text(section.title)
                .typeRole(.display)
                .foregroundStyle(Theme.ink)
        }
    }
}

enum GallerySection: Int, CaseIterable {
    case colour, scale, typeLarge, typeSmall, typeTrim
    case buttonStates, buttonContext, icons, toasts, loaders
    case opticalSize, weightAxis

    var title: String {
        switch self {
        case .colour: "Colour"
        case .scale: "Scale"
        case .typeLarge: "Type, large"
        case .typeSmall: "Type, small"
        case .typeTrim: "Cap trim"
        case .buttonStates: "Button states"
        case .buttonContext: "Buttons in context"
        case .icons: "Icons"
        case .toasts: "Toasts and banners"
        case .loaders: "Loaders"
        case .opticalSize: "Optical size"
        case .weightAxis: "Weight axis"
        }
    }

    static func fromLaunchArguments() -> GallerySection {
        let raw = UserDefaults.standard.integer(forKey: "gallerySection")
        return GallerySection(rawValue: raw) ?? .colour
    }
}

// MARK: - Shared bits

private struct SectionHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .typeRole(.h3)
            .foregroundStyle(Theme.ink)
    }
}

private struct Swatch: View {
    let name: String
    let colour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(colour)
                .frame(height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
            Text(name)
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

// MARK: - Colour

private struct ColourSection: View {
    private let columns = [GridItem(.adaptive(minimum: 88), spacing: Space.s3)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            group("Structure", [
                ("canvas", Theme.canvas),
                ("surface1", Theme.surface1),
                ("surface2", Theme.surface2),
                ("surface3", Theme.surface3),
                ("stroke", Theme.stroke),
            ])

            group("Ink ladder", [
                ("ink", Theme.ink),
                ("ink2", Theme.ink2),
                ("ink3", Theme.ink3),
            ])

            group("Accent", [
                ("accent", Theme.accent),
                ("accentInk", Theme.accentInk),
                ("accentSoft", Theme.accentSoft),
            ])

            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Semantic triples")
                ForEach(SemanticRole.allCases, id: \.self) { role in
                    HStack(spacing: Space.s2) {
                        Swatch(name: role.label.lowercased(), colour: role.base)
                        Swatch(name: "soft", colour: role.soft)
                        Swatch(name: "line", colour: role.line)
                    }
                }
            }
        }
    }

    private func group(_ title: String, _ entries: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionHeading(title: title)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Space.s3) {
                ForEach(entries, id: \.0) { name, colour in
                    Swatch(name: name, colour: colour)
                }
            }
        }
    }
}

// MARK: - Scale

private struct ScaleSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Elevation")
                HStack(spacing: Space.s4) {
                    elevationChip("card", .card)
                    elevationChip("pop", .pop)
                    elevationChip("flat", .flat)
                }
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Radius")
                HStack(spacing: Space.s3) {
                    radiusChip("sm 10", Radius.sm)
                    radiusChip("md 14", Radius.md)
                    radiusChip("card 20", Radius.card)
                    radiusChip("pill", Radius.pill)
                }
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Spacing")
                ForEach(spacingScale, id: \.0) { name, value in
                    HStack(spacing: Space.s3) {
                        Text(name)
                            .typeRole(.caption)
                            .foregroundStyle(Theme.ink3)
                            .frame(width: 32, alignment: .leading)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Theme.accent)
                            .frame(width: value, height: 8)
                        Text("\(Int(value))")
                            .typeRole(.caption)
                            .foregroundStyle(Theme.ink3)
                    }
                }
            }
        }
    }

    private var spacingScale: [(String, CGFloat)] {
        [("s1", Space.s1), ("s2", Space.s2), ("s3", Space.s3), ("s4", Space.s4),
         ("s5", Space.s5), ("s6", Space.s6), ("s7", Space.s7), ("s8", Space.s8)]
    }

    private func elevationChip(_ name: String, _ elevation: Elevation) -> some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Theme.surface1)
                .frame(width: 84, height: 56)
                .houseShadow(elevation)
            Text(name)
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
        }
    }

    private func radiusChip(_ name: String, _ radius: CGFloat) -> some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.surface2)
                .frame(width: 64, height: 44)
            Text(name)
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Type

private struct TypeSection: View {
    let roles: [TypeRole]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            ForEach(roles, id: \.self) { role in
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(specimen(for: role))
                        .typeRole(role)
                        .foregroundStyle(role == .caption || role == .eyebrow ? Theme.ink2 : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(metrics(for: role))
                        .typeRole(.caption)
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func specimen(for role: TypeRole) -> String {
        switch role {
        case .display: "Study what you forget"
        case .h2: "Decks and daily allowance"
        case .h3: "Desired retention"
        case .lead, .body:
            "Cards you rate again come back inside the same session. Everything else leaves and returns on its own schedule."
        case .bodyStrong: "Two cards are due right now."
        case .caption: "Reviewed 4 minutes ago"
        case .eyebrow: "New in this deck"
        case .label: "Start studying"
        case .labelSmall: "Decks"
        }
    }

    private func metrics(for role: TypeRole) -> String {
        let tracking = String(format: "%.3f", role.trackingEm)
        return "\(role.name) · \(Int(role.size))pt · wght \(Int(role.weight)) · leading \(role.leading) · tracking \(tracking)em"
    }
}

private struct TrimSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text("Cap trim removes the font's leading above the cap height and below the baseline, so a label sits truly centred against an icon. The tinted band is the text's own layout box.")
                .typeRole(.body)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Untrimmed")
                row(trimmed: false)
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Trimmed")
                row(trimmed: true)
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Stacked pair, s3 gap")
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("New in this deck")
                        .typeRole(.eyebrow)
                        .capTrim(.eyebrow)
                        .foregroundStyle(Theme.ink2)
                    Text("Spanish verbs")
                        .typeRole(.h2)
                        .capTrim(.h2)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    @ViewBuilder
    private func row(trimmed: Bool) -> some View {
        HStack(spacing: TypeRole.body.size * 0.5) {
            HouseIcon(icon: .due, role: .body)
                .foregroundStyle(Theme.accent)
            Group {
                if trimmed {
                    Text("Due in 12 minutes").typeRole(.body).capTrim(.body)
                } else {
                    Text("Due in 12 minutes").typeRole(.body)
                }
            }
            .foregroundStyle(Theme.ink)
            .background(Theme.accentSoft)
        }
    }
}

// MARK: - Buttons

private struct ButtonStatesSection: View {
    @FocusState private var focus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            row("Default") {
                Button("Save deck") {}.buttonStyle(.house)
                Button("Start studying") {}.buttonStyle(.houseAccent)
                Button {} label: { HouseIcon(icon: .edit, role: .body) }
                    .buttonStyle(.houseIcon)
            }

            row("Disabled") {
                Button("Save deck") {}.buttonStyle(.house).disabled(true)
                Button("Start studying") {}.buttonStyle(.houseAccent).disabled(true)
                Button {} label: { HouseIcon(icon: .edit, role: .body) }
                    .buttonStyle(.houseIcon).disabled(true)
            }

            row("Loading") {
                Button("Save deck") {}.buttonStyle(.house).houseLoading(true)
                Button("Start studying") {}.buttonStyle(.houseAccent).houseLoading(true)
                Button {} label: { HouseIcon(icon: .edit, role: .body) }
                    .buttonStyle(.houseIcon).houseLoading(true)
            }

            row("Focused") {
                Button("Save deck") {}
                    .buttonStyle(.house)
                    .focused($focus)
                    .houseFocusRing(true)
                Button("Start studying") {}
                    .buttonStyle(.houseAccent)
                    .houseFocusRing(true)
            }

            row("Small and destructive") {
                Button("Rename") {}
                    .buttonStyle(.house(.neutral, size: .small))
                Button("Delete deck") {}
                    .buttonStyle(.house(.neutral, size: .medium, role: .danger))
            }

            Text("Press and hold any button for the pressed fill and the impact haptic. Medium padding is 12 vertical and 24 horizontal, small is 8 and 16, exactly 2 to 1.")
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { focus = true }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionHeading(title: title)
            HStack(spacing: Space.s3) { content() }
        }
    }
}

private struct ButtonContextSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            SectionHeading(title: "A card with its one primary action")
            HouseCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("Due today")
                        .typeRole(.eyebrow)
                        .foregroundStyle(Theme.ink2)
                    Text("Spanish verbs")
                        .typeRole(.h2)
                        .foregroundStyle(Theme.ink)
                    Text("12 cards are due and 5 are new. Ratings you give now change when each card comes back.")
                        .typeRole(.body)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s3) {
                        Button {} label: {
                            HouseButtonLabel(title: "Study now", icon: .study)
                        }
                        .buttonStyle(.house(.accent, size: .medium, elevation: .pop))
                        Button("Edit") {}
                            .buttonStyle(.house)
                    }
                }
            }

            SectionHeading(title: "A flat repeating row")
            VStack(spacing: Space.s2) {
                ForEach(["Spanish verbs", "Kanji, grade 2", "Pharmacology"], id: \.self) { name in
                    HStack(spacing: Space.s3) {
                        HouseIcon(icon: .decks, role: .body)
                            .foregroundStyle(Theme.ink3)
                        Text(name)
                            .typeRole(.body)
                            .capTrim(.body)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: Space.s3)
                        Text("12 due")
                            .typeRole(.caption)
                            .foregroundStyle(Theme.ink3)
                        HouseIcon.trailing(.confirm, role: .body)
                    }
                    .padding(Space.s3)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Icons

private struct IconSection: View {
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Space.s3)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Text("Outline at rest on the left, fill on the right. Four glyphs have no fill counterpart in SF Symbols and fall back to the outline, shown quieter.")
                .typeRole(.body)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, alignment: .leading, spacing: Space.s4) {
                ForEach(Icon.allCases, id: \.self) { icon in
                    VStack(spacing: Space.s2) {
                        HStack(spacing: Space.s4) {
                            HouseIcon(icon: icon, filled: false, role: .h3)
                                .foregroundStyle(Theme.ink2)
                            HouseIcon(icon: icon, filled: true, role: .h3)
                                .foregroundStyle(icon.hasDistinctFill ? Theme.ink : Theme.ink3)
                        }
                        Text(icon.symbol)
                            .typeRole(.caption)
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Optical centring against a label")
                ForEach([Icon.due, Icon.synced, Icon.stats], id: \.self) { icon in
                    HStack(spacing: TypeRole.body.size * 0.5) {
                        HouseIcon(icon: icon, role: .body)
                            .foregroundStyle(Theme.accent)
                        Text(icon.name)
                            .typeRole(.body)
                            .capTrim(.body)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: Space.s3)
                        HouseIcon.trailing(.confirm, role: .body)
                    }
                    .padding(.vertical, Space.s2)
                }
            }
        }
    }
}

// MARK: - Feedback

private struct ToastSection: View {
    let toasts: ToastCentre

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Toasts")
                Text("Neutral surface, coloured icon. Success and info clear themselves after three seconds. Warning and danger stay until dismissed.")
                    .typeRole(.caption)
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s2) {
                    Button("Show success") { toasts.show(.success("Deck saved")) }
                        .buttonStyle(.house(.neutral, size: .small))
                    Button("Show error") { toasts.show(.error("Could not reach iCloud")) }
                        .buttonStyle(.house(.neutral, size: .small, role: .danger))
                }
                ToastView(toast: .success("Deck saved")) {}
                ToastView(toast: .error("Could not reach iCloud")) {}
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Banners")
                ForEach(SemanticRole.allCases, id: \.self) { role in
                    HouseBanner(role: role, message: bannerCopy(role), icon: bannerIcon(role))
                }
            }
        }
    }

    private func bannerCopy(_ role: SemanticRole) -> String {
        switch role {
        case .info: "Sync runs over iCloud, so both devices need the same account."
        case .success: "All cards are up to date on this device."
        case .warning: "Retention above 0.95 makes reviews much more frequent."
        case .danger: "Deleting a deck removes its cards and their history."
        }
    }

    private func bannerIcon(_ role: SemanticRole) -> Icon {
        switch role {
        case .info: .synced
        case .success: .confirm
        case .warning: .due
        case .danger: .delete
        }
    }
}

private struct LoaderSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Ring spinner")
                Text("Sized off the role it sits beside, so it never runs twice the cap height of the words next to it. Wave 1 ships this and the skeleton only.")
                    .typeRole(.caption)
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach([TypeRole.body, .caption], id: \.self) { role in
                    HStack(spacing: role.size * 0.6) {
                        RingSpinner(role: role)
                            .foregroundStyle(Theme.ink2)
                        Text(role == .body ? "Saving your deck" : "Checking iCloud")
                            .typeRole(role)
                            .foregroundStyle(Theme.ink2)
                    }
                }
                HStack(spacing: Space.s3) {
                    Button("Saving") {}.buttonStyle(.house).houseLoading(true)
                    Button("Saving") {}.buttonStyle(.houseAccent).houseLoading(true)
                }
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                SectionHeading(title: "Skeleton")
                VStack(alignment: .leading, spacing: Space.s2) {
                    SkeletonBlock(width: 180, height: 22)
                    SkeletonBlock(height: 14)
                    SkeletonBlock(width: 240, height: 14)
                }
            }
        }
    }
}

// MARK: - Variable font evidence

/// Side by side evidence that setting the `opsz` variation axis genuinely changes the
/// rendering. The first specimen leaves the axis at the file's 9pt default, the second sets
/// it to the rendered point size. The measured widths are what the axis moved.
private struct OpticalSizeSection: View {
    private let sample = "Handgloves at seventeen points"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("DM Sans registered: \(HouseFont.isAvailable ? "yes" : "no")")
                    .typeRole(.caption)
                    .foregroundStyle(HouseFont.isAvailable ? Theme.success : Theme.danger)
                ForEach(HouseFont.availableAxes(), id: \.identifier) { axis in
                    Text("axis \(HouseFont.tagString(axis.identifier)) · \(Int(axis.minimum)) to \(Int(axis.maximum)) · default \(Int(axis.defaultValue))")
                        .typeRole(.caption)
                        .foregroundStyle(Theme.ink3)
                }
            }

            comparison(size: 17, weight: 400, label: "Body, 17pt, wght 400")
            comparison(size: 34, weight: 700, label: "Display, 34pt, wght 700")
        }
    }

    private func comparison(size: CGFloat, weight: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionHeading(title: label)

            specimen(
                caption: "opsz unset, file default 9",
                font: HouseFont.uiFontWithoutOpticalSize(size: size, weight: weight)
            )
            specimen(
                caption: "opsz set to \(Int(min(max(size, 9), 40)))",
                font: HouseFont.uiFont(size: size, weight: weight)
            )
        }
    }

    private func specimen(caption: String, font: UIFont) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(caption)
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
            Text(sample)
                .font(Font(font))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("measured width \(width(of: sample, in: font))")
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
        }
    }

    private func width(of text: String, in font: UIFont) -> String {
        let measured = NSAttributedString(string: text, attributes: [.font: font]).size().width
        return String(format: "%.2fpt", measured)
    }
}

/// The `wght` axis, which `Font.custom` plus `.fontWeight()` cannot drive on this file.
private struct WeightAxisSection: View {
    private let weights: [Double] = [100, 300, 400, 600, 800, 1000]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("The bundled file registers one face, Regular. Every weight below comes from the wght variation axis, which is why they differ at all.")
                .typeRole(.body)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(weights, id: \.self) { weight in
                HStack(spacing: Space.s3) {
                    Text("wght \(Int(weight))")
                        .typeRole(.caption)
                        .foregroundStyle(Theme.ink3)
                        .frame(width: 76, alignment: .leading)
                    Text("Handgloves")
                        .font(Font(HouseFont.uiFont(size: 22, weight: weight)))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: Space.s2)
                    Text(width(weight: weight))
                        .typeRole(.caption)
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
    }

    private func width(weight: Double) -> String {
        let font = HouseFont.uiFont(size: 22, weight: weight)
        let measured = NSAttributedString(string: "Handgloves", attributes: [.font: font]).size().width
        return String(format: "%.1fpt", measured)
    }
}

#Preview("Dark") {
    DesignGallery().preferredColorScheme(.dark)
}

#Preview("Light") {
    DesignGallery().preferredColorScheme(.light)
}
