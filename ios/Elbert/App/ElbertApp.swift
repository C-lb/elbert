import SwiftData
import SwiftUI

@main
struct ElbertApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Persistence.shared)
    }
}

