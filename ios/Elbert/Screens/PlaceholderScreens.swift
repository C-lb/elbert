import SwiftUI

// Wave-1 stubs. Each is replaced wholesale by its own task: Decks in task 10, Study in task 13,
// Home in task 14, Settings in task 15. They exist now so the shell can be built and walked
// before any of them is real, and so the tab bar has four genuinely different destinations to
// switch between rather than one view shown four times.
//
// The copy says the screen is not built rather than pretending to be empty. A "no decks yet"
// message on a screen that cannot make a deck is a lie with a button on it.

struct HomeScreen: View {
    var body: some View {
        HouseScreen(title: "Home") {
            NotBuiltYet(icon: .home, what: "Due and new counts, and a way into today's session")
        }
    }
}

struct DeckListScreen: View {
    var body: some View {
        HouseScreen(title: "Decks") {
            NotBuiltYet(icon: .decks, what: "Your decks, with counts, and create, rename and delete")
        }
    }
}

struct StudyScreen: View {
    var body: some View {
        HouseScreen(title: "Study") {
            NotBuiltYet(icon: .study, what: "The review loop: card, reveal, and the four ratings")
        }
    }
}

struct SettingsScreen: View {
    var body: some View {
        HouseScreen(title: "Settings") {
            NotBuiltYet(icon: .settings, what: "iCloud status, theme, and what is not available yet")
        }
    }
}

private struct NotBuiltYet: View {
    let icon: Icon
    let what: String

    var body: some View {
        HouseEmptyState(
            icon: icon,
            title: "Not built yet",
            message: "\(what) lands here."
        )
    }
}

#Preview("Placeholders") {
    HomeScreen().housePalette()
}
