# Elbert, iOS native rewrite

Date: 2026-07-29
Status: approved design, ready to plan against
Supersedes for all new work: `2026-07-17-elbert-design.md` (the web build)

## 1. Why

Elbert today is a Vite + React PWA at https://elbert.vercel.app, offline-first on Dexie/IndexedDB, FSRS scheduling, with two Vercel serverless endpoints (sync and AI generate). It works, but three things it cannot do are the reasons for this move:

1. **App Store presence.** A PWA is not installable from the App Store and cannot go through TestFlight.
2. **iOS capabilities.** No real background notifications, no widgets, no share-sheet capture, and iOS evicts IndexedDB after roughly seven weeks of non-use. For an app whose entire value is months of accumulated FSRS state, silent data eviction is the serious one.
3. **Native feel.** Gestures, haptics, transitions, and keyboard behaviour in a Safari-hosted PWA do not match the platform.

## 2. Decisions

| Decision | Choice | Consequence |
|---|---|---|
| Stack | Swift 6 / SwiftUI, iOS 17 minimum | Full rewrite. No TypeScript carries over. |
| Persistence and sync | SwiftData with CloudKit private-database mirroring | No sync code to write, and the outstanding Neon setup is no longer needed by anything. Locks Elbert to Apple platforms permanently. |
| Data migration | None. Start clean. | No export format, no importer, no migration tests. |
| v1 scope | Core loop only | Decks, deck settings, card editor, FSRS study loop, home, settings. |
| Repo | `C-lb/elbert`, new `ios/` directory | Web app stays in place, frozen. |
| Icon family | SF Symbols | Matches system chrome. Deliberately diverges from the Phosphor default used in Nexus and Blocks. |
| Type | DM Sans, bundled | Not SF Pro. House standard wins over platform default here. |

iOS 17 is the floor because SwiftData with a CloudKit container requires it.

## 3. Scope

**In (wave 1):** Home, DeckList, DeckSettings, Editor, Study, Settings. The design system layer. The scheduling engine. CloudKit sync.

**Out (wave 2, separate spec):** Learn, Match, Test mode, AI Generate, CSV import, .apkg import, notifications, widgets, share-sheet capture.

**Out permanently:** the shader backdrop, any use of the Vercel sync endpoint from iOS, the Neon database, any non-Apple client.

**Untouched:** everything under `src/`, `api/`, and the Vercel config. The web app stays deployed and buildable exactly as it is today. Nothing in this spec deletes or edits web code, because deleting `src/sync/` or `api/sync.ts` would break a build that is still shipping.

## 4. Architecture

```
ios/Elbert/
  App/         ElbertApp.swift, ModelContainer + CloudKit configuration, RootView
  Design/      Theme.swift, Typography.swift, Buttons.swift, Icons.swift, Feedback.swift
  Models/      Deck, Note, Card, Review, MediaAsset (SwiftData @Model)
  Engine/      Cloze, CardsFromNote, Scheduler, Queue, StudySession
  Screens/     Home, DeckList, DeckSettings, Editor, Study, Settings
  Tests/       ElbertEngineTests (Swift Testing), ElbertUITests (XCUITest)
```

`Engine/` is pure Swift with no SwiftUI import and no direct `ModelContext` writes where avoidable, so it stays unit-testable in isolation. Screens compose from `Design/` and never hardcode a colour, radius, spacing value, or font size.

### What the iOS app uses from Vercel

`api/generate.ts` only, and only in wave 2. The Anthropic key cannot ship inside an iOS binary because strings are trivially extractable from an `.ipa`, so AI generation stays a server round trip.

`api/sync.ts` and `api/_lib/*` stay exactly where they are. They belong to the frozen web app, not to iOS. They were never enabled in production anyway, since the Neon setup was left unaccepted, so there is nothing running to turn off. The iOS app simply never calls them.

## 5. Data model

Ported from `src/data/types.ts`, minus all sync bookkeeping.

```
Deck:   id, name, parentId, newPerDay, desiredRetention, createdAt
Note:   id, deck, type (basic | basicReversed | cloze),
        term, definition, example?, hint?, imageAssetID?, tags
Card:   id, note, ord, due, stability, difficulty, reps, lapses,
        state (new | learning | review | relearning), lastReview?,
        suspended, learningSteps
Review: id, card, ts, rating (again | hard | good | easy), elapsedMs, snapshot
MediaAsset: id, hash, data (@Attribute(.externalStorage)), mime
```

`Synced`, `dirty`, `updatedAt`, and `deletedAt` are all gone. CloudKit handles conflict resolution and tombstones itself, so the soft-delete scheme that `queue.ts` and `cards-from-note.ts` are built around disappears with it. That is a real behavioural change and Section 6 says what replaces it.

### CloudKit constraints, non-negotiable

1. **No `@Attribute(.unique)`.** The CloudKit mirror rejects unique constraints. Identity is a plain `id: UUID` and de-duplication is application logic.
2. **Every property optional or defaulted.** A non-optional property without a default will not compile against a CloudKit container.
3. **Every relationship optional, with an inverse.** `Note.deck` is `Deck?`. Inverses must be declared or the mirror drops rows.
4. **No custom `Codable` enums without a raw-value default.** Store `state` and `type` as `Int` and `String` raw values with defaults.

### Day counter

`newIntroduced:<deckId>:<yyyy-MM-dd>` currently lives in a Dexie `meta` table. On iOS it moves to `UserDefaults`, deliberately **not** to CloudKit. New-cards-introduced-today is a per-device notion, and syncing it would mean starting a session on iPad silently consuming iPhone's allowance. Accepting per-device drift here is simpler and closer to what a user expects.

## 6. Behaviour to preserve

The existing TypeScript is the reference specification. It is reviewed, tested, and correct, so the Swift port must reproduce these behaviours exactly. Each bullet names the source file so the port can be diffed against it.

**Cloze parsing** (`src/engine/cloze.ts`). Pattern `{{c<n>::answer::hint}}`, hint optional. Ordinals de-duplicate keeping the first occurrence's hint, and sort ascending. Rendering an unrevealed ordinal shows `[hint]` or `[...]`; every other ordinal renders its answer text.

**Cards per note** (`src/engine/cards-from-note.ts`). Basic gives one card at ord 0. Basic reversed gives ords 0 and 1. Cloze gives one card per distinct ordinal. On edit, the card set reconciles: missing ordinals get a fresh card, ordinals no longer present are removed, and existing cards for surviving ordinals keep their FSRS state untouched.

> **Change from web.** The web version soft-deletes a removed ordinal and resurrects the same row id if that ordinal comes back, so a basic to reversed round trip does not accumulate dead rows. Without soft delete, the Swift version hard-deletes and mints a new id on return. This is acceptable because the resurrected card was already given fresh FSRS state, so the only thing lost is id stability across a round trip, which nothing depends on now that sync is CloudKit's problem. Tests must cover the round trip and assert no duplicate live card exists per ordinal.

**Scheduling** (`src/engine/scheduler.ts`). FSRS with `request_retention` taken from the card's deck. A review writes the updated card and appends a `Review` row carrying a snapshot of the pre-review scheduling state. Interval preview labels for the four ratings follow the existing format: under an hour shows `<Nm` with a floor of 1, under a day shows `Nh`, under 30 days shows `Nd`, beyond that shows `N.Nmo`.

**Queue order** (`src/engine/queue.ts`). Learning and relearning cards due now, ordered by due date, then review cards due now ordered by due date, then new cards up to each deck's remaining daily allowance. Suspended cards, cards whose note or deck is gone, and cards not yet due are all excluded.

**Due counts** (`src/engine/queue.ts`). Per deck, `due` counts non-new cards past their due time, and `newAvailable` is the smaller of the deck's remaining allowance and the count of new cards actually in that deck.

**In-session requeue** (`src/engine/session.ts`). After a rating, if the card's new due time is within 20 minutes, it goes back into the queue 5 positions down, or at the end if the queue is shorter than that. Otherwise it leaves the session.

**Note field editing** (`src/engine/editor-row.ts`). Empty optional fields (example, hint, image) are removed rather than stored as empty strings, and a save is skipped entirely when nothing the editor owns has changed.

### FSRS parity, resolved during task 1

The original draft of this section guessed wrong and is corrected here.

**Measured facts.** The web app runs `ts-fsrs` 5.4.1, whose default weight vector is **21 weights** ending in a `0.1542` decay term. That is the FSRS-6 signature, so the web app is on **FSRS-6**, not FSRS-5 as first written. The only tagged release of `open-spaced-repetition/swift-fsrs` is **5.0.0** (Oct 2024), which ships a **19-weight FSRS-5** vector.

So the pinned Swift package is one generation *behind* the web app, the reverse of the risk originally anticipated.

**Option A, stay on tagged 5.0.0 (FSRS-5).** Stable, tagged, no dependency risk. Scheduling is a generation old. Given there is no data migration and Elbert starts empty, nothing breaks, intervals are just modelled slightly less well.

**Option B, track `swift-fsrs` `main`.** HEAD adds `BasicSchedulerV6`, an algorithm-version detector keyed on vector length (19 means v5, 21 means v6), and an `FSRSDefaults.defaultWv6` vector that matches the ts-fsrs 5.4.1 defaults byte for byte, including the decay constant. FSRS-6 is opt-in there by passing the 21-weight vector; the package still defaults to v5 on purpose so it never silently migrates anyone. Cost: `main` carries no release tag, so this means pinning a branch or a bare revision.

**Decision point: task 6.** Not made yet. Task 6 must pick one, record the choice, and either way run the parity check: schedule the same synthetic card through both implementations with identical inputs and compare intervals across all four ratings.

## 7. Design system

House anti-vibecode standards, translated to SwiftUI. `Design/` is written and reviewed against the non-negotiables before any screen is built. A screen file reaching past `Theme` for a raw value is a review failure.

**Colour.** One accent, the existing blurple from commit `29437c7`. Everything structural is neutral. Semantic colours are four triples (base, soft tint, hairline) for info, success, warning, and danger, used only to signal state. Dark mode is primary and surfaces step lighter than the canvas: `bg` darkest, `surface1` for cards, `surface2` for menus and sheets. Body ink is near `#f4f4f5`, never pure white, with `ink2` and `ink3` completing the hierarchy ladder.

**No shader backdrop.** `ShaderBackdrop.tsx` and `ShaderGradientInner.tsx` are a spotlight gradient, which the house rules ban outright. The Swift card face is a flat surface with a soft shadow. Three.js, `@react-three/fiber`, and `shadergradient` are simply not ported.

**Type.** DM Sans bundled into the app bundle. 17pt base, mobile only. Leading and tracking scale inversely with size, so each role is a modifier rather than a per-view guess: `.typeRole(.display)` applies size, weight, `lineSpacing`, and tracking together. Two SwiftUI-specific notes:

- SwiftUI `.tracking()` takes points, not em. Tokens store em and the modifier multiplies by the role's point size.
- There is no `text-box-trim` equivalent. Cap-to-baseline trim is a modifier that reads `UIFont` ascender and cap height and applies the difference as negative vertical padding. This is what makes labels sit truly centred against icons.

**Buttons.** Three `ButtonStyle`s: `.house` (grey `surface1`), `.houseAccent` (the one primary action per screen), `.houseIcon`. Horizontal padding is exactly twice vertical. Radius 10 small, 14 medium, 20 cards. Flat: fill, optional dim hairline, optional soft outer shadow, and no lit top edge. Labels are `.lineLimit(1)`. States are default, pressed, disabled, focused, plus a loading state that swaps the label for a spinner and disables the control. Pressed also fires `UIImpactFeedbackGenerator`, which is the iOS substitute for a hover tooltip.

**Icons.** SF Symbols, one family throughout. Wrapped in an `Icon` enum in `Design/Icons.swift` so symbol names appear exactly once each and a rename is a single edit. Wave 1 set: `house`, `rectangle.stack`, `graduationcap`, `gearshape`, `plus`, `pencil`, `trash`, `clock`, `checkmark`, `xmark`, `chart.bar`, `checkmark.icloud`.

**Navigation.** Bottom tab bar in the thumb zone: Home, Decks, Study, Settings. Each item uses the outline symbol at rest and the `.fill` variant when current, which is the entire current-state signal. No accent on nav items, no underline. Icon runs large at about 1.6em with a small quieter caption. Safe-area inset reserved and the scroll container padded to match.

**Motion and feedback.** Three house behaviours come free from the platform and should use the system version rather than a reimplementation: swipe-back transition is `NavigationStack`, long-press context menu with backdrop blur and zoom is `.contextMenu`, and reduced motion is `@Environment(\.accessibilityReduceMotion)`. Everything else follows the rule that every action gets a visible response: async work shows a loader, success and failure both say so.

**Copy.** Sentence case, plain verbs, no em dashes, no ALL-CAPS eyebrows. Applies to every string in the app and to the App Store listing.

## 8. Screens

**Home.** Due and new counts across all decks, one row per deck with counts, a single primary action to start studying. Empty state when there are no decks.

**DeckList.** Decks with per-deck due and new counts. Create, rename, and delete. Delete is a `.contextMenu` destructive action with a confirmation, since there is no undo.

**DeckSettings.** New cards per day and desired retention. Retention is a slider constrained to the FSRS-sensible range with the resulting interval effect described in plain words, not just a number.

**Editor.** Create and edit notes in a deck. Note type picker (basic, basic reversed, cloze), term, definition, and the optional example and hint fields. Cloze syntax gets a live preview of the ordinals it produces, because `{{c1::...}}` is not discoverable otherwise. Saving reconciles the card set per Section 6.

**Study.** The FSRS loop. Card face, reveal, four-rating bar with predicted intervals on each button. Haptic on rating. Requeue behaviour per Section 6. Session summary on completion.

**Settings.** iCloud sync status, theme, and the wave-2 features listed as not yet available rather than hidden.

## 9. Testing

**Engine unit tests** in Swift Testing, with cases lifted directly from the existing TypeScript specs (`scheduler.test.ts`, `queue.test.ts`, `cards-from-note.test.ts`, `editor-row.test.ts`, `cloze` cases inside those). The TS tests are the oracle: same inputs, same expected outputs. This is the mechanism that catches a Swift FSRS port disagreeing with the one already trusted.

**One XCUITest smoke:** create deck, add note, study it, rate it, confirm the count decrements.

**CloudKit is verified by hand.** Two devices, same iCloud account, edit on one and confirm it appears on the other. It cannot be meaningfully unit-tested, and pretending otherwise would be worse than admitting it.

## 10. Prerequisites owned by Caleb

1. Apple developer console: bundle identifier for Elbert, plus an iCloud container `iCloud.<bundle-id>` with the CloudKit capability enabled. Same account as Remy and Blocks.
2. A second Apple device signed into the same iCloud account for the sync walk. Without it, sync ships unverified.

Neither blocks the start of implementation. Item 1 blocks the first build that touches CloudKit, which is task 3.

## 11. Risks

| Risk | Handling |
|---|---|
| Swift FSRS is a generation behind the web app (measured: tagged 5.0.0 is FSRS-5, web is FSRS-6) | Two options written up in section 6, decided and recorded in task 6 before any screen depends on it |
| CloudKit schema changes are effectively append-only once deployed to production | Model layer is finalised and reviewed in task 3, before data exists |
| Losing the soft-delete round-trip guarantee | Covered by an explicit reconciliation test, see Section 6 |
| Rewrite fatigue with no shippable artifact for a stretch | Wave 1 is deliberately the smallest genuinely usable app, and task order puts a studyable loop on device before the polish screens |

---

# Implementation plan

Execution is subagent-driven with a reviewer gate per task. Each task commits atomically.

### Task 1, project scaffold

Create `ios/Elbert` Xcode project, iOS 17 deployment target, Swift 6. Add SPM dependencies: `open-spaced-repetition/swift-fsrs`. Bundle DM Sans. Add a `.gitignore` for Xcode artifacts. No app logic.
**Verify:** project builds and launches to an empty view in the simulator.

### Task 2, design system

`Design/Theme.swift` (colour, spacing, radius, shadow tokens, light and dark), `Typography.swift` (roles, leading and tracking table, cap-to-baseline trim modifier), `Buttons.swift` (three `ButtonStyle`s with all states), `Icons.swift` (SF Symbol enum), `Feedback.swift` (haptics, toast, loader shapes).
**Verify:** a scratch preview screen renders every token, every button state, and every wave-1 icon in both colour schemes. Reviewed against the anti-vibecode non-negotiables before task 3 starts.

### Task 3, models and CloudKit container

`Models/` per Section 5. `ModelContainer` configured with a CloudKit private database. Requires the container from Section 10 item 1.
**Verify:** app launches, writes a `Deck`, relaunches, and the deck is still there. CloudKit dashboard shows the record types.

### Task 4, cloze engine

`Engine/Cloze.swift`: parse, render, answer-for-ordinal. Port of `src/engine/cloze.ts`.
**Verify:** unit tests covering duplicate ordinals, hint capture, out-of-order ordinals, and unrevealed rendering.

### Task 5, cards from note

`Engine/CardsFromNote.swift`: card set per note type, plus reconciliation on edit per Section 6 including the hard-delete change.
**Verify:** unit tests including the basic to reversed to basic round trip asserting exactly one live card per ordinal.

### Task 6, scheduler

`Engine/Scheduler.swift`: FSRS wrapper, review application with `Review` snapshot, four-rating interval preview with the existing label format.

**Decides the FSRS generation question from Section 6:** tagged 5.0.0 on FSRS-5, or `swift-fsrs` `main` pinned to a revision for FSRS-6 parity with the web app. Caleb's call, ask before implementing.
**Verify:** unit tests on label formatting boundaries and state transitions. Parity comparison against `ts-fsrs` recorded in the task report, including which generation was chosen and why.

### Task 7, queue

`Engine/Queue.swift`: eligibility filter, queue order, due counts, and the `UserDefaults` day counter.
**Verify:** unit tests on ordering across all four card states, allowance exhaustion, and exclusion of suspended and orphaned cards.

### Task 8, study session

`Engine/StudySession.swift`: the 20-minute requeue horizon at offset 5.
**Verify:** unit tests on requeue at horizon boundary, short-queue clamping, and session completion.

### Task 9, app shell

`RootView` with the bottom tab bar, four tabs, outline and fill state, safe-area handling, `NavigationStack` per tab. Placeholder content per tab.
**Verify:** all four tabs switch, fill state tracks the current tab, swipe-back works, nothing sits under the bar.

### Task 10, DeckList

Deck rows with live counts, create, rename, delete with confirmation.
**Verify:** create a deck, rename it, delete it, counts update live.

### Task 11, DeckSettings

New per day and desired retention, persisted.
**Verify:** change both, leave and return, values persist and affect the queue.

### Task 12, Editor

Note create and edit, type picker, five fields, cloze ordinal preview, card reconciliation on save.
**Verify:** each note type produces the right card count; editing a cloze to add an ordinal adds exactly one card and leaves existing ones untouched.

### Task 13, Study

The review loop, reveal, four-rating bar with predicted intervals, haptics, requeue, session summary.
**Verify:** study a deck end to end, ratings change future due dates, requeued cards reappear, summary counts are right.

### Task 14, Home

Aggregate counts, per-deck rows, primary study action, empty state.
**Verify:** counts match DeckList, empty state shows with no decks.

### Task 15, Settings

iCloud status, theme, wave-2 features listed as unavailable.
**Verify:** status reflects real container state, theme switch applies immediately.

### Task 16, smoke test and README

XCUITest covering create deck, add note, study, rate. Update `README` to state that the web app under `src/` is frozen, that `ios/` is where new work goes, and that the Neon sync setup is no longer needed by anything. No web code is deleted or edited.
**Verify:** UI test passes, `npm run build` still succeeds, Vercel deploy unaffected.

### Owed by Caleb after task 16

Two-device CloudKit walk, then a TestFlight build.
