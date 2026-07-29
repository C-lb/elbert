import SwiftUI
import UIKit

@main
struct ElbertApp: App {
    init() {
        Self.logRegisteredFontFamilies()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }

    /// Task 1 scaffold check: confirms the bundled DM Sans actually registers at runtime.
    /// Remove once `Design/Typography.swift` lands in task 2.
    private static func logRegisteredFontFamilies() {
        let families = UIFont.familyNames.sorted()
        print("[Elbert] registered font families: \(families)")
        let dmSans = families.filter { $0.localizedCaseInsensitiveContains("DM Sans") }
        print("[Elbert] DM Sans families: \(dmSans)")
        for family in dmSans {
            print("[Elbert] DM Sans font names: \(UIFont.fontNames(forFamilyName: family))")
        }
    }
}

struct RootView: View {
    var body: some View {
        Text("Elbert")
    }
}

#Preview {
    RootView()
}
