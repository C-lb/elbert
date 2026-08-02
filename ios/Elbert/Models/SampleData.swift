import Foundation
import SwiftData

/// Decks written from real lecture slides, for building and walking screens against something
/// other than "Deck 1" and "Note 2".
///
/// Off by default. It loads when the app is launched with `-seedSampleData`, which is how the
/// simulator walks and the UI tests get content, and never in an ordinary launch. Promoting these
/// to starter decks that ship on first launch is a change to ``seedIfRequested(into:)`` and
/// nothing else: the JSON already travels in the bundle either way, which is worth knowing before
/// shipping, since it is someone else's course material.
///
/// Provenance is `ios/Tools/extract-slides.py`, plus the source list inside the JSON.
enum SampleData {
    static let launchArgument = "-seedSampleData"

    /// Empties the store on launch without seeding anything into it.
    ///
    /// XCUITest never resets the data container between tests — only `-seedSampleData` does that,
    /// by resetting and then seeding. A walk that wants to prove something about content it
    /// creates itself (rather than the samples) still needs a known-empty starting point, or it
    /// silently inherits whatever an earlier test in the run left behind: leftover decks, and a
    /// `NewCardCounter` allowance in `UserDefaults` that an earlier test already spent, which
    /// changes which decks the Study queue serves first.
    static let resetLaunchArgument = "-resetStore"

    private static let resourceName = "SampleDecks"

    // MARK: - Decoding

    private struct File: Decodable {
        let decks: [SampleDeck]
    }

    struct SampleDeck: Decodable {
        let name: String
        let newPerDay: Int
        let desiredRetention: Double
        let notes: [SampleNote]
    }

    struct SampleNote: Decodable {
        let type: String
        let term: String
        let definition: String
        var example: String?
        var hint: String?
        var tags: [String] = []

        var noteType: NoteType {
            // The JSON uses Swift's spelling of the case, not the web app's raw value, because it
            // is written by hand and `basicReversed` is what an author would type.
            switch type {
            case "basicReversed": .basicReversed
            case "cloze": .cloze
            default: .basic
            }
        }
    }

    // MARK: - Loading

    /// Reads the bundled decks. Throws rather than returning empty, because a decode failure is a
    /// malformed resource in the app's own bundle, and quietly seeding nothing would look exactly
    /// like the flag not being passed.
    static func bundledDecks(from bundle: Bundle = .main) throws -> [SampleDeck] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw SampleDataError.resourceMissing(resourceName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(File.self, from: data).decks
    }

    /// Resets the store to exactly the sample decks, if the launch argument is present.
    ///
    /// Reset rather than top-up, and that is the important part. The flag means "put the app in a
    /// known state", so a walk starts the same way every time and a UI test cannot inherit what
    /// the test before it did. Topping up instead would make the second launch depend on the
    /// first, which is exactly the bug this is here to avoid.
    ///
    /// The day counter goes too: it lives in `UserDefaults`, not the store, so a fresh set of
    /// decks would otherwise inherit an allowance a previous run had already spent.
    @MainActor
    @discardableResult
    static func seedIfRequested(
        into context: ModelContext,
        arguments: [String] = CommandLine.arguments,
        counter: NewCardCounter = NewCardCounter()
    ) -> Bool {
        guard arguments.contains(launchArgument) else { return false }

        do {
            try reset(context)
            counter.resetAll()
            try seed(try bundledDecks(), into: context)
            return true
        } catch {
            // A broken sample file must not take the app down: the flag is a development
            // convenience, and failing loudly in the log is the right volume for it.
            print("Sample data failed to load: \(error)")
            return false
        }
    }

    /// Empties the store if `-resetStore` is present, and does nothing if `-seedSampleData` is
    /// also present — that flag already resets on its own path, and running both would just
    /// reset twice for no reason.
    @MainActor
    @discardableResult
    static func resetIfRequested(
        into context: ModelContext,
        arguments: [String] = CommandLine.arguments,
        counter: NewCardCounter = NewCardCounter()
    ) -> Bool {
        guard arguments.contains(resetLaunchArgument), !arguments.contains(launchArgument) else { return false }

        do {
            try reset(context)
            counter.resetAll()
            return true
        } catch {
            // Same volume as the sample-data failure above: a development convenience failing
            // loudly in the log, not taking the app down.
            print("Store reset failed: \(error)")
            return false
        }
    }

    /// Empties the store. Deck deletion cascades to notes, cards and reviews, so the rest of the
    /// sweep is for rows that were orphaned rather than owned.
    @MainActor
    static func reset(_ context: ModelContext) throws {
        for deck in try context.fetch(FetchDescriptor<Deck>()) { context.delete(deck) }
        for note in try context.fetch(FetchDescriptor<Note>()) { context.delete(note) }
        for card in try context.fetch(FetchDescriptor<Card>()) { context.delete(card) }
        for review in try context.fetch(FetchDescriptor<Review>()) { context.delete(review) }
        for asset in try context.fetch(FetchDescriptor<MediaAsset>()) { context.delete(asset) }
        try context.save()
    }

    /// Inserts decks, notes, and the cards each note produces.
    ///
    /// Cards come from `CardsFromNote` rather than being described in the JSON, so seeded content
    /// goes through exactly the path the editor uses. A sample deck that disagreed with the
    /// engine would be worse than no sample deck.
    @MainActor
    static func seed(_ decks: [SampleDeck], into context: ModelContext) throws {
        for sample in decks {
            let deck = Deck(
                name: sample.name,
                newPerDay: sample.newPerDay,
                desiredRetention: sample.desiredRetention
            )
            context.insert(deck)

            for sampleNote in sample.notes {
                let note = Note(
                    type: sampleNote.noteType,
                    term: sampleNote.term,
                    definition: sampleNote.definition,
                    example: sampleNote.example,
                    hint: sampleNote.hint,
                    tags: sampleNote.tags,
                    deck: deck
                )
                context.insert(note)

                for card in CardsFromNote.cards(for: note) {
                    context.insert(card)
                }
            }
        }
        try context.save()
    }
}

enum SampleDataError: Error, CustomStringConvertible {
    case resourceMissing(String)

    var description: String {
        switch self {
        case .resourceMissing(let name): "\(name).json is not in the app bundle"
        }
    }
}
