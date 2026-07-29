import Foundation
import SwiftData

/// The thing a person actually writes. Cards are generated from it, never the other way round.
///
/// The web app nests the writable fields in a `fields` object; here they are flat properties,
/// because a nested struct would be one more thing for the CloudKit mirror to flatten and the
/// nesting bought nothing. Optional fields stay genuinely optional: `Engine/EditorRow` (task 12)
/// clears them to `nil` rather than storing an empty string, per spec section 6.
@Model
final class Note {
    var id: UUID = UUID()

    /// Backing store for ``type``. Persisted as the raw string, never as the enum.
    var typeRaw: String = NoteType.basic.rawValue

    var term: String = ""
    var definition: String = ""
    var example: String?
    var hint: String?

    /// Points at a ``MediaAsset/id``. Deliberately a loose reference rather than a relationship:
    /// one image can be shared by many notes, and a relationship would make deleting a note
    /// entangled with reference counting an asset it does not own.
    var imageAssetID: UUID?

    var tags: [String] = []
    var createdAt: Date = Date()

    var deck: Deck?

    @Relationship(deleteRule: .cascade, inverse: \Card.note)
    var cards: [Card]?

    var type: NoteType {
        get { NoteType(rawValue: typeRaw) ?? .basic }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        type: NoteType = .basic,
        term: String = "",
        definition: String = "",
        example: String? = nil,
        hint: String? = nil,
        imageAssetID: UUID? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        deck: Deck? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.term = term
        self.definition = definition
        self.example = example
        self.hint = hint
        self.imageAssetID = imageAssetID
        self.tags = tags
        self.createdAt = createdAt
        self.deck = deck
        self.cards = []
    }
}
