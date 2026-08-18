import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Brings delimited text in, as notes, in a deck the person picks.
///
/// The parser deliberately does not try to detect a header row, because any heuristic for that
/// eventually eats a real first card. The `skipFirstRow` toggle here makes it the person's call,
/// with the preview updating live so they can see what the toggle does before anything is written.
struct ImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCentre.self) private var toasts

    @Query(sort: \Deck.name) private var decks: [Deck]

    private enum Source: Hashable {
        case paste, file
    }

    @State private var source: Source = .paste
    @State private var text = ""
    @State private var skipFirstRow = false
    @State private var pickedFileName: String?
    @State private var fileProblem: String?
    @State private var showingPicker = false
    @State private var targetDeckID: UUID?
    @State private var newDeckName = ""

    private static let previewLimit = 50

    private var rows: [ImportRow] {
        let parsed = DelimitedImport.parse(text)
        return skipFirstRow ? Array(parsed.dropFirst()) : parsed
    }

    private var trimmedNewDeckName: String {
        newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canImport: Bool {
        !rows.isEmpty && (targetDeckID != nil || !trimmedNewDeckName.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s6) {
                    sourcePicker
                    input
                    options
                    preview
                    target
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s6)
            }
            .background(Theme.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: runImport)
                        .disabled(!canImport)
                        .accessibilityIdentifier("import-confirm")
                }
            }
        }
        .housePalette()
        .onAppear {
            if targetDeckID == nil { targetDeckID = decks.first?.id }
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText],
            allowsMultipleSelection: false,
            onCompletion: handlePicked
        )
    }

    // MARK: - Source

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HouseText("Where from", role: .eyebrow, ink: \.ink2)

            Picker("Where from", selection: $source) {
                Text("Paste").tag(Source.paste)
                Text("File").tag(Source.file)
            }
            .pickerStyle(.segmented)
            .tint(Theme.accent)
        }
    }

    @ViewBuilder
    private var input: some View {
        switch source {
        case .paste:
            VStack(alignment: .leading, spacing: Space.s2) {
                HouseText(
                    "Paste from Quizlet, a spreadsheet, or any tab, comma or semicolon list.",
                    role: .caption,
                    ink: \.ink3
                )

                TextField("chat\tcat", text: $text, axis: .vertical)
                    .typeRole(.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(6, reservesSpace: true)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .houseFieldChrome()
                    .accessibilityIdentifier("import-paste")
            }

        case .file:
            VStack(alignment: .leading, spacing: Space.s3) {
                Button("Choose a file") { showingPicker = true }
                    .buttonStyle(HouseButtonStyle(tier: .neutral, size: .medium))
                    .accessibilityIdentifier("import-choose-file")

                if let pickedFileName {
                    HouseText(pickedFileName, role: .caption, ink: \.ink2)
                }
                if let fileProblem {
                    HouseText(fileProblem, role: .caption, ink: \.danger)
                }
            }
        }
    }

    private var options: some View {
        Toggle(isOn: $skipFirstRow) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HouseText("Skip the first row", role: .body)
                HouseText(
                    "Turn this on when the file starts with column headings.",
                    role: .caption,
                    ink: \.ink3
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, Space.s3)
        }
        .tint(Theme.accent)
        .accessibilityIdentifier("import-skip-first-row")
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if rows.isEmpty {
            HouseText("Nothing to import yet.", role: .caption, ink: \.ink3)
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                HouseText(
                    "Preview, \(rows.count) \(rows.count == 1 ? "card" : "cards")",
                    role: .eyebrow,
                    ink: \.ink2
                )

                VStack(spacing: Space.s3) {
                    ForEach(Array(rows.prefix(Self.previewLimit).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: Space.s3) {
                            HouseText(row.term, role: .bodyStrong)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HouseText(row.definition, role: .body, ink: \.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if rows.count > Self.previewLimit {
                    HouseText("and \(rows.count - Self.previewLimit) more", role: .caption, ink: \.ink3)
                }
            }
        }
    }

    // MARK: - Target

    private var target: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HouseText("Into which deck", role: .eyebrow, ink: \.ink2)

            if !decks.isEmpty {
                Picker("Deck", selection: $targetDeckID) {
                    ForEach(decks) { deck in
                        Text(deck.name).tag(Optional(deck.id))
                    }
                }
                .tint(Theme.accent)
                .accessibilityIdentifier("import-target-deck")
            }

            TextField("Or make a new deck", text: $newDeckName)
                .typeRole(.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .textInputAutocapitalization(.words)
                .houseFieldChrome()
                .accessibilityIdentifier("import-new-deck")

            HouseText("Imported cards arrive new, with no review history.", role: .caption, ink: \.ink3)
        }
    }

    // MARK: - Actions

    private func handlePicked(_ result: Result<[URL], Error>) {
        fileProblem = nil

        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result { fileProblem = "That file could not be opened." }
            return
        }

        // A file picked out of iCloud Drive is not ours to read without asking, and the read has to
        // happen inside the scoped window or it comes back empty.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            fileProblem = "That file could not be read."
            return
        }

        // Old Excel exports on Windows are Latin 1, not UTF-8. Without the fallback they import as
        // mojibake, which reads as the app mangling the content rather than misreading it.
        guard let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            fileProblem = "That file is not text this can read."
            return
        }

        pickedFileName = url.lastPathComponent
        text = decoded
    }

    private func runImport() {
        let name = trimmedNewDeckName
        let deck: Deck

        if !name.isEmpty {
            let made = Deck(name: name)
            context.insert(made)
            deck = made
        } else if let targetDeckID, let existing = decks.first(where: { $0.id == targetDeckID }) {
            deck = existing
        } else {
            toasts.show(.error("Pick a deck first."))
            return
        }

        let summary = DeckImport.run(rows: rows, into: deck, context: context)

        do {
            try context.save()
            let cards = summary.cards
            toasts.show(.success("Imported \(cards) \(cards == 1 ? "card" : "cards")"))
            dismiss()
        } catch {
            toasts.show(.error("That did not import. Try again."))
        }
    }
}

// MARK: - Pieces

private extension View {
    /// The same surface, radius and hairline `EditorSheet`'s fields wear. A bare `TextField` on the
    /// canvas has no edge at all in dark mode, so there is nothing to say where to tap.
    func houseFieldChrome() -> some View {
        padding(.vertical, Space.s3)
            .padding(.horizontal, Space.s3)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}
