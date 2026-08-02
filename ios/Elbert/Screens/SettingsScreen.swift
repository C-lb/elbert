import SwiftUI

/// Task 15: iCloud status, an appearance choice, and an honest list of what wave 2 has not
/// shipped yet.
///
/// Nothing here is a placeholder. The sync card reports the container's real state rather than
/// assuming sync is on, and the "coming later" rows are static text, not buttons that go nowhere.
struct SettingsScreen: View {
    @AppStorage(AppearanceMode.storageKey) private var appearanceModeRaw = AppearanceMode.system.rawValue

    /// Read once: the health of the container the app is already running on does not change
    /// while Settings is on screen, so there is nothing to observe here.
    private let health = Persistence.health

    var body: some View {
        HouseScreen(title: "Settings") {
            syncSection
            appearanceSection
            comingLaterSection
        }
    }

    // MARK: - iCloud

    private var syncSection: some View {
        let status = SyncStatusDisplay.forHealth(health)

        return HouseCard {
            HStack(alignment: .top, spacing: Space.s3) {
                HouseIcon(icon: status.icon, role: .h3)
                    .foregroundStyle(status.role.base)

                VStack(alignment: .leading, spacing: Space.s2) {
                    HouseText(status.title, role: .h3)
                    HouseText(status.detail, role: .body, ink: \.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("Sync status")
        }
    }

    // MARK: - Appearance

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private var appearanceSection: some View {
        HouseCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HouseText("Appearance", role: .h3)

                Picker("Appearance", selection: appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("Appearance")
            }
        }
    }

    // MARK: - Coming later

    private static let unavailableFeatures = [
        "Learn mode",
        "Match mode",
        "Test mode",
        "AI card generation",
        "Import from CSV or .apkg",
        "Notifications",
        "Home Screen widgets",
    ]

    private var comingLaterSection: some View {
        HouseCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HouseText("Coming later", role: .h3)
                    HouseText(
                        "Wave 1 covers decks, notes, cards and spaced review. These land in a later wave.",
                        role: .caption,
                        ink: \.ink2
                    )
                }

                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(Self.unavailableFeatures, id: \.self) { feature in
                        UnavailableRow(title: feature)
                    }
                }
            }
        }
    }
}

/// One static row: a feature name and a quiet "not yet" tag. Deliberately not a `Button` — there
/// is nothing behind it to tap through to, and a control that looks live but does nothing is
/// worse than no control at all.
private struct UnavailableRow: View {
    let title: String

    var body: some View {
        HStack {
            HouseText(title, role: .body, ink: \.ink2)
            Spacer(minLength: Space.s3)
            HouseText("Not yet", role: .caption, ink: \.ink3)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Settings") {
    SettingsScreen().housePalette()
}
