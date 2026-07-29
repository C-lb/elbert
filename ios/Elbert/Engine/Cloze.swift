import Foundation

/// One cloze deletion in a note, identified by its ordinal.
///
/// A note produces one card per distinct ordinal, so `{{c1::…}}` appearing three times is still
/// one card with three blanks on it.
struct ClozeDeletion: Equatable, Sendable, Identifiable {
    let ord: Int
    let hint: String?

    var id: Int { ord }
}

/// Cloze syntax: `{{c<n>::answer}}` or `{{c<n>::answer::hint}}`.
///
/// Port of `src/engine/cloze.ts`. Same regex, same non-greedy matching, same de-duplication rule,
/// so the TypeScript cases carry over unchanged. Two deliberate differences from the web version
/// are marked below, both places where the original was inconsistent with itself.
enum Cloze {
    /// `.*?` is lazy so `{{c1::a}} {{c2::b}}` is two matches, not one spanning both. The hint
    /// group is optional, which is why a bare `{{c1::a}}` still matches.
    ///
    /// Deliberately not `dotMatchesLineSeparators`: JavaScript's `.` stops at a newline and a
    /// cloze that swallowed the rest of the note would be worse than one that failed to match.
    ///
    /// `nonisolated(unsafe)` because `Regex` is immutable once built but not marked `Sendable`.
    /// Matching never mutates it, and the alternative under strict concurrency is rebuilding the
    /// regex on every keystroke of the editor's live cloze preview.
    nonisolated(unsafe) private static let pattern = /\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}/

    /// Every distinct ordinal in `text`, ascending.
    ///
    /// A repeated ordinal keeps the *first* occurrence's hint, so the hint a person wrote next to
    /// the first blank is the one they get, rather than whichever happened to come last.
    static func parse(_ text: String) -> [ClozeDeletion] {
        var byOrdinal: [Int: ClozeDeletion] = [:]

        for match in text.matches(of: pattern) {
            // A number too large for `Int` is not a real ordinal, it is a typo. Skipping it leaves
            // the text alone rather than minting a card nobody asked for.
            guard let ord = Int(match.1), !byOrdinal.keys.contains(ord) else { continue }
            byOrdinal[ord] = ClozeDeletion(ord: ord, hint: hint(from: match.3))
        }

        return byOrdinal.values.sorted { $0.ord < $1.ord }
    }

    /// The note text as it appears on the card for `ord`.
    ///
    /// The target ordinal shows `[hint]`, or `[...]` if there is no hint, until it is revealed.
    /// Every other ordinal shows its answer, because the other blanks are context, not questions.
    static func render(_ text: String, ord: Int, revealed: Bool) -> String {
        var out = ""
        var cursor = text.startIndex

        for match in text.matches(of: pattern) {
            out += text[cursor..<match.range.lowerBound]
            let answer = String(match.2)

            if Int(match.1) == ord && !revealed {
                // Divergence from the web version. There, an empty hint (`{{c1::x::}}`) parses as
                // "no hint" but renders as `[]`, because parse tests falsiness and render tests
                // nullishness. Both go through `hint(from:)` here, so an empty hint renders
                // `[...]` like the absent one it already claimed to be.
                out += "[\(hint(from: match.3) ?? "...")]"
            } else {
                out += answer
            }

            cursor = match.range.upperBound
        }

        out += text[cursor...]
        return out
    }

    /// The hidden text for `ord`, or `nil` if the ordinal is not in `text`.
    ///
    /// Divergence from the web version, which returns `""` for a missing ordinal and so cannot
    /// tell it apart from `{{c1::}}`. The caller in the study loop needs that difference.
    static func answer(_ text: String, ord: Int) -> String? {
        for match in text.matches(of: pattern) where Int(match.1) == ord {
            return String(match.2)
        }
        return nil
    }

    /// Whether the text contains any cloze at all. What the editor uses to tell someone their
    /// cloze note has no blanks in it yet.
    static func hasDeletions(_ text: String) -> Bool {
        text.firstMatch(of: pattern) != nil
    }

    /// The text with every deletion replaced by its answer and no syntax left.
    ///
    /// For lists and previews, where the point is to recognise the note rather than be tested by
    /// it. `{{c1::Madrid::capital}} is in Spain` reads as `Madrid is in Spain`.
    static func stripped(_ text: String) -> String {
        // No ordinal is being asked about, so every deletion renders its answer. `-1` cannot
        // collide with a real ordinal, which the pattern guarantees is a non-negative integer.
        render(text, ord: -1, revealed: true)
    }

    /// An empty hint is no hint. `{{c1::x::}}` is a trailing separator someone did not finish
    /// typing, not a request for an empty bracket.
    private static func hint(from captured: Substring?) -> String? {
        guard let captured, !captured.isEmpty else { return nil }
        return String(captured)
    }
}
