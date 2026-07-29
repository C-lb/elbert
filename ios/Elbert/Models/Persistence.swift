import Foundation
import SwiftData

/// How the live store ended up being opened.
///
/// Surfaced by Settings (task 15) rather than hidden, because "my cards are not syncing" and
/// "my cards are not saving" are very different problems and the app should be able to say which
/// one it is having.
enum StoreHealth: Sendable, Equatable {
    /// Local file, mirroring to the iCloud private database.
    case syncing
    /// Local file only. Either CloudKit is compiled out or the container refused to open.
    case localOnly(reason: String?)
    /// Nothing on disk would open. Data lasts until the app quits.
    case ephemeral(reason: String)

    var isSyncing: Bool { self == .syncing }
}

/// Owns the app's `ModelContainer`.
///
/// CloudKit is behind the `ELBERT_CLOUDKIT` compilation condition, off by default. The iCloud
/// container `iCloud.com.calebl.elbert` still has to be registered in the Apple developer console
/// and the capability added to the target (spec section 10, item 1). Until that exists, a build
/// carrying the entitlement fails to sign, so the flag stays off and the app runs on a local
/// store. Turning it on is two edits, both documented in `ios/README.md`.
enum Persistence {
    static let cloudKitContainerID = "iCloud.com.calebl.elbert"

    static let schema = Schema([
        Deck.self,
        Note.self,
        Card.self,
        Review.self,
        MediaAsset.self,
    ])

    #if ELBERT_CLOUDKIT
    static let configuredDatabase: ModelConfiguration.CloudKitDatabase = .private(cloudKitContainerID)
    #else
    static let configuredDatabase: ModelConfiguration.CloudKitDatabase = .none
    #endif

    @MainActor private(set) static var health: StoreHealth = .localOnly(reason: nil)

    /// The container the app runs on. Created once, on first use.
    @MainActor static let shared: ModelContainer = makeShared()

    /// A throwaway container for tests and previews. Never touches disk or iCloud.
    static func inMemoryContainer() throws -> ModelContainer {
        try container(database: .none, inMemory: true)
    }

    static func container(
        database: ModelConfiguration.CloudKitDatabase,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: database
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Opens the best store available, degrading rather than crashing.
    ///
    /// A `fatalError` here would mean an unregistered iCloud container, a full disk, or a schema
    /// the existing file cannot migrate to all present as the app simply refusing to launch, with
    /// nothing on screen to say why. Falling back and recording the reason is worth the extra
    /// branch.
    @MainActor private static func makeShared() -> ModelContainer {
        #if ELBERT_CLOUDKIT
        do {
            let container = try container(database: configuredDatabase)
            health = .syncing
            return container
        } catch {
            return makeLocal(cloudKitFailure: error.localizedDescription)
        }
        #else
        return makeLocal(cloudKitFailure: nil)
        #endif
    }

    @MainActor private static func makeLocal(cloudKitFailure: String?) -> ModelContainer {
        do {
            let container = try container(database: .none)
            health = .localOnly(reason: cloudKitFailure)
            return container
        } catch {
            let reason = error.localizedDescription
            health = .ephemeral(reason: reason)
            do {
                return try inMemoryContainer()
            } catch {
                // An in-memory store failing means the schema itself is invalid, which is a
                // programmer error no fallback can paper over.
                fatalError("Elbert could not open any store. Schema is invalid: \(error)")
            }
        }
    }
}
