import SwiftUI

// MARK: - Tiers

/// Three tiers, defined once. Screens pick a tier, never hand-tune a button.
enum HouseButtonTier: Sendable {
    /// The default. Grey `surface1`. Almost every button in the app is this.
    case neutral
    /// The single primary action on a screen. Accent fill. Never more than one per view.
    case accent
    /// A square icon-only control.
    case icon
}

enum HouseButtonSize: Sendable {
    case small
    case medium

    /// Vertical padding. Horizontal is exactly twice this.
    var verticalPadding: CGFloat {
        switch self {
        case .small: Space.s2
        case .medium: Space.s3
        }
    }

    var horizontalPadding: CGFloat { verticalPadding * 2 }

    var cornerRadius: CGFloat {
        switch self {
        case .small: Radius.sm
        case .medium: Radius.md
        }
    }

    var role: TypeRole { .label }

    /// Minimum tap target, so a small button is still reachable with a thumb.
    var minimumSide: CGFloat { 44 }
}

// MARK: - Loading state

private struct HouseButtonLoadingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var houseButtonIsLoading: Bool {
        get { self[HouseButtonLoadingKey.self] }
        set { self[HouseButtonLoadingKey.self] = newValue }
    }
}

private struct HouseButtonFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var houseButtonIsFocused: Bool {
        get { self[HouseButtonFocusKey.self] }
        set { self[HouseButtonFocusKey.self] = newValue }
    }
}

extension View {
    /// Puts a button into its loading state: the label is swapped for a ring spinner and the
    /// control is disabled, so a second tap cannot fire the same request twice.
    func houseLoading(_ isLoading: Bool) -> some View {
        environment(\.houseButtonIsLoading, isLoading)
            .disabled(isLoading)
    }

    /// Forces the focus ring on.
    ///
    /// The ring normally tracks `\.isFocused`, which iOS only sets under full keyboard access
    /// or an attached keyboard. A screen that drives focus itself, a form stepping through
    /// fields for instance, uses this to keep the visible ring and the real focus agreeing.
    func houseFocusRing(_ isFocused: Bool) -> some View {
        environment(\.houseButtonIsFocused, isFocused)
    }
}

// MARK: - Style

/// Flat. Fill, an optional dim hairline, an optional soft outer shadow.
///
/// No lit top edge, no inset specular highlight, no gradient sheen. That treatment is banned
/// outright and requires an explicit instruction for a specific element.
///
/// States: default, pressed, disabled, focused, loading.
struct HouseButtonStyle: ButtonStyle {
    var tier: HouseButtonTier = .neutral
    var size: HouseButtonSize = .medium
    /// Set for a destructive action, which tints the label without changing the tier.
    var role: SemanticRole?
    /// A button sitting on top of a card needs the deeper shadow to separate from it.
    var elevation: Elevation = .flat

    func makeBody(configuration: Configuration) -> some View {
        HouseButtonBody(configuration: configuration, tier: tier, size: size, role: role, elevation: elevation)
    }

    struct HouseButtonBody: View {
        let configuration: Configuration
        let tier: HouseButtonTier
        let size: HouseButtonSize
        let role: SemanticRole?
        let elevation: Elevation

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.houseButtonIsFocused) private var forcedFocus
        @Environment(\.houseButtonIsLoading) private var isLoading

        var body: some View {
            content
                .frame(minWidth: minimumWidth, minHeight: size.minimumSide)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(strokeColour, lineWidth: 1))
                .overlay(focusRing)
                .houseShadow(isEnabled ? elevation : .flat)
                .opacity(isEnabled ? 1 : 0.55)
                .contentShape(shape)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed { Haptics.impact(.light) }
                }
        }

        @ViewBuilder
        private var content: some View {
            ZStack {
                // The label is held in place while loading so the button cannot change width
                // mid-request, which would shift everything beside it.
                configuration.label
                    .typeRole(size.role)
                    .lineLimit(1)
                    .capTrim(size.role)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    RingSpinner(role: size.role, scale: 0.9)
                }
            }
            .foregroundStyle(foreground)
            .padding(.vertical, size.verticalPadding)
            .padding(.horizontal, tier == .icon ? size.verticalPadding : size.horizontalPadding)
        }

        private var minimumWidth: CGFloat? {
            tier == .icon ? size.minimumSide : nil
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: tier == .icon ? Radius.sm : size.cornerRadius, style: .continuous)
        }

        private var fill: Color {
            switch tier {
            case .accent:
                configuration.isPressed ? Theme.accent.opacity(0.82) : Theme.accent
            case .neutral:
                configuration.isPressed ? Theme.surface2 : Theme.surface1
            case .icon:
                configuration.isPressed ? Theme.surface2 : .clear
            }
        }

        private var foreground: Color {
            if !isEnabled { return Theme.ink3 }
            if let role, tier != .accent { return role.base }
            switch tier {
            case .accent: return Theme.accentInk
            case .neutral: return Theme.ink
            case .icon: return configuration.isPressed ? Theme.ink : Theme.ink2
            }
        }

        private var strokeColour: Color {
            switch tier {
            case .accent: .clear
            case .neutral: Theme.stroke
            case .icon: .clear
            }
        }

        @ViewBuilder
        private var focusRing: some View {
            if isFocused || forcedFocus {
                // Accent on accent would vanish, so the ring around the primary action is ink.
                shape
                    .inset(by: -3)
                    .strokeBorder(tier == .accent ? Theme.ink : Theme.accent, lineWidth: 2)
            }
        }
    }
}

// MARK: - Convenience

extension ButtonStyle where Self == HouseButtonStyle {
    /// Grey `surface1`. The default for every action that is not the screen's primary one.
    static var house: HouseButtonStyle { HouseButtonStyle(tier: .neutral, size: .medium) }

    /// Accent fill. At most one per screen.
    static var houseAccent: HouseButtonStyle { HouseButtonStyle(tier: .accent, size: .medium) }

    /// Square, icon only, transparent at rest.
    static var houseIcon: HouseButtonStyle { HouseButtonStyle(tier: .icon, size: .small) }

    static func house(
        _ tier: HouseButtonTier = .neutral,
        size: HouseButtonSize = .medium,
        role: SemanticRole? = nil,
        elevation: Elevation = .flat
    ) -> HouseButtonStyle {
        HouseButtonStyle(tier: tier, size: size, role: role, elevation: elevation)
    }
}

// MARK: - Label helper

/// An icon and its label on one optical centre line, with real air between them.
struct HouseButtonLabel: View {
    let title: String
    var icon: Icon?
    var role: TypeRole = .label

    var body: some View {
        HStack(spacing: role.size * 0.5) {
            if let icon {
                HouseIcon(icon: icon, role: role)
            }
            Text(title)
                .lineLimit(1)
        }
    }
}
