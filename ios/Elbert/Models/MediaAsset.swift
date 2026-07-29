import Foundation
import SwiftData

/// An image attached to a note, addressed by content hash.
///
/// `contentHash` is what makes the same picture pasted into three notes cost one copy. It cannot
/// be an `@Attribute(.unique)` because the CloudKit mirror rejects unique constraints, so the
/// caller looks up by hash before inserting. That check is not atomic across devices, meaning two
/// devices can each mint a row for the same image; the cost is a duplicate blob, not a bug, and
/// de-duplication can happen later.
///
/// The property is deliberately *not* called `hash`. SwiftData reaches persisted properties
/// through Objective-C key-value coding, and `hash` is already `NSObject`'s `Int` identity hash,
/// so a `String` under that name crashes at read time with an `NSNumber` to `NSString` cast
/// failure. It surfaces on first fetch, not at compile time.
@Model
final class MediaAsset {
    var id: UUID = UUID()

    /// Lowercase hex SHA-256 of ``data``.
    var contentHash: String = ""

    /// External storage keeps the blob out of the SQLite file, which matters once a deck has a
    /// few hundred images in it.
    @Attribute(.externalStorage)
    var data: Data?

    var mime: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        contentHash: String = "",
        data: Data? = nil,
        mime: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.contentHash = contentHash
        self.data = data
        self.mime = mime
        self.createdAt = createdAt
    }
}
