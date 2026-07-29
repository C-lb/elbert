import SwiftData
import SwiftUI

/// Write or change a note, and see what cards it will produce before committing to them.
///
/// The editor holds a ``NoteDraft`` rather than the `Note` itself. A `@Model` object edited in
/// place is already saved in every sense that matters, so Cancel would be a lie. Nothing reaches
/// the store until Save, and Save is also where the card set is reconciled.
struct EditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCentre.self) private var toasts

    let deck: Deck
    let target: EditorTarget

    @State private var draft = NoteDraft()
    @State private var didLoad = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case term, definition, example, hint
    }

    private var isCloze: Bool { draft.type == .cloze }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    typePicker
                    fields
                    cardPreview
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s6)
            }
            .background(Theme.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle(isCreating ? "New note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.canSave)
                }
            }
        }
        .housePalette()
        .onAppear(perform: load)
    }

    private var isCreating: Bool {
        if case .creating = target { return true }
        return false
    }

    // MARK: - Type

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HouseText("Note type", role: .eyebrow, ink: \.ink2)

            Picker("Note type", selection: $draft.type) {
                ForEach(NoteType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)

            HouseText(typeExplanation, role: .caption, ink: \.ink3)
        }
    }

    private var typeExplanation: String {
        switch draft.type {
        case .basic: "One card: term on the front, definition on the back."
        case .basicReversed: "Two cards, one in each direction."
        case .cloze: "One card per blank. Mark a blank as {{c1::the answer}}, and add a hint with {{c1::answer::hint}}."
        }
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            EditorField(
                label: isCloze ? "Text" : "Term",
                placeholder: isCloze ? "Rome was founded in {{c1::753 BC}}" : "The word or question",
                text: $draft.term,
                axis: .vertical
            )
            .focused($focus, equals: .term)

            EditorField(
                label: isCloze ? "Notes" : "Definition",
                placeholder: isCloze ? "Anything worth seeing with the answer, optional" : "The answer",
                text: $draft.definition,
                axis: .vertical
            )
            .focused($focus, equals: .definition)

            EditorField(
                label: "Example",
                placeholder: "Optional",
                text: $draft.example,
                axis: .vertical
            )
            .focused($focus, equals: .example)

            EditorField(
                label: "Hint",
                placeholder: "Optional",
                text: $draft.hint,
                axis: .horizontal
            )
            .focused($focus, equals: .hint)
        }
    }

    // MARK: - Preview

    /// What this note will actually become.
    ///
    /// Cloze syntax is not discoverable: `{{c1::…}}` either produces a card or silently produces
    /// nothing, and without this the difference only shows up during a review. For the other two
    /// types the preview is smaller but the same idea, saying how many cards will exist.
    @ViewBuilder
    private var cardPreview: some View {
        HouseCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HouseText("This note makes", role: .eyebrow, ink: \.ink2)

                if let problem = draft.blockingProblem {
                    HouseBanner(role: .warning, message: problem)
                } else if isCloze {
                    let deletions = draft.clozeDeletions
                    HouseText(
                        "\(deletions.count) \(deletions.count == 1 ? "card" : "cards"), one per blank.",
                        role: .body
                    )

                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(deletions) { deletion in
                            ClozePreviewRow(text: draft.term, deletion: deletion)
                        }
                    }
                } else {
                    HouseText(
                        draft.type == .basic
                            ? "One card, term to definition."
                            : "Two cards, one in each direction.",
                        role: .body
                    )
                }

                if case .editing(let note) = target, draft.canSave {
                    ReconciliationNotice(note: note, draft: draft)
                }
            }
        }
    }

    // MARK: - Loading and saving

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        if case .editing(let note) = target {
            draft = NoteDraft(note)
        } else {
            focus = .term
        }
    }

    private func save() {
        guard draft.canSave else { return }

        switch target {
        case .creating:
            let note = Note(deck: deck)
            draft.apply(to: note)
            context.insert(note)
            CardsFromNote.reconcile(note, in: context)
            commit(created: true)

        case .editing(let note):
            // Nothing changed, so nothing is written. A no-op save still touches the row, and a
            // touched row is a CloudKit push and a sync on every other device, for nothing.
            guard !draft.matches(note) else {
                dismiss()
                return
            }
            draft.apply(to: note)
            let result = CardsFromNote.reconcile(note, in: context)
            commit(created: false, reconciliation: result)
        }
    }

    private func commit(created: Bool, reconciliation: Reconciliation = Reconciliation()) {
        do {
            try context.save()
            toasts.show(.success(created ? "Note added" : summary(for: reconciliation)))
            dismiss()
        } catch {
            toasts.show(.error("That did not save. Try again."))
        }
    }

    /// Says what changed when the card set changed, because adding a blank silently adding a card
    /// is the kind of thing people only notice as a surprise mid-review.
    private func summary(for reconciliation: Reconciliation) -> String {
        let added = reconciliation.added.count
        let removed = reconciliation.removed.count

        switch (added, removed) {
        case (0, 0): return "Note saved"
        case (let a, 0): return "Saved, \(a) new \(a == 1 ? "card" : "cards")"
        case (0, let r): return "Saved, \(r) \(r == 1 ? "card" : "cards") removed"
        default: return "Saved, \(added) added and \(removed) removed"
        }
    }
}

// MARK: - Pieces

private struct EditorField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .vertical

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // A label and the control it names never share a line.
            HouseText(label, role: .eyebrow, ink: \.ink2)

            TextField(placeholder, text: $text, axis: axis)
                .typeRole(.body)
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.sentences)
                .lineLimit(axis == .vertical ? 2 : 1, reservesSpace: axis == .vertical)
                .padding(.vertical, Space.s3)
                .padding(.horizontal, Space.s3)
                .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
        }
    }
}

/// One blank, shown as the card it becomes: the front, with everything else revealed.
private struct ClozePreviewRow: View {
    let text: String
    let deletion: ClozeDeletion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Text("c\(deletion.ord)")
                    .typeRole(.labelSmall)
                    .foregroundStyle(Theme.ink3)
                    .monospacedDigit()

                if deletion.hint != nil {
                    Text("has a hint")
                        .typeRole(.labelSmall)
                        .foregroundStyle(Theme.ink3)
                }

                Spacer(minLength: Space.s2)
            }

            HouseText(Cloze.render(text, ord: deletion.ord, revealed: false), role: .body, ink: \.ink2)
        }
    }
}

/// What saving will do to the cards that already exist.
private struct ReconciliationNotice: View {
    let note: Note
    let draft: NoteDraft

    private var wanted: Set<Int> {
        let preview = Note(type: draft.type, term: draft.trimmed.term)
        return Set(CardsFromNote.wantedOrdinals(for: preview))
    }

    private var existing: Set<Int> {
        Set((note.cards ?? []).map(\.ord))
    }

    var body: some View {
        let losing = existing.subtracting(wanted).count
        let gaining = wanted.subtracting(existing).count

        if losing > 0 {
            // Losing a card loses its schedule, which is the only genuinely destructive thing the
            // editor can do, so it is a warning rather than a note.
            HouseBanner(
                role: .warning,
                message: "\(losing) existing \(losing == 1 ? "card" : "cards") will be removed, along with \(losing == 1 ? "its" : "their") review history."
            )
        } else if gaining > 0 {
            HouseText(
                "\(gaining) new \(gaining == 1 ? "card" : "cards") will be added. The others keep their schedule.",
                role: .caption,
                ink: \.ink3
            )
        }
    }
}
