import SwiftData
import SwiftUI

@main
struct ElbertApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // No-op unless the app was launched with `-seedSampleData`. See SampleData.
                    SampleData.seedIfRequested(into: Persistence.shared.mainContext)
                }
        }
        .modelContainer(Persistence.shared)
    }
}

