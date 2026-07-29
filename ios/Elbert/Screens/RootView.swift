import SwiftUI

/// The app shell: four tabs, each with its own navigation stack, over one tab bar.
///
/// `TabView` does the switching, with its own bar hidden and `HouseTabBar` drawn in its place.
/// That split is deliberate. The house rules want things `TabView`'s bar will not give up (the
/// fill swap as the entire current-state signal, a 1.6em icon over a 0.68 caption, no accent
/// anywhere), but the *container* semantics are worth keeping: each tab holds its state, and an
/// off-screen tab is genuinely out of the accessibility tree.
///
/// Hand-rolling the container instead, as a `ZStack` of four stacks with `.opacity`, looks
/// identical and is subtly broken: `.accessibilityHidden(true)` does not reach into a
/// `UIViewRepresentable` subtree, so `HouseText`'s `UILabel` stays visible to VoiceOver and all
/// four screen headings are exposed at once. XCUITest found that by refusing to pick between four
/// identical headings, which is the same complaint a screen reader user would have.
struct RootView: View {
    @State private var selection: AppTab = .home

    /// One navigation path per tab, so a push in Decks cannot appear in Study.
    @State private var paths: [AppTab: NavigationPath] = [:]

    @State private var toasts = ToastCentre()

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: path(for: tab)) {
                    screen(for: tab)
                        // Swipe-back is `NavigationStack`'s own and the large title is the
                        // screen's, so the system bar has nothing left to draw. The tab bar is
                        // hidden here, on the content, because that is where the modifier looks
                        // for the bar to hide.
                        .toolbar(.hidden, for: .navigationBar)
                        .toolbar(.hidden, for: .tabBar)
                }
                .tag(tab)
            }
        }
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HouseTabBar(selection: $selection)
        }
        .housePalette()
        .houseToast(toasts)
        .environment(toasts)
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeScreen()
        case .decks: DeckListScreen()
        case .study: StudyScreen()
        case .settings: SettingsScreen()
        }
    }

    /// A binding that treats a missing entry as an empty path, so a tab does not need its path
    /// seeded before it can be pushed onto.
    private func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { paths[tab] ?? NavigationPath() },
            set: { paths[tab] = $0 }
        )
    }
}

#Preview("Shell") {
    RootView()
        .modelContainer(for: Deck.self, inMemory: true)
}
