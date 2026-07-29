import Foundation
import SwiftData

/// A deck of notes. Decks nest one level or many, via `parent`.
///
/// Every stored property has a default and every relationship is optional with a declared
/// inverse, which is what the CloudKit mirror requires. `id` is a plain `UUID` with no
/// `@Attribute(.unique)`, because the mirror rejects unique constraints outright, so
/// de-duplication is application logic rather than a database guarantee.
@Model
final class Deck {
    var id: UUID = UUID()
    var name: String = ""
    var newPerDay: Int = 20
    var desiredRetention: Double = 0.9
    var createdAt: Date = Date()

    var parent: Deck?

    /// Deleting a parent promotes its subdecks to the top level rather than deleting them.
    ///
    /// Cascade would be the tidier graph, but deck deletion has no undo (spec section 8), and
    /// silently taking a whole subtree with it is the kind of loss a confirmation dialog does
    /// not really warn about. An orphaned subdeck is recoverable; a deleted one is not.
    @Relationship(deleteRule: .nullify, inverse: \Deck.parent)
    var children: [Deck]?

    /// Notes, on the other hand, do cascade. A note has no meaning outside its deck.
    @Relationship(deleteRule: .cascade, inverse: \Note.deck)
    var notes: [Note]?

    init(
        id: UUID = UUID(),
        name: String = "",
        newPerDay: Int = 20,
        desiredRetention: Double = 0.9,
        createdAt: Date = Date(),
        parent: Deck? = nil
    ) {
        self.id = id
        self.name = name
        self.newPerDay = newPerDay
        self.desiredRetention = desiredRetention
        self.createdAt = createdAt
        self.parent = parent
        self.children = []
        self.notes = []
    }
}
