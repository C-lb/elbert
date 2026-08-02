import Testing

@testable import Elbert

// MARK: - Appearance

@Suite("Appearance mode")
struct AppearanceModeTests {
    @Test("System hands colour scheme control back rather than forcing one")
    func systemIsNil() {
        #expect(AppearanceMode.system.colorScheme == nil)
    }

    @Test("Light and Dark force their own scheme")
    func explicitSchemesForce() {
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test("round-trips through its raw value, the form it is persisted in")
    func roundTrips() {
        for mode in AppearanceMode.allCases {
            #expect(AppearanceMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test("an unrecognised stored value is not silently accepted as a mode")
    func unknownRawValueFailsToDecode() {
        #expect(AppearanceMode(rawValue: "sepia") == nil)
    }
}

// MARK: - Sync status

@Suite("Sync status display")
struct SyncStatusDisplayTests {
    @Test("syncing reports success and the synced glyph")
    func syncing() {
        let status = SyncStatusDisplay.forHealth(.syncing)
        #expect(status.role == .success)
        #expect(status.icon == .synced)
        #expect(status.title.localizedCaseInsensitiveContains("syncing"))
    }

    @Test("local-only never claims to be syncing, with or without a reason")
    func localOnlyIsHonest() {
        for reason in [nil, "The iCloud container is not registered."] {
            let status = SyncStatusDisplay.forHealth(.localOnly(reason: reason))
            #expect(!status.title.localizedCaseInsensitiveContains("sync"))
            #expect(status.icon == .cloudOff)
        }
    }

    @Test("a reason, when present, surfaces in the detail copy")
    func localOnlyReasonSurfaces() {
        let status = SyncStatusDisplay.forHealth(.localOnly(reason: "container missing"))
        #expect(status.detail.contains("container missing"))
    }

    @Test("ephemeral is flagged as danger, not a quieter role")
    func ephemeralIsDanger() {
        let status = SyncStatusDisplay.forHealth(.ephemeral(reason: "disk full"))
        #expect(status.role == .danger)
        #expect(status.detail.contains("disk full"))
    }

    @Test("every health case produces a distinct title")
    func titlesAreDistinct() {
        let titles = Set([
            SyncStatusDisplay.forHealth(.syncing).title,
            SyncStatusDisplay.forHealth(.localOnly(reason: nil)).title,
            SyncStatusDisplay.forHealth(.ephemeral(reason: "x")).title,
        ])
        #expect(titles.count == 3)
    }
}
