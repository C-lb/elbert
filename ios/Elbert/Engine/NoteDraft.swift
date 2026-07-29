import Foundation
import SwiftData

/// What the editor is holding, before any of it reaches the store.
///
/// Port of `src/engine/editor-row.ts`. Keeping the draft separate from the `Note` is what lets the
/// editor abandon an edit cleanly: a `@Model` object edited in place is already saved in every way
/// that matters, and there is no going back from it.
///
/// The rules carried over from the web version: an empty optional field is removed rather than
/// stored as an empty string, and a save is skipped entirely when nothing the editor owns has
/// changed.
struct NoteDraft: Equatable {
    var type: NoteType = .basic
    var term: String = ""
    var definition: String = ""
    var example: String = ""
    var hint: String = ""

    init() {}

    init(_ note: Note) {
        type = note.type
        term = note.term
        definition = note.definition
        example = note.example ?? ""
        hint = note.hint ?? ""
    }

    // MARK: - Validation

    /// Trimmed once, here, so nothing downstream has to remember to.
    var trimmed: NoteDraft {
        var copy = self
        copy.term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.definition = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.example = example.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.hint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    /// The ordinals this draft would produce, if it is a cloze note.
    var clozeDeletions: [ClozeDeletion] {
        type == .cloze ? Cloze.parse(term) : []
    }

    /// Why this draft cannot be saved yet, or `nil` if it can.
    ///
    /// A cloze note with no deletions is the interesting case: it would reconcile to zero cards,
    /// which is a note you can never study and never see again. The web app guards it in the same
    /// place, and the engine stays faithful rather than second-guessing the caller.
    var blockingProblem: String? {
        let draft = trimmed

        if draft.term.isEmpty {
            return type == .cloze ? "Add some text with a blank in it." : "Add a term."
        }
        if draft.type != .cloze && draft.definition.isEmpty {
            return "Add a definition."
        }
        if draft.type == .cloze && draft.clozeDeletions.isEmpty {
            return "Mark at least one blank, like {{c1::this}}."
        }
        return nil
    }

    var canSave: Bool { blockingProblem == nil }

    // MARK: - Applying

    /// True when `note` already says exactly what this draft says.
    ///
    /// The editor uses this to skip the write, which matters more here than on the web: a no-op
    /// save still touches the row, and a touched row is a CloudKit push and a sync on every other
    /// device, for nothing.
    func matches(_ note: Note) -> Bool {
        let draft = trimmed
        return note.type == draft.type
            && note.term == draft.term
            && note.definition == draft.definition
            && (note.example ?? "") == draft.example
            && (note.hint ?? "") == draft.hint
    }

    /// Writes the draft onto a note. Optional fields that are empty become `nil`, never `""`.
    func apply(to note: Note) {
        let draft = trimmed
        note.type = draft.type
        note.term = draft.term
        note.definition = draft.definition
        note.example = draft.example.isEmpty ? nil : draft.example
        note.hint = draft.hint.isEmpty ? nil : draft.hint
    }
}
