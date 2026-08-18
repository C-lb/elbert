import SwiftUI

/// Accessibility identifiers UI tests depend on.
///
/// A separate namespace rather than a static on `HouseScreen`, which is generic and so cannot hold
/// one, and a shared constant rather than a literal in two files, which is how a test starts
/// passing for the wrong reason.
enum ScreenID {
    /// The heading of whichever screen is showing. Deliberately the same on every screen: a test
    /// asks for the heading and reads its label, rather than knowing an identifier per screen.
    static let title = "screen-title"
}

/// The frame every screen sits in: canvas, a large title, and a scroll body on the house rhythm.
///
/// Screens supply content and nothing else. A screen that reaches past this for its own background
/// colour or its own horizontal padding is how a set of screens stops agreeing with itself.
struct HouseScreen<Content: View>: View {
    let title: String
    /// One optional primary action per screen, top right. This is the only place an accent fill is
    /// allowed to appear on a screen's chrome.
    var action: Action?

    /// An optional second action, sitting to the left of the primary. Deliberately `.icon` tier
    /// and never accent: a screen with two accent fills has no primary action, it has two buttons.
    var secondary: Action?

    @ViewBuilder var content: Content

    struct Action {
        let icon: Icon
        let label: String
        let perform: () -> Void
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                content
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            // The scroll content clears the tab bar on its own too. `safeAreaInset` handles the
            // bar's height, this is the breathing room after it.
            .padding(.bottom, Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvas)
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            HouseText(title, role: .h2)
                // The tab bar caption and the screen heading carry the same words, so a UI test
                // asking for "Decks" gets two elements and no way to tell which is which. This is
                // the heading.
                .accessibilityIdentifier(ScreenID.title)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Space.s3)

            // Declared after `action` but drawn before it, because the primary belongs furthest
            // right where the thumb lands. The property order only affects the initialiser.
            if let secondary {
                Button(action: secondary.perform) {
                    HouseIcon(icon: secondary.icon, role: .body)
                }
                .buttonStyle(HouseButtonStyle(tier: .icon, size: .small))
                .accessibilityLabel(secondary.label)
            }

            if let action {
                Button(action: action.perform) {
                    HouseIcon(icon: action.icon, role: .body)
                }
                .buttonStyle(HouseButtonStyle(tier: .accent, size: .small))
                .accessibilityLabel(action.label)
            }
        }
    }
}

/// What a screen shows when it has nothing to show.
///
/// An empty state is a real state, not a blank page: it says what is missing and, where there is
/// something to do about it, offers exactly one way to fix it.
struct HouseEmptyState: View {
    let icon: Icon
    let title: String
    let message: String
    var action: Action?

    struct Action {
        let label: String
        let perform: () -> Void
    }

    var body: some View {
        VStack(spacing: Space.s3) {
            HouseIcon(icon: icon, role: .display, scale: 1.2)
                .foregroundStyle(Theme.ink3)
                .padding(.bottom, Space.s1)

            HouseText(title, role: .h3, alignment: .center)

            HouseText(message, role: .body, ink: \.ink2, alignment: .center)
                // Measure capped, so a two-line message does not run the full width of a phone.
                .frame(maxWidth: 340)

            if let action {
                Button(action: action.perform) {
                    Text(action.label)
                        .lineLimit(1)
                }
                .buttonStyle(HouseButtonStyle(tier: .accent, size: .medium))
                .padding(.top, Space.s2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s7)
    }
}

#Preview("Screen with empty state") {
    HouseScreen(
        title: "Decks",
        action: .init(icon: .add, label: "New deck") {}
    ) {
        HouseEmptyState(
            icon: .decks,
            title: "No decks yet",
            message: "A deck holds the notes you want to remember. Make one to get started.",
            action: .init(label: "New deck") {}
        )
    }
    .housePalette()
}
