import SwiftUI

@main
struct ElbertApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        // Temporary for task 2. The real shell, a bottom tab bar over four
        // `NavigationStack`s, arrives in task 9 and replaces this.
        DesignGallery()
    }
}

#Preview {
    RootView()
}
