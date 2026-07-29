import SwiftUI

/// The last wave-1 stub. Settings is task 15.
///
/// The copy says the screen is not built rather than pretending to be empty. A "nothing here yet"
/// message on a screen that cannot act is a lie with a button on it.
struct SettingsScreen: View {
    var body: some View {
        HouseScreen(title: "Settings") {
            HouseEmptyState(
                icon: .settings,
                title: "Not built yet",
                message: "iCloud status, theme, and what is not available yet lands here."
            )
        }
    }
}

#Preview("Settings") {
    SettingsScreen().housePalette()
}
