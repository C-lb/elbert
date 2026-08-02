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

    /// The appearance choice from Settings (task 15). `@AppStorage` publishes through the
    /// environment, so flipping it in Settings re-renders this view and `.preferredColorScheme`
    /// picks up the new value on the same frame — no relaunch, no foreground/background cycle.
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.system.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

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
                        .navigationDestination(for: DeckRoute.self, destination: destination)
                }
                .tag(tab)
            }
        }
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HouseTabBar(selection: $selection)
        }
        // `.preferredColorScheme` is a preference that propagates up to the window and gets
        // re-published scene-wide through `\.colorScheme`; modifier order here does not change
        // that mechanism. `nil` (System) hands the environment's `\.colorScheme` straight through
        // unchanged, which is what lets `.housePalette()` resolve off the system scheme in that
        // case and the overridden one otherwise.
        .preferredColorScheme(appearanceMode.colorScheme)
        .housePalette()
        .houseToast(toasts)
        .environment(toasts)
    }

    /// Routes are carried as deck ids rather than `Deck` objects, so a path that outlives the deck
    /// it points at resolves to nothing instead of holding a deleted model alive.
    @ViewBuilder
    private func destination(_ route: DeckRoute) -> some View {
        switch route {
        case .notes(let id): DeckLoader(deckID: id) { DeckNotesScreen(deck: $0) }
        case .settings(let id): DeckLoader(deckID: id) { DeckSettingsScreen(deck: $0) }
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        // Home's actions move you between tabs rather than pushing, so it needs the selection.
        case .home: HomeScreen(selectedTab: $selection)
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
