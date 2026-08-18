# iOS deck import, design

Date: 2026-08-18
Status: approved in chat, ready to plan

## Why

The iOS app has no way to get content in other than typing it, note by note, in the editor. The web app has had a working importer since the original build (`src/screens/Import.tsx`, `src/import/csv.ts`), but the two apps do not share data: iOS mirrors through CloudKit's private database, the frozen web app syncs to Neon, and nothing bridges them. So a deck built anywhere else, a Quizlet export, a spreadsheet, a CSV a study group passed around, cannot reach the phone at all.

This closes that. Delimited text in, notes and cards out, in the deck the person picks.

## Scope

In:

- Pasting delimited text, the same flow the web importer offers.
- Picking a `.csv`, `.tsv` or `.txt` file through the Files app.
- A preview of what will be created before anything is written.
- Importing into an existing deck, or into a new deck named on the spot.

Out, deliberately:

- `.apkg` (Anki) import. The web reader leans on a JavaScript zip library and a SQLite build, and neither has an equivalent sitting in the iOS bundle. Shipping it means shipping an unzip implementation and a `libsqlite3` layer, which is its own feature.
- A share extension. That needs a second app target with its own bundle id, entitlements and provisioning profile, and the App Group work that the portal cannot do over the API (see `reference_asc_api_no_app_groups`).
- Image and media import.
- Cloze detection. Every imported row becomes a basic note. A person who wants cloze can edit the note afterwards.
- Duplicate detection. The web importer does not dedupe, and inventing a rule here would put the two apps out of step for no asked-for reason.

## Architecture

Three units, matching how the app is already split, each usable and testable without the ones above it.

### 1. `Engine/DelimitedImport.swift`

Pure parsing. No SwiftData, no UI, no file system.

```swift
struct ImportRow: Equatable, Sendable {
    let term: String
    let definition: String
}

enum DelimitedImport {
    static func parse(_ text: String) -> [ImportRow]
}
```

This is a port of `src/import/csv.ts`, and that file plus its test suite is the oracle, the same way `ts-fsrs` was the oracle for the scheduler. The behaviour carried over exactly:

- **One delimiter for the whole input**, chosen in order: tab if the text contains one, else comma if it contains one, else semicolon. Deliberately not per line, because a definition containing a comma inside a tab-delimited file would otherwise split in the wrong place.
- **Quoted fields**, opened only when the quote is the first character of the field, closed by a lone quote, with `""` meaning a literal quote. A quoted field may contain the delimiter and may contain newlines.
- **CRLF** handled by dropping `\r` outside quotes.
- **Cells trimmed** of surrounding whitespace.
- **Rows that are entirely empty are skipped.**
- **Rows whose first cell is empty after trimming are skipped**, so a stray delimiter does not produce a note with no term.
- **Extra columns beyond the second are appended to the definition**, joined with a space, a middle dot, and a space.
- **A row with only a term** yields that term and an empty definition.

### 2. `Engine/DeckImport.swift`

The write. Takes parsed rows and puts them in the store.

```swift
struct ImportSummary: Equatable, Sendable {
    let notes: Int
    let cards: Int
}

enum DeckImport {
    static func run(rows: [ImportRow], into deck: Deck, context: ModelContext) -> ImportSummary
}
```

One `Note` per row, type `.basic`, term and definition from the row, everything else left at its default, then `CardsFromNote.reconcile(note, in: context)` for each. That reconcile call is not incidental: it is exactly how `EditorSheet.save()` creates a note, so imported cards arrive through the same path as hand-written ones and land new, with no scheduling state, no reviews and no due date fiction.

`DeckImport` does not call `context.save()`. The caller owns the transaction, so a failed save leaves nothing half-written and the screen can report the failure the way the editor already does.

### 3. `Screens/ImportSheet.swift`

The screen, presented as a sheet.

- A source segment: **Paste** or **File**.
- Paste mode holds a multi-line text field.
- File mode uses `.fileImporter` restricted to `.commaSeparatedText`, `.tabSeparatedText` and `.plainText`. The picked URL is read inside `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`, decoded as UTF-8, and on failure retried as ISO Latin 1, which is what old Excel exports on Windows produce. A file that decodes as neither is reported plainly rather than importing as mojibake.
- A **Skip first row** toggle, off by default.
- A preview of the first 50 rows with the total count above it.
- A target deck picker listing existing decks, plus a new deck name field. A non-empty name wins, matching the web app's `resolveDeckId`.
- An import button, disabled at zero rows.

#### The header row decision

`parseCsv` does not skip a header, so every spreadsheet export produces a junk note reading "term / definition". The temptation is to teach the parser to detect and drop a header, and that is wrong twice over: it diverges from the oracle, and any heuristic will eventually eat a real first card. Instead the parser stays faithful and the screen carries a **Skip first row** toggle the person can see and set, with the preview updating live so the effect is visible before anything is written.

### Entry point, and the one design system change

The request was a deck list toolbar button. `HouseScreen` allows exactly one action there and documents it as the only place an accent fill may appear on a screen's chrome, and the deck list already spends it on New deck.

Rather than break that rule or bury import somewhere it does not belong, `HouseScreen` gains an optional second slot:

```swift
var secondary: Action?
```

rendered in the `.icon` tier, to the left of the primary, so there is still exactly one accent per screen. It defaults to `nil`, so every other screen is untouched.

A new `Icon` case, `importDeck`, maps to the SF Symbol `square.and.arrow.down`.

## Error handling

| What goes wrong | What happens |
| --- | --- |
| Pasted text parses to zero rows | The import button is disabled and the preview area says so. No error state, because nothing has gone wrong yet. |
| Picked file cannot be read or decoded | An inline message naming the file, and the paste box is left alone so the person can fall back to copy and paste. |
| No target deck chosen and no new name typed | Import button disabled. |
| `context.save()` throws | The existing toast pattern from `EditorSheet.commit`: an error toast, the sheet stays open, nothing is dismissed. |
| Import succeeds | Success toast reading how many notes and cards were created, then the sheet dismisses. |

## Testing

- `DelimitedImportTests` ports every case in `src/import/csv.test.ts` case for case, marked as the oracle in a comment the way `ClozeTests` does, plus the Swift-specific edge cases that suite never had: a lone `\r\n` at end of input, a file with a BOM, and an unterminated quote.
- `DeckImportTests` runs against `Persistence.inMemoryContainer()`: rows into an empty deck, rows into a deck that already has notes, the card count matching the note count for basic notes, an empty row array writing nothing, and the summary numbers.
- One walk added to `DeckFlowUITests`: open the deck list, tap Import, paste two rows, name a new deck, import, and confirm the deck appears with two cards. Navigation taps go through the existing `tap(_:untilExists:)` helper, never the writing taps.

## Deliberate divergences from the web app

Recorded here so nobody later "fixes" them:

1. **The header toggle is new.** The web importer has no equivalent and imports the header as a card.
2. **File picking is new.** The web app has paste and `.apkg` upload, no plain file picker.
3. **`.apkg` is absent on iOS**, as above.

Everything the parser does is identical, and the tests prove it against the same inputs.
