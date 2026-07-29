import SwiftData
import SwiftUI

/// Every deck, with what each has waiting. Create, rename, delete.
///
/// Counts come from `@Query` results rather than a fresh fetch, so rating a card in Study updates
/// the numbers here without anything having to know to refresh them.
struct DeckListScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCentre.self) private var toasts

    @Query(sort: \Deck.name) private var decks: [Deck]
    @Query private var cards: [Card]

    @State private var editor: DeckNameEditor?
    @State private var deckPendingDeletion: Deck?

    private var counts: [UUID: Queue.Counts] {
        Queue.counts(decks: decks, cards: Queue.eligible(cards: cards))
    }

    var body: some View {
        HouseScreen(
            title: "Decks",
            action: .init(icon: .add, label: "New deck") { editor = .creating }
        ) {
            if decks.isEmpty {
                HouseEmptyState(
                    icon: .decks,
                    title: "No decks yet",
                    message: "A deck holds the notes you want to remember. Make one to get started.",
                    action: .init(label: "New deck") { editor = .creating }
                )
            } else {
                VStack(spacing: Space.s3) {
                    ForEach(decks) { deck in
                        DeckRow(deck: deck, counts: counts[deck.id] ?? Queue.Counts())
                            .contextMenu {
                                Button {
                                    editor = .renaming(deck)
                                } label: {
                                    Label("Rename", systemImage: Icon.edit.symbol)
                                }

                                NavigationLink(value: DeckRoute.settings(deck.id)) {
                                    Label("Deck settings", systemImage: Icon.settings.symbol)
                                }

                                Button(role: .destructive) {
                                    deckPendingDeletion = deck
                                } label: {
                                    Label("Delete", systemImage: Icon.delete.symbol)
                                }
                            }
                    }
                }
            }
        }
        .deckNameAlert($editor) { name, target in
            switch target {
            case .creating: create(named: name)
            case .renaming(let deck): rename(deck, to: name)
            }
        }
        .confirmationDialog(
            // The deck's own name, because "Delete deck?" is the question people say yes to by
            // reflex and then regret.
            "Delete \(deckPendingDeletion?.name ?? "this deck")?",
            isPresented: Binding(
                get: { deckPendingDeletion != nil },
                set: { if !$0 { deckPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: deckPendingDeletion
        ) { deck in
            Button("Delete deck", role: .destructive) { delete(deck) }
            Button("Keep it", role: .cancel) {}
        } message: { deck in
            Text(deletionWarning(for: deck))
        }
    }

    // MARK: - Actions

    private func create(named name: String) {
        let deck = Deck(name: name)
        context.insert(deck)
        save(then: "Deck created")
    }

    private func rename(_ deck: Deck, to name: String) {
        guard deck.name != name else { return }
        deck.name = name
        save(then: "Deck renamed")
    }

    private func delete(_ deck: Deck) {
        context.delete(deck)
        deckPendingDeletion = nil
        save(then: "Deck deleted")
    }

    private func save(then message: String) {
        do {
            try context.save()
            toasts.show(.success(message))
        } catch {
            // Every action gets a response, including the ones that fail. A silent no-op after a
            // rename looks exactly like a rename that worked.
            toasts.show(.error("That did not save. Try again."))
        }
    }

    /// Says what is actually about to be lost, in cards rather than in rows, because "3 notes" and
    /// "7 cards of review history" are different sizes of regret.
    private func deletionWarning(for deck: Deck) -> String {
        let notes = deck.notes?.count ?? 0
        let cards = (deck.notes ?? []).reduce(0) { $0 + ($1.cards?.count ?? 0) }
        let subdecks = deck.children?.count ?? 0

        if notes == 0 {
            return "This deck is empty. There is no undo."
        }

        var warning = "\(notes) \(notes == 1 ? "note" : "notes") and \(cards) "
        warning += cards == 1 ? "card, with its review history, will go" : "cards, with their review history, will go"
        if subdecks > 0 {
            warning += ". Its \(subdecks == 1 ? "subdeck moves" : "subdecks move") to the top level"
        }
        return warning + ". There is no undo."
    }
}

// MARK: - Row

private struct DeckRow: View {
    let deck: Deck
    let counts: Queue.Counts

    var body: some View {
        NavigationLink(value: DeckRoute.notes(deck.id)) {
            HouseCard(elevation: .flat) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    HouseText(deck.name, role: .h3)
                        .lineLimit(2)

                    Spacer(minLength: Space.s3)

                    CountPills(counts: counts)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deck.name), \(counts.due) due, \(counts.newAvailable) new")
    }
}

/// Due and new, as two quiet numbers rather than two coloured badges.
///
/// Semantic colour carries meaning, and "you have homework" is not a meaning: it is neither an
/// error nor a success. So the counts sit on the ink ladder, and only the zero state changes,
/// dropping a step quieter when there is nothing waiting.
private struct CountPills: View {
    let counts: Queue.Counts

    var body: some View {
        HStack(spacing: Space.s3) {
            pill(count: counts.due, label: "due")
            pill(count: counts.newAvailable, label: "new")
        }
    }

    private func pill(count: Int, label: String) -> some View {
        HStack(spacing: Space.s1) {
            Text("\(count)")
                .typeRole(.bodyStrong)
                .foregroundStyle(count > 0 ? Theme.ink : Theme.ink3)
                .monospacedDigit()

            Text(label)
                .typeRole(.caption)
                .foregroundStyle(Theme.ink3)
        }
        .lineLimit(1)
    }
}

// MARK: - Naming alert

/// Which deck a name is being typed for, if any.
enum DeckNameEditor: Identifiable {
    case creating
    case renaming(Deck)

    var id: String {
        switch self {
        case .creating: "new"
        case .renaming(let deck): deck.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .creating: "New deck"
        case .renaming: "Rename deck"
        }
    }

    var confirmLabel: String {
        switch self {
        case .creating: "Create"
        case .renaming: "Rename"
        }
    }

    var initialName: String {
        switch self {
        case .creating: ""
        case .renaming(let deck): deck.name
        }
    }
}

private struct DeckNameAlert: ViewModifier {
    @Binding var editor: DeckNameEditor?
    let commit: (String, DeckNameEditor) -> Void

    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(editor?.title ?? "", isPresented: isPresented, presenting: editor) { editor in
                TextField("Deck name", text: $name)
                    .textInputAutocapitalization(.words)

                Button(editor.confirmLabel) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    commit(trimmed, editor)
                }
                // A blank name is not an error worth a message; the button simply cannot be used.
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: editor?.id) {
                name = editor?.initialName ?? ""
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { editor != nil },
            set: { if !$0 { editor = nil } }
        )
    }
}

extension View {
    func deckNameAlert(
        _ editor: Binding<DeckNameEditor?>,
        commit: @escaping (String, DeckNameEditor) -> Void
    ) -> some View {
        modifier(DeckNameAlert(editor: editor, commit: commit))
    }
}

// MARK: - Routing

/// Where a deck row can go. A typed route rather than a raw `UUID` on the path, so two
/// destinations that both take a deck id cannot be confused for each other.
enum DeckRoute: Hashable {
    case notes(UUID)
    case settings(UUID)
}

/// Resolves a deck id to the deck, and says so plainly when it cannot.
///
/// A navigation path can outlive what it points at: delete a deck on another device and the route
/// pushed on this one still exists. Loading by id and handling the miss is the difference between
/// that being a blank screen and being a crash.
struct DeckLoader<Content: View>: View {
    let deckID: UUID
    @ViewBuilder let content: (Deck) -> Content

    @Query private var decks: [Deck]

    init(deckID: UUID, @ViewBuilder content: @escaping (Deck) -> Content) {
        self.deckID = deckID
        self.content = content
        _decks = Query(filter: #Predicate<Deck> { $0.id == deckID })
    }

    var body: some View {
        if let deck = decks.first {
            content(deck)
        } else {
            HouseScreen(title: "Deck") {
                HouseEmptyState(
                    icon: .caution,
                    title: "This deck is gone",
                    message: "It was deleted, here or on another device."
                )
            }
        }
    }
}
