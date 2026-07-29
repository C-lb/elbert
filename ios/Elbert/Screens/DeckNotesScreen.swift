import SwiftData
import SwiftUI

/// The notes in one deck, and the way into the editor.
///
/// The editor opens as a sheet rather than a push. Writing a note is a bounded piece of work with
/// two exits, save and cancel, and a sheet says that; a pushed screen implies a back button that
/// silently keeps whatever you typed.
struct DeckNotesScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCentre.self) private var toasts

    let deck: Deck

    @State private var editing: EditorTarget?
    @State private var notePendingDeletion: Note?

    /// Creation order, not alphabetical. A deck is a sequence someone built, and re-sorting it
    /// hides where they left off.
    private var notes: [Note] {
        (deck.notes ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        HouseScreen(
            title: deck.name,
            action: .init(icon: .add, label: "New note") { editing = .creating }
        ) {
            if notes.isEmpty {
                HouseEmptyState(
                    icon: .edit,
                    title: "No notes yet",
                    message: "A note is what you write. Elbert turns each one into the cards you actually review.",
                    action: .init(label: "New note") { editing = .creating }
                )
            } else {
                VStack(spacing: Space.s3) {
                    ForEach(notes) { note in
                        NoteRow(note: note)
                            .onTapGesture { editing = .editing(note) }
                            .contextMenu {
                                Button {
                                    editing = .editing(note)
                                } label: {
                                    Label("Edit", systemImage: Icon.edit.symbol)
                                }

                                Button(role: .destructive) {
                                    notePendingDeletion = note
                                } label: {
                                    Label("Delete", systemImage: Icon.delete.symbol)
                                }
                            }
                    }
                }

                NavigationLink(value: DeckRoute.settings(deck.id)) {
                    HStack(spacing: Space.s3) {
                        HouseIcon(icon: .settings, role: .body)
                            .foregroundStyle(Theme.ink2)
                        Text("Deck settings")
                            .typeRole(.label)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: Space.s3)
                    }
                    .padding(.vertical, Space.s3)
                    .padding(.horizontal, Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $editing) { target in
            EditorSheet(deck: deck, target: target)
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { notePendingDeletion != nil },
                set: { if !$0 { notePendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: notePendingDeletion
        ) { note in
            Button("Delete note", role: .destructive) { delete(note) }
            Button("Keep it", role: .cancel) {}
        } message: { note in
            let cards = note.cards?.count ?? 0
            Text("\(cards) \(cards == 1 ? "card and its" : "cards and their") review history will go. There is no undo.")
        }
    }

    private func delete(_ note: Note) {
        context.delete(note)
        notePendingDeletion = nil
        do {
            try context.save()
            toasts.show(.success("Note deleted"))
        } catch {
            toasts.show(.error("That did not save. Try again."))
        }
    }
}

// MARK: - Row

private struct NoteRow: View {
    let note: Note

    private var cardCount: Int { note.cards?.count ?? 0 }

    var body: some View {
        HouseCard(elevation: .flat) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Text(note.type.label)
                        .typeRole(.labelSmall)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)

                    Spacer(minLength: Space.s2)

                    Text("\(cardCount) \(cardCount == 1 ? "card" : "cards")")
                        .typeRole(.labelSmall)
                        .foregroundStyle(Theme.ink3)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                // Cloze syntax is unreadable at a glance, so the list shows the sentence rather
                // than the markup. The editor is where the braces belong.
                HouseText(Cloze.stripped(note.term), role: .bodyStrong)
                    .lineLimit(2)

                if !note.definition.isEmpty {
                    HouseText(note.definition, role: .caption, ink: \.ink2)
                        .lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editor presentation

/// Whether the editor is writing a new note or changing one that exists.
enum EditorTarget: Identifiable {
    case creating
    case editing(Note)

    var id: String {
        switch self {
        case .creating: "new"
        case .editing(let note): note.id.uuidString
        }
    }
}
