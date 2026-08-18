# iOS deck import, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let someone bring delimited text into Elbert on iOS, by pasting it or picking a file, and turn it into notes and cards in a deck they choose.

**Architecture:** Three units stacked so each is usable without the ones above it. A pure parser ported from the web app's `src/import/csv.ts`, a thin writer that turns parsed rows into notes through the same `CardsFromNote.reconcile` path the editor uses, and a sheet that previews the result before anything is written. Entry is a second, non-accent action slot added to `HouseScreen`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing for unit tests, XCTest for UI walks, XcodeGen for the project file.

**Spec:** `docs/superpowers/specs/2026-08-18-ios-import-design.md`

## Global Constraints

- Swift 6 strict concurrency. A static `Regex` needs `nonisolated(unsafe)`; prefer not using one here at all.
- iOS 17 minimum, so `.fileImporter` and `ScrollView` APIs must be the iOS 17 spellings.
- Never name a persisted SwiftData property `hash`, `description` or `superclass`.
- Swift Testing's `#expect` loses `rethrows` inference: pull `allSatisfy(\.keyPath)` out into a `let` before asserting on it.
- All new screens sit inside `HouseScreen` or a `NavigationStack` styled like `EditorSheet`, never their own background colour or horizontal padding.
- One accent fill per screen. A second action is `.icon` tier.
- Copy is sentence case, plain, and contains no em dashes.
- Run tests with: `cd ios && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
- Never `pkill` a running `xcodebuild`. If a run wedges, point `-derivedDataPath` somewhere fresh.
- After adding files, regenerate the project: `cd ios && xcodegen generate`, and commit the `.xcodeproj` alongside.

---

### Task 1: The delimited parser

**Files:**
- Create: `ios/Elbert/Engine/DelimitedImport.swift`
- Test: `ios/Elbert/Tests/ElbertTests/DelimitedImportTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct ImportRow: Equatable, Sendable { let term: String; let definition: String }` and `enum DelimitedImport { static func parse(_ text: String) -> [ImportRow] }`.

- [ ] **Step 1: Write the failing tests**

Create `ios/Elbert/Tests/ElbertTests/DelimitedImportTests.swift`. The first suite is the web app's suite, case for case, in the order `src/import/csv.test.ts` has them.

```swift
import Testing

@testable import Elbert

// Every case in `src/import/csv.test.ts` is the oracle and appears first, verbatim in intent.
// The suite after them is the edge coverage the web app never had.

@Suite("Delimited import, the web app's cases")
struct DelimitedImportOracleTests {
    @Test("tab-delimited rows, the Quizlet default export")
    func tabs() {
        #expect(DelimitedImport.parse("chat\tcat\nchien\tdog") == [
            ImportRow(term: "chat", definition: "cat"),
            ImportRow(term: "chien", definition: "dog"),
        ])
    }

    @Test("comma-delimited rows with quoted fields containing commas")
    func quotedCommas() {
        #expect(DelimitedImport.parse("\"a, b\",def\nterm2,def2") == [
            ImportRow(term: "a, b", definition: "def"),
            ImportRow(term: "term2", definition: "def2"),
        ])
    }

    @Test("quoted fields with embedded newlines")
    func embeddedNewlines() {
        #expect(DelimitedImport.parse("\"line1\nline2\",def") == [
            ImportRow(term: "line1\nline2", definition: "def"),
        ])
    }

    @Test("escaped quotes inside quoted fields")
    func escapedQuotes() {
        #expect(DelimitedImport.parse("\"she said \"\"hi\"\"\",def") == [
            ImportRow(term: "she said \"hi\"", definition: "def"),
        ])
    }

    @Test("semicolon is the fallback when there is no tab or comma")
    func semicolons() {
        #expect(DelimitedImport.parse("chat;cat\nchien;dog") == [
            ImportRow(term: "chat", definition: "cat"),
            ImportRow(term: "chien", definition: "dog"),
        ])
    }

    @Test("extra columns join onto the definition with a middle dot")
    func extraColumns() {
        #expect(DelimitedImport.parse("chat,cat,feline,animal") == [
            ImportRow(term: "chat", definition: "cat · feline · animal"),
        ])
    }

    @Test("cell whitespace is trimmed")
    func trimming() {
        #expect(DelimitedImport.parse("  chat  ,  cat  ") == [
            ImportRow(term: "chat", definition: "cat"),
        ])
    }

    @Test("empty lines are skipped")
    func emptyLines() {
        #expect(DelimitedImport.parse("chat\tcat\n\n\nchien\tdog") == [
            ImportRow(term: "chat", definition: "cat"),
            ImportRow(term: "chien", definition: "dog"),
        ])
    }

    @Test("rows with an empty term are skipped")
    func emptyTerm() {
        #expect(DelimitedImport.parse("chat\tcat\n\tdog\n   \tcat2") == [
            ImportRow(term: "chat", definition: "cat"),
        ])
    }

    @Test("CRLF line endings")
    func crlf() {
        #expect(DelimitedImport.parse("chat\tcat\r\nchien\tdog\r\n") == [
            ImportRow(term: "chat", definition: "cat"),
            ImportRow(term: "chien", definition: "dog"),
        ])
    }

    @Test("empty input parses to nothing")
    func empty() {
        #expect(DelimitedImport.parse("").isEmpty)
        #expect(DelimitedImport.parse("   \n  \n").isEmpty)
    }

    @Test("a row with only a term keeps an empty definition")
    func termOnly() {
        #expect(DelimitedImport.parse("chat") == [ImportRow(term: "chat", definition: "")])
    }
}

@Suite("Delimited import, edges the web app never covered")
struct DelimitedImportEdgeTests {
    @Test("a byte order mark does not become part of the first term")
    func bom() {
        #expect(DelimitedImport.parse("\u{FEFF}chat\tcat") == [
            ImportRow(term: "chat", definition: "cat"),
        ])
    }

    @Test("an unterminated quote keeps the rest of the input as one field")
    func unterminatedQuote() {
        #expect(DelimitedImport.parse("\"chat,cat") == [
            ImportRow(term: "chat,cat", definition: ""),
        ])
    }

    @Test("a quote that is not the first character is a literal quote")
    func lateQuote() {
        #expect(DelimitedImport.parse("5\" nail,a nail") == [
            ImportRow(term: "5\" nail", definition: "a nail"),
        ])
    }

    @Test("the delimiter is chosen once, so commas inside a tab file stay put")
    func delimiterChosenOnce() {
        #expect(DelimitedImport.parse("chat\tcat, a small one") == [
            ImportRow(term: "chat", definition: "cat, a small one"),
        ])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Expected: compile failure, `cannot find 'DelimitedImport' in scope`.

- [ ] **Step 3: Write the parser**

Create `ios/Elbert/Engine/DelimitedImport.swift`:

```swift
import Foundation

/// One row of a pasted or picked file, before it becomes a note.
struct ImportRow: Equatable, Sendable {
    let term: String
    let definition: String
}

/// Parses delimited text into rows.
///
/// Port of `src/import/csv.ts`, and that file's test suite is the oracle. The behaviour worth
/// knowing before changing anything here: the delimiter is chosen once for the whole input rather
/// than per line, because a definition containing a comma inside a tab-delimited file would
/// otherwise split in the wrong place, and that is the common case with Quizlet exports.
enum DelimitedImport {
    static func parse(_ text: String) -> [ImportRow] {
        var text = text
        // Excel on Windows writes a BOM. Left in place it rides along on the first term and the
        // first card silently reads wrong.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let delimiter = detectDelimiter(text)
        var out: [ImportRow] = []

        for cells in splitRows(text, delimiter: delimiter) {
            let trimmed = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let allBlank = trimmed.allSatisfy(\.isEmpty)
            if allBlank { continue }

            guard let term = trimmed.first, !term.isEmpty else { continue }

            // Columns past the second are appended rather than dropped, so a three-column export
            // does not silently lose its third column.
            let definition = trimmed.count > 1 ? trimmed[1...].joined(separator: " · ") : ""
            out.append(ImportRow(term: term, definition: definition))
        }

        return out
    }

    private static func detectDelimiter(_ text: String) -> Character {
        if text.contains("\t") { return "\t" }
        if text.contains(",") { return "," }
        return ";"
    }

    /// Splits text into rows of raw fields, respecting quoted fields that may contain the
    /// delimiter and may contain newlines.
    private static func splitRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        func pushField() {
            row.append(field)
            field = ""
        }
        func pushRow() {
            pushField()
            rows.append(row)
            row = []
        }

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                index = text.index(after: index)
                continue
            }

            // A quote only opens a quoted field at the start of one. Anywhere else it is a literal
            // quote, which is what makes `5" nail` survive.
            if character == "\"" && field.isEmpty {
                inQuotes = true
                index = text.index(after: index)
                continue
            }
            if character == delimiter {
                pushField()
                index = text.index(after: index)
                continue
            }
            if character == "\r" {
                index = text.index(after: index)
                continue
            }
            if character == "\n" {
                pushRow()
                index = text.index(after: index)
                continue
            }

            field.append(character)
            index = text.index(after: index)
        }

        // Flush a trailing field or row, unless the input ended cleanly on a newline and it was
        // already pushed.
        if !field.isEmpty || !row.isEmpty { pushRow() }

        return rows
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios && xcodegen generate && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Expected: PASS, including all 16 new cases.

- [ ] **Step 5: Commit**

```bash
git add ios/Elbert/Engine/DelimitedImport.swift ios/Elbert/Tests/ElbertTests/DelimitedImportTests.swift ios/Elbert.xcodeproj
git commit -m "feat(ios): port the web app's delimited text parser"
```

---

### Task 2: The writer

**Files:**
- Create: `ios/Elbert/Engine/DeckImport.swift`
- Test: `ios/Elbert/Tests/ElbertTests/DeckImportTests.swift`

**Interfaces:**
- Consumes: `ImportRow` from Task 1. `CardsFromNote.reconcile(_ note: Note, in context: ModelContext) -> Reconciliation`, whose `added` is `[Card]`.
- Produces: `struct ImportSummary: Equatable, Sendable { let notes: Int; let cards: Int }` and `enum DeckImport { static func run(rows: [ImportRow], into deck: Deck, context: ModelContext) -> ImportSummary }`.

- [ ] **Step 1: Write the failing tests**

Create `ios/Elbert/Tests/ElbertTests/DeckImportTests.swift`:

```swift
import Foundation
import SwiftData
import Testing

@testable import Elbert

@Suite("Deck import")
struct DeckImportTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try Persistence.inMemoryContainer())
    }

    @Test("rows become basic notes in the deck, one card each")
    func writesNotesAndCards() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        let summary = DeckImport.run(
            rows: [
                ImportRow(term: "chat", definition: "cat"),
                ImportRow(term: "chien", definition: "dog"),
            ],
            into: deck,
            context: context
        )
        try context.save()

        #expect(summary == ImportSummary(notes: 2, cards: 2))

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 2)

        let allBasic = notes.allSatisfy { $0.type == .basic }
        #expect(allBasic)

        let inDeck = notes.allSatisfy { $0.deck?.id == deck.id }
        #expect(inDeck)

        let terms = Set(notes.map(\.term))
        #expect(terms == ["chat", "chien"])
    }

    @Test("imported cards arrive new, with no scheduling state")
    func cardsArriveNew() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        _ = DeckImport.run(rows: [ImportRow(term: "chat", definition: "cat")], into: deck, context: context)
        try context.save()

        let cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 1)
        #expect(cards[0].reps == 0)
        #expect(cards[0].lapses == 0)
        #expect(cards[0].lastReview == nil)
    }

    @Test("importing into a deck that already has notes adds to it")
    func addsToExistingDeck() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        let existing = Note(type: .basic, term: "old", definition: "note", deck: deck)
        context.insert(existing)
        _ = CardsFromNote.reconcile(existing, in: context)
        try context.save()

        let summary = DeckImport.run(rows: [ImportRow(term: "chat", definition: "cat")], into: deck, context: context)
        try context.save()

        #expect(summary == ImportSummary(notes: 1, cards: 1))
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 2)
    }

    @Test("no rows writes nothing")
    func emptyRows() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        let summary = DeckImport.run(rows: [], into: deck, context: context)
        try context.save()

        #expect(summary == ImportSummary(notes: 0, cards: 0))
        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
    }

    @Test("a row with an empty definition still imports")
    func emptyDefinition() throws {
        let context = try makeContext()
        let deck = Deck(name: "Imported")
        context.insert(deck)

        let summary = DeckImport.run(rows: [ImportRow(term: "chat", definition: "")], into: deck, context: context)
        try context.save()

        #expect(summary == ImportSummary(notes: 1, cards: 1))
    }
}
```

Before running, confirm `Deck`'s initialiser accepts `name:` alone. If it does not, read `ios/Elbert/Models/Deck.swift` and match its actual signature in every test above.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Expected: compile failure, `cannot find 'DeckImport' in scope`.

- [ ] **Step 3: Write the writer**

Create `ios/Elbert/Engine/DeckImport.swift`:

```swift
import Foundation
import SwiftData

/// What an import created, for the toast that reports it.
struct ImportSummary: Equatable, Sendable {
    let notes: Int
    let cards: Int
}

/// Turns parsed rows into notes and cards in a deck.
///
/// Every row goes through `CardsFromNote.reconcile`, which is the same path `EditorSheet.save()`
/// takes. That is deliberate: imported cards then arrive exactly like hand-written ones, new, with
/// no reviews and no invented due date, rather than through a second code path that would drift.
///
/// This does not call `context.save()`. The caller owns the transaction, so a save that throws
/// leaves nothing half-written and the screen can report it.
enum DeckImport {
    static func run(rows: [ImportRow], into deck: Deck, context: ModelContext) -> ImportSummary {
        var cards = 0

        for row in rows {
            let note = Note(type: .basic, term: row.term, definition: row.definition, deck: deck)
            context.insert(note)
            cards += CardsFromNote.reconcile(note, in: context).added.count
        }

        return ImportSummary(notes: rows.count, cards: cards)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios && xcodegen generate && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Elbert/Engine/DeckImport.swift ios/Elbert/Tests/ElbertTests/DeckImportTests.swift ios/Elbert.xcodeproj
git commit -m "feat(ios): write imported rows as notes through the editor's reconcile path"
```

---

### Task 3: A second action slot on HouseScreen

**Files:**
- Modify: `ios/Elbert/Screens/HouseScreen.swift` (the `HouseScreen` struct and its `header`)
- Modify: `ios/Elbert/Design/Icons.swift` (add one case)
- Test: `ios/Elbert/Tests/ElbertTests/DesignSystemTests.swift` (append)

**Interfaces:**
- Consumes: `HouseScreen.Action`, which already exists as `{ icon: Icon, label: String, perform: () -> Void }`.
- Produces: `HouseScreen` gains `var secondary: Action?`, rendered `.icon` tier to the left of the primary. `Icon.importDeck` maps to the SF Symbol `square.and.arrow.down`.

- [ ] **Step 1: Write the failing test**

Append to `ios/Elbert/Tests/ElbertTests/DesignSystemTests.swift`, inside whichever suite covers icons (read the file and match its existing suite name and style rather than adding a second suite for one test):

```swift
@Test("the import icon has a symbol and a stable accessibility name")
func importIcon() {
    #expect(Icon.importDeck.symbol == "square.and.arrow.down")
    #expect(Icon.importDeck.name == "import-deck")
}
```

Read the existing icon tests first. `Icon` exposes `symbol` and a name used for accessibility; if the accessor is called something other than `name`, match the file.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ios && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Expected: compile failure, `type 'Icon' has no member 'importDeck'`.

- [ ] **Step 3: Add the icon and the slot**

In `ios/Elbert/Design/Icons.swift`, add the case alongside the others and add it to every `switch` in the file that enumerates cases exhaustively (there is at least a symbol mapping and a name mapping):

```swift
case importDeck = "square.and.arrow.down"
```

and in the name mapping:

```swift
case .importDeck: "import-deck"
```

In `ios/Elbert/Screens/HouseScreen.swift`, add the property below `action`:

```swift
    /// One optional primary action per screen, top right. This is the only place an accent fill is
    /// allowed to appear on a screen's chrome.
    var action: Action?

    /// An optional second action, sitting to the left of the primary. Deliberately `.icon` tier
    /// and never accent: a screen with two accent fills has no primary action, it has two buttons.
    var secondary: Action?
```

and in `header`, before the `if let action` block:

```swift
            if let secondary {
                Button(action: secondary.perform) {
                    HouseIcon(icon: secondary.icon, role: .body)
                }
                .buttonStyle(HouseButtonStyle(tier: .icon, size: .small))
                .accessibilityLabel(secondary.label)
            }
```

Note that `secondary` is declared after `action` but rendered before it. That is the ordering the house wants on screen, primary furthest right, and the property order only affects the memberwise initialiser.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Expected: PASS. Every existing screen still compiles because `secondary` defaults to `nil`.

- [ ] **Step 5: Commit**

```bash
git add ios/Elbert/Screens/HouseScreen.swift ios/Elbert/Design/Icons.swift ios/Elbert/Tests/ElbertTests/DesignSystemTests.swift
git commit -m "feat(ios): allow a screen one non-accent second action"
```

---

### Task 4: The import sheet

**Files:**
- Create: `ios/Elbert/Screens/ImportSheet.swift`
- Modify: `ios/Elbert/Screens/DeckListScreen.swift` (add the secondary action and the sheet)

**Interfaces:**
- Consumes: `DelimitedImport.parse`, `ImportRow`, `DeckImport.run`, `ImportSummary`, `HouseScreen.secondary`, `Icon.importDeck`, `ToastCentre` from the environment, `Toast.success` and `Toast.error`.
- Produces: `struct ImportSheet: View` taking no parameters, presented as a sheet.

- [ ] **Step 1: Write the screen**

There is no unit test step here. The sheet is view code with no logic of its own worth a Swift Testing case, because both things worth asserting, parsing and writing, are already covered by Tasks 1 and 2. The acceptance is the UI walk in Task 5.

Create `ios/Elbert/Screens/ImportSheet.swift`:

```swift
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Brings delimited text in, as notes, in a deck the person picks.
///
/// The parser deliberately does not try to detect a header row, because any heuristic eventually
/// eats a real first card. The `skipFirstRow` toggle here makes it the person's call, with the
/// preview updating live so they can see what the toggle does before anything is written.
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

    private var canImport: Bool {
        !rows.isEmpty && (targetDeckID != nil || !newDeckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
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
        }
    }

    @ViewBuilder
    private var input: some View {
        switch source {
        case .paste:
            VStack(alignment: .leading, spacing: Space.s2) {
                HouseText("Paste from Quizlet, a spreadsheet, or any tab, comma or semicolon list", role: .caption, ink: \.ink3)

                TextField("chat\tcat", text: $text, axis: .vertical)
                    .lineLimit(6...12)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("import-paste")
            }

        case .file:
            VStack(alignment: .leading, spacing: Space.s3) {
                Button("Choose a file") { showingPicker = true }
                    .buttonStyle(HouseButtonStyle(tier: .neutral, size: .medium))

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
            VStack(alignment: .leading, spacing: Space.s1) {
                HouseText("Skip the first row", role: .body)
                HouseText("Turn this on when the file starts with column headings.", role: .caption, ink: \.ink3)
            }
        }
        .accessibilityIdentifier("import-skip-first-row")
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if rows.isEmpty {
            HouseText("Nothing to import yet.", role: .caption, ink: \.ink3)
        } else {
            VStack(alignment: .leading, spacing: Space.s2) {
                HouseText("Preview, \(rows.count) \(rows.count == 1 ? "card" : "cards")", role: .eyebrow, ink: \.ink2)

                VStack(spacing: Space.s2) {
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
                .accessibilityIdentifier("import-target-deck")
            }

            TextField("Or make a new deck", text: $newDeckName)
                .textInputAutocapitalization(.words)
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
        // mojibake, which looks like the app mangled the content rather than misread it.
        guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            fileProblem = "That file is not text this can read."
            return
        }

        pickedFileName = url.lastPathComponent
        text = decoded
    }

    private func runImport() {
        let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
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
```

Two things to check against the codebase while writing this, and match rather than assume: the exact `HouseText` initialiser, including whether the ink argument is a key path as written here, and the exact `Deck` initialiser. Both are used above in the shape the rest of the app uses them, but read `Design/Typography.swift` and `Models/Deck.swift` and correct any mismatch.

- [ ] **Step 2: Wire it into the deck list**

In `ios/Elbert/Screens/DeckListScreen.swift`, add state beside the existing `@State` properties:

```swift
    @State private var showingImport = false
```

change the `HouseScreen` call to carry both actions:

```swift
        HouseScreen(
            title: "Decks",
            action: .init(icon: .add, label: "New deck") { editor = .creating },
            secondary: .init(icon: .importDeck, label: "Import") { showingImport = true }
        ) {
```

and add the sheet next to the existing alert modifiers on the same view:

```swift
        .sheet(isPresented: $showingImport) {
            ImportSheet()
        }
```

- [ ] **Step 3: Build and walk it by hand**

Run: `cd ios && xcodegen generate && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

Then launch the simulator with `-seedSampleData`, open Decks, tap Import, paste two tab-separated lines, type a new deck name, and confirm the deck appears with two cards. Check the same screen in both appearances:

```bash
xcrun simctl ui <device-udid> appearance dark
xcrun simctl ui <device-udid> appearance light
```

Resolve the UDID explicitly. Two booted simulators means `xcrun simctl io booted` grabs the wrong one.

- [ ] **Step 4: Run the full test suite**

Run: `cd ios && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Expected: PASS. Nothing here should have moved an existing test.

- [ ] **Step 5: Commit**

```bash
git add ios/Elbert/Screens/ImportSheet.swift ios/Elbert/Screens/DeckListScreen.swift ios/Elbert.xcodeproj
git commit -m "feat(ios): import delimited text from a paste or a file"
```

---

### Task 5: The acceptance walk, and the docs

**Files:**
- Modify: `ios/Elbert/Tests/ElbertUITests/DeckFlowUITests.swift` (append one test)
- Modify: `ios/README.md`

**Interfaces:**
- Consumes: the accessibility identifiers set in Task 4, `import-paste`, `import-new-deck`, `import-skip-first-row`, and the `Import` accessibility label on the secondary action. Plus `tap(_:untilExists:)` and `selectTab` from `UITestSupport.swift`.
- Produces: nothing other code reads.

- [ ] **Step 1: Write the failing walk**

Append to `ios/Elbert/Tests/ElbertUITests/DeckFlowUITests.swift`:

```swift
    // MARK: - Import

    /// Pastes two rows into a brand new deck and proves they became cards.
    ///
    /// Launches with `-resetStore` rather than `-seedSampleData`, because this walk asserts on a
    /// deck count and the sample decks would make the assertion depend on the fixture.
    func testPastedRowsImportIntoANewDeck() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetStore"]
        app.launch()

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 15))
        selectTab(app, "Decks", heading: "Decks")

        tap(app.buttons["Import"], untilExists: app.staticTexts["Import"])

        let paste = app.textViews["import-paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        paste.typeText("chat\tcat\nchien\tdog")

        let name = app.textFields["import-new-deck"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("French")

        // A writing tap is never re-tapped: a second one here would import twice.
        app.buttons["Import"].firstMatch.tap()

        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'French'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the imported deck never appeared")
        XCTAssertTrue(row.label.contains("2"), "expected two cards in the imported deck, got \(row.label)")
    }
```

If `import-paste` resolves as a `textField` rather than a `textView` because of the `axis: .vertical` spelling, address it as `app.textFields["import-paste"]` instead. Check with a single run before assuming either.

Note the toolbar button and the sheet title share the word "Import", which is exactly the two-elements-one-name trap the heading identifier exists for. Address the toolbar button through `app.buttons` and the title through `app.staticTexts`, as written.

- [ ] **Step 2: Run the walk to verify it fails**

Run: `cd ios && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ElbertUITests/DeckFlowUITests/testPastedRowsImportIntoANewDeck test`

Expected: fail if Task 4 is incomplete. If Task 4 is done, this should pass on the first run, and the failure to look for is a missing identifier rather than missing behaviour.

- [ ] **Step 3: Fix whatever the walk finds**

Adjust identifiers in `ImportSheet.swift` until the walk passes. Do not weaken the assertion to make it green. If the card count is hard to read from the deck row's label, open the deck and count rows instead, but keep an assertion on the number.

- [ ] **Step 4: Run the whole suite twice**

Run: `cd ios && xcodebuild -project Elbert.xcodeproj -scheme Elbert -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Expected: PASS. Run it a second time, because two pre-existing UI tests intermittently drop touches on full-suite reruns, a different pair each time. A new failure in a test this plan did not touch is that known flake, not a regression. A repeated failure in the same test is real.

- [ ] **Step 5: Document it and commit**

In `ios/README.md`, add a short section under the existing notes:

```markdown
## Importing decks

Deck list, the icon left of New deck. Paste tab, comma or semicolon separated text, or pick a
`.csv`, `.tsv` or `.txt` file from Files. `Engine/DelimitedImport.swift` is a port of the web app's
`src/import/csv.ts` and that file's tests are the oracle, so a change to one belongs in both.

The parser does not detect header rows on purpose. The sheet's "Skip the first row" toggle makes it
the person's call, because a heuristic eventually eats a real first card.

`.apkg` is not supported on iOS. The web reader needs a zip library and SQLite, neither of which is
in the iOS bundle.
```

```bash
git add ios/Elbert/Tests/ElbertUITests/DeckFlowUITests.swift ios/README.md
git commit -m "test(ios): walk a pasted import into a new deck"
git push origin main
```

---

## Self-review notes

**Spec coverage.** Parser and its oracle tests, Task 1. Writer and its store tests, Task 2. The `HouseScreen` second slot and the icon, Task 3. Paste, file picking, the skip-header toggle, preview, deck targeting, error handling and toasts, Task 4. The acceptance walk and the README record of the divergences, Task 5. The error table in the spec maps to `fileProblem`, the disabled `canImport`, and the `do/catch` in `runImport`.

**Known soft spots the executor should expect to resolve by reading code, not guessing.** Three call sites are written in the shape the rest of the app uses but were not verified line by line: `HouseText`'s ink argument, `Deck`'s initialiser, and whether `Icon`'s accessibility accessor is called `name`. Each task says to read the file and match. None of them changes the design.

**Type consistency.** `ImportRow` is defined once in Task 1 and used unchanged in Tasks 2 and 4. `ImportSummary` is defined in Task 2 and read in Task 4. `HouseScreen.secondary` is defined in Task 3 and passed in Task 4. `Icon.importDeck` is defined in Task 3 and used in Task 4.
