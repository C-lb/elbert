import SwiftUI

/// The bottom tab bar, in the thumb zone.
///
/// Built by hand rather than with SwiftUI's `TabView` because the house rules want things
/// `TabView` will not give up: the fill swap as the *entire* current-state signal, an icon at
/// 1.6em over a caption at 0.68 of base, and no accent anywhere in the bar. `TabView` insists on
/// tinting the selected item and sizing its own glyphs.
///
/// The bar does not position itself. `RootView` hands it to `.safeAreaInset(edge: .bottom)`, which
/// is what makes every scroll view above it pad by exactly the bar's height, home indicator
/// included, instead of hiding its last row underneath.
struct HouseTabBar: View {
    @Binding var selection: AppTab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The icon is the target and the word is a caption for it, so the icon runs large. Both are
    /// sized off the base type size rather than off each other, so the ratio survives a role edit.
    private static let iconScale: CGFloat = 1.6

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                TabBarItem(tab: tab, isCurrent: tab == selection) {
                    guard tab != selection else { return }
                    Haptics.selection()
                    if reduceMotion {
                        selection = tab
                    } else {
                        withAnimation(.snappy(duration: 0.18)) { selection = tab }
                    }
                }
            }
        }
        .padding(.top, Space.s2)
        .background(alignment: .top) {
            // A hairline, not a shadow. The bar sits under the content rather than floating over
            // it, and a drop shadow pointing up would claim an elevation it does not have.
            Theme.stroke.frame(height: 1)
        }
        .background(Theme.surface1)
        .zIndex(ZLayer.stickyChrome)
    }

    private struct TabBarItem: View {
        let tab: AppTab
        let isCurrent: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: Space.s1) {
                    HouseIcon(
                        icon: tab.icon,
                        filled: isCurrent,
                        role: .body,
                        scale: HouseTabBar.iconScale
                    )
                    .foregroundStyle(isCurrent ? Theme.ink : Theme.ink2)

                    Text(tab.title)
                        .typeRole(.labelSmall)
                        // The caption is one ink step quieter than its icon, at rest and current
                        // alike. It labels the glyph; it does not compete with it.
                        .foregroundStyle(isCurrent ? Theme.ink2 : Theme.ink3)
                        .lineLimit(1)
                }
                // 44pt is the floor for a tap target, and a tab bar is the last place to skimp.
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(TabBarItemStyle())
            .accessibilityLabel(tab.title)
            // The tab-bar equivalent of aria-current: the accessible state and the fill can never
            // drift apart, because both read the same value.
            .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        }
    }

    /// Every interactive element answers a press. A tab has no hover, so the press response is the
    /// whole feedback budget: the item dims, and nothing moves.
    private struct TabBarItemStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.55 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

#Preview("Tab bar") {
    struct Harness: View {
        @State private var selection: AppTab = .home

        var body: some View {
            VStack {
                Spacer()
                HouseTabBar(selection: $selection)
            }
            .background(Theme.canvas)
            .housePalette()
        }
    }

    return Harness()
}
