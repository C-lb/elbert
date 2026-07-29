import Foundation
import SwiftData
import Testing

@testable import Elbert

// The CloudKit mirror will not tell you it is unhappy until the first sync on a real device,
// which is late. These tests stand in for that feedback: they open the real schema, exercise the
// invariants section 5 of the spec calls non-negotiable, and prove the store round-trips across
// container instances rather than only within one.

@MainActor
private func freshContext() throws -> ModelContext {
    ModelContext(try Persistence.inMemoryContainer())
}

// MARK: - CloudKit constraints

@Suite("CloudKit model constraints")
@MainActor
struct CloudKitConstraintTests {
    /// Constraint 2: every property optional or defaulted. If any model gained a property with
    /// neither, one of these no-argument initialisers stops compiling, which is the point.
    @Test("every model constructs with no arguments")
    func defaultsExistEverywhere() {
        _ = Deck()
        _ = Note()
        _ = Card()
        _ = Review()
        _ = MediaAsset()
    }

    @Test("the schema opens, so no unsupported attribute slipped in")
    func schemaOpens() throws {
        _ = try Persistence.inMemoryContainer()
        #expect(Persistence.schema.entities.count == 5)
    }

    /// Constraint 1: identity is a plain `UUID`, not a unique constraint. Two rows with the same
    /// `id` must be storable, because the mirror would accept them anyway and pretending
    /// otherwise would just mean the duplicate surfaces later, on a different device.
    @Test("duplicate ids are storable, de-duplication is application logic")
    func duplicateIDsAreNotRejected() throws {
        let context = try freshContext()
        let shared = UUID()
        context.insert(Deck(id: shared, name: "One"))
        context.insert(Deck(id: shared, name: "Two"))
        try context.save()

        let decks = try context.fetch(FetchDescriptor<Deck>())
        #expect(decks.count == 2)
    }

    /// The container id has to match the entitlement in `Elbert.entitlements` exactly, and a typo
    /// in either is only visible as sync silently never happening.
    @Test("the CloudKit container id matches the entitlement")
    func containerIDMatchesEntitlement() {
        #expect(Persistence.cloudKitContainerID == "iCloud.com.calebl.elbert")
    }

    @Test("a store opened without CloudKit reports itself as local only")
    func healthReflectsNoCloudKit() throws {
        #if !ELBERT_CLOUDKIT
        // `shared` is what the app runs on. Touching it here is what proves the fallback path
        // opens a real store rather than dropping to ephemeral.
        _ = Persistence.shared
        #expect(Persistence.health == .localOnly(reason: nil))
        #endif
    }
}

// MARK: - Enums

@Suite("Enum raw values")
struct EnumRawValueTests {
    /// Task 4 onwards lifts test cases straight out of the TypeScript specs, which only works if
    /// the spellings match `src/data/types.ts`.
    @Test("note types keep the web app's spelling")
    func noteTypeRawValues() {
        #expect(NoteType.basic.rawValue == "basic")
        #expect(NoteType.basicReversed.rawValue == "basic_reversed")
        #expect(NoteType.cloze.rawValue == "cloze")
    }

    @Test("card states match ts-fsrs")
    func cardStateRawValues() {
        #expect(CardState.new.rawValue == 0)
        #expect(CardState.learning.rawValue == 1)
        #expect(CardState.review.rawValue == 2)
        #expect(CardState.relearning.rawValue == 3)
    }

    @Test("ratings match ts-fsrs")
    func ratingRawValues() {
        #expect(Rating.again.rawValue == 1)
        #expect(Rating.hard.rawValue == 2)
        #expect(Rating.good.rawValue == 3)
        #expect(Rating.easy.rawValue == 4)
    }

    @Test("only learning and relearning count as learning")
    func learningStates() {
        #expect(CardState.learning.isLearning)
        #expect(CardState.relearning.isLearning)
        #expect(!CardState.new.isLearning)
        #expect(!CardState.review.isLearning)
    }

    /// An unrecognised raw value has to fall back rather than crash: a newer version of the app on
    /// another device can write a value this build has never heard of, and CloudKit will hand it over.
    @Test("unknown raw values fall back instead of trapping")
    @MainActor
    func unknownRawValuesFallBack() throws {
        let context = try freshContext()
        let note = Note(term: "t")
        let card = Card()
        context.insert(note)
        context.insert(card)
        note.typeRaw = "quantum"
        card.stateRaw = 99
        try context.save()

        #expect(note.type == .basic)
        #expect(card.state == .new)
    }
}

// MARK: - Relationships

@Suite("Relationships")
@MainActor
struct RelationshipTests {
    @Test("inverses wire up in both directions")
    func inversesWire() throws {
        let context = try freshContext()
        let deck = Deck(name: "Japanese")
        let note = Note(term: "犬", definition: "dog", deck: deck)
        let card = Card(ord: 0, note: note)
        context.insert(deck)
        context.insert(note)
        context.insert(card)
        try context.save()

        #expect(deck.notes?.count == 1)
        #expect(note.deck?.id == deck.id)
        #expect(note.cards?.count == 1)
        #expect(card.note?.id == note.id)
    }

    @Test("deleting a note takes its cards and their reviews with it")
    func noteCascades() throws {
        let context = try freshContext()
        let note = Note(term: "t")
        let card = Card(note: note)
        let review = Review(rating: .good, card: card)
        context.insert(note)
        context.insert(card)
        context.insert(review)
        try context.save()

        context.delete(note)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Card>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Review>()).isEmpty)
    }

    @Test("deleting a deck takes its notes with it")
    func deckCascadesToNotes() throws {
        let context = try freshContext()
        let deck = Deck(name: "Doomed")
        let note = Note(term: "t", deck: deck)
        context.insert(deck)
        context.insert(note)
        try context.save()

        context.delete(deck)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
    }

    /// The deliberate exception to cascade. Deck deletion has no undo, so a subdeck is promoted to
    /// the top level rather than quietly deleted along with its parent.
    @Test("deleting a parent deck promotes its subdecks instead of deleting them")
    func subdecksArePromoted() throws {
        let context = try freshContext()
        let parent = Deck(name: "Language")
        let child = Deck(name: "Japanese", parent: parent)
        context.insert(parent)
        context.insert(child)
        try context.save()

        context.delete(parent)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Deck>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.name == "Japanese")
        #expect(remaining.first?.parent == nil)
    }
}

// MARK: - Review snapshot

@Suite("Review snapshot")
@MainActor
struct ReviewSnapshotTests {
    @Test("a snapshot survives a store round trip")
    func snapshotRoundTrips() throws {
        let context = try freshContext()
        let reviewedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let card = Card(
            due: reviewedAt,
            stability: 12.5,
            difficulty: 6.25,
            reps: 3,
            lapses: 1,
            learningSteps: 2,
            state: .review,
            lastReview: reviewedAt
        )
        context.insert(card)

        let review = Review(rating: .hard, elapsedMs: 4200, snapshot: CardSnapshot(card: card), card: card)
        context.insert(review)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<Review>()).first)
        let snapshot = try #require(stored.snapshot)
        #expect(snapshot.stability == 12.5)
        #expect(snapshot.difficulty == 6.25)
        #expect(snapshot.reps == 3)
        #expect(snapshot.lapses == 1)
        #expect(snapshot.learningSteps == 2)
        #expect(snapshot.state == .review)
        #expect(stored.rating == .hard)
        #expect(stored.elapsedMs == 4200)
    }

    @Test("no snapshot decodes to nil rather than throwing")
    func missingSnapshotIsNil() {
        #expect(Review().snapshot == nil)
    }

    @Test("corrupt snapshot data decodes to nil rather than throwing")
    func corruptSnapshotIsNil() {
        let review = Review()
        review.snapshotData = Data("not json".utf8)
        #expect(review.snapshot == nil)
    }
}

// MARK: - Durability

@Suite("Durability")
@MainActor
struct DurabilityTests {
    /// The task 3 acceptance check, minus the manual relaunch: write a deck, throw the container
    /// away, open a new one over the same file, and the deck is still there.
    @Test("a deck written to disk is still there after the container is rebuilt")
    func survivesContainerRebuild() throws {
        let url = URL.temporaryDirectory.appending(path: "elbert-durability-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let configuration = ModelConfiguration(
            schema: Persistence.schema,
            url: url,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: Persistence.schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(Deck(name: "Persisted", newPerDay: 7, desiredRetention: 0.85))
            try context.save()
        }

        let reopened = try ModelContainer(for: Persistence.schema, configurations: [configuration])
        let context = ModelContext(reopened)
        let deck = try #require(try context.fetch(FetchDescriptor<Deck>()).first)
        #expect(deck.name == "Persisted")
        #expect(deck.newPerDay == 7)
        #expect(deck.desiredRetention == 0.85)
    }

    /// Also the regression test for the `hash` name collision: the content hash is read back
    /// through key-value coding, which is where a property named `hash` blew up with an
    /// `NSNumber` to `NSString` cast failure rather than a compile error.
    @Test("an image blob round trips through external storage")
    func mediaRoundTrips() throws {
        let context = try freshContext()
        let bytes = Data((0..<2048).map { UInt8($0 % 251) })
        context.insert(MediaAsset(contentHash: "abc123", data: bytes, mime: "image/png"))
        try context.save()

        let asset = try #require(try context.fetch(FetchDescriptor<MediaAsset>()).first)
        #expect(asset.contentHash == "abc123")
        #expect(asset.data == bytes)
        #expect(asset.mime == "image/png")
    }

    /// Content-hash lookup is how de-duplication works without a unique constraint, so it has to
    /// survive being expressed as a store-level predicate, not just an in-memory filter.
    @Test("assets are findable by content hash")
    func mediaFoundByHash() throws {
        let context = try freshContext()
        context.insert(MediaAsset(contentHash: "aaa", mime: "image/png"))
        context.insert(MediaAsset(contentHash: "bbb", mime: "image/png"))
        try context.save()

        let wanted = "bbb"
        let descriptor = FetchDescriptor<MediaAsset>(predicate: #Predicate { $0.contentHash == wanted })
        let found = try context.fetch(descriptor)
        #expect(found.count == 1)
        #expect(found.first?.contentHash == "bbb")
    }
}
