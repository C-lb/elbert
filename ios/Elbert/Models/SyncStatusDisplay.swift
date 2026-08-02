import Foundation

/// What Settings says about `StoreHealth`, in words a non-engineer can act on.
///
/// Split out from the view so the mapping is a pure function a test can call without standing up
/// SwiftUI: `StoreHealth` in, copy out, no environment required.
struct SyncStatusDisplay: Equatable {
    let title: String
    let detail: String
    let icon: Icon
    let role: SemanticRole

    static func forHealth(_ health: StoreHealth) -> SyncStatusDisplay {
        switch health {
        case .syncing:
            return SyncStatusDisplay(
                title: "Syncing with iCloud",
                detail: "Cards mirror to your iCloud private database and follow you to your other devices.",
                icon: .synced,
                role: .success
            )

        case .localOnly(let reason):
            return SyncStatusDisplay(
                title: "Local only",
                detail: reason.map {
                    "iCloud sync is off. \($0) Your cards are still saved on this device."
                } ?? "iCloud sync is off. Your cards are saved on this device and will not follow you to another one.",
                icon: .cloudOff,
                role: .info
            )

        case .ephemeral(let reason):
            return SyncStatusDisplay(
                title: "Not saving",
                detail: "Nothing is being written to disk (\(reason)). Cards will be lost when Elbert quits.",
                icon: .problem,
                role: .danger
            )
        }
    }
}
