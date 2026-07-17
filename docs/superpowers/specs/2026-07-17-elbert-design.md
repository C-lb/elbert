# Elbert — personal spaced-repetition study app

**Date:** 2026-07-17
**Status:** Approved (design walked through in conversation, all sections confirmed)

## What it is

A personal Quizlet + Anki hybrid for Caleb. Quizlet's study modes and AI authoring (free + Plus tier feature set), on top of Anki's learning engine (FSRS spaced repetition, note/card split, cloze deletions). Single user, phone-first PWA, fully offline-capable, local-first with cloud sync.

The moat being emulated is not Quizlet's content network (impossible and unneeded for a personal app) but Anki's: the append-only review history, which makes the scheduler's model of the user's memory ever more accurate. The review log is the crown jewels — append-only, never lossy, synced everywhere.

## Requirements

- Phone-first (study on iPhone), desktop for authoring. Delivered as a PWA (add-to-home-screen); no App Store, no Xcode. Wrappable in Capacitor later if push notifications are ever wanted.
- Content: languages/vocab, uni/professional exams, general facts. Card types: basic, basic+reversed, cloze. Images on cards. Device TTS for pronunciation.
- Study model: Anki core (FSRS daily due-queue across all decks) with Quizlet modes on top (Learn session, Test generator, Match game) that do not disturb the schedule.
- Authoring: AI generation from notes/PDFs (Claude), manual table editor, phone quick-capture to an Inbox deck, CSV/TSV import, .apkg Anki import.
- Offline: all reads and reviews work with zero network. Sync is opportunistic background replication.
- Card visuals: shadergradient (github.com/ruucm/shadergradient) animated gradient card backgrounds — explicit user request, a deliberate exception to the house no-gradient rule.

## Architecture

```
┌─ Phone / Mac browser (PWA) ──────────────────┐
│  React (Vite)                                │
│  ├─ Study engine: ts-fsrs + mode components  │
│  ├─ Dexie (IndexedDB): all app data          │
│  ├─ Service worker: offline shell + assets   │
│  └─ Sync client: push/pull queue             │
└──────────────┬───────────────────────────────┘
               │ HTTPS, x-elbert-key header
┌─ Vercel ─────┴───────────────────────────────┐
│  /api/sync      → Neon Postgres (mirror)     │
│  /api/generate  → Claude (cards from notes)  │
│  static PWA hosting                          │
└──────────────────────────────────────────────┘
```

- Device is the source of truth; Neon Postgres (provisioned through Vercel — Supabase free tier is full at 2 projects) is a replica for device convergence and disaster recovery.
- App boots straight from IndexedDB. Sync runs on launch, after a study session, and on regaining connectivity.
- Auth: single shared secret (long random token entered once per device, stored locally, sent as `x-elbert-key` header). No accounts.
- Stack: Vite + React + TypeScript, Dexie, ts-fsrs, Vite PWA plugin (Workbox), Vercel serverless functions, Neon Postgres, shadergradient (+ three / @react-three/fiber, lazy-loaded).

## Data model

Five tables, mirrored identically in Dexie and Postgres. All rows carry `id` (uuid), `updated_at`, `deleted_at` (soft delete so deletions sync).

- **decks** — name, parent_id (nesting, `Spanish::Verbs` style), config overrides (new cards/day, desired retention).
- **notes** — deck_id, type (`basic` | `basic_reversed` | `cloze`), fields (JSON: term, definition, example, image ref, hint), tags. Notes are content; cards are generated from them: reversed note → 2 cards, cloze note → 1 card per blank.
- **cards** — note_id, template ordinal, FSRS state (stability, difficulty, due, state: new/learning/review/relearning), suspended flag.
- **reviews** — append-only log: card_id, timestamp, rating (again/hard/good/easy), elapsed ms, scheduler snapshot. Never updated or deleted. Enables future FSRS parameter re-optimization and full recovery from scheduling bugs by replay.
- **media** — images, content-addressed by hash; blobs in Dexie, base64 in Postgres (fine at personal scale).

## Sync protocol

Hand-rolled, ~200 lines per side, single-user so trivially simple:

- **Push:** every local write marks the row dirty; sync sends dirty rows in batches; server upserts by id, last-write-wins on `updated_at`. `reviews` is insert-only on both sides — review history can never be clobbered by a stale device.
- **Pull:** client sends its last sync cursor (server-issued sequence number, not a timestamp); server returns rows changed since; client applies and stores the new cursor.
- **Conflicts:** last-write-wins is acceptable (same-note simultaneous offline edits are the only real case); the review log is exempt by construction. No merge UI.
- **Failure handling:** idempotent and resumable; every batch replayable. Offline just grows the queue; nothing in the UI blocks on sync. A small indicator shows pending count.

## Study engine

**Daily queue (core).** Home screen leads with cards due today across all decks (filterable per deck). Session = due cards + capped new cards (default 15/day, per-deck override). Reveal → rate Again/Hard/Good/Easy → ts-fsrs computes next due targeting 90% recall. Learning-stage cards re-queue within the session (intraday steps). Desktop keyboard shortcuts (space = reveal, 1–4 = rate); phone tap zones, one-handed.

**Cram modes** never touch FSRS state, with one exception: a "Good" during cram on a card that was due anyway counts as a review (no double work).

- **Learn session:** pick a deck; multiple-choice → typed answer; misses recycle until cleared twice. Typed grading diacritic-lenient, typo-tolerant (edit distance 1 on longer answers), "I was right" override.
- **Test generator:** paper from a deck — written / MC / true-false / matching mix, graded at the end, weakest cards listed.
- **Match:** timed tile grid, personal best per deck.

**TTS:** SpeechSynthesis speaker button on any card side; language auto-detected per deck (configurable); auto-play option for language decks.

## Authoring

All paths produce drafts confirmed before entering the schedule:

- **AI generation (`/api/generate`):** paste notes or upload PDF (parsed server-side); pick deck + card style (basic/reversed/cloze/mix); Claude returns structured drafts; review checklist UI (edit/delete/approve). Anthropic key in Vercel env.
- **Manual editor (desktop):** spreadsheet-style table, tab-through, bulk paste, image drop per row.
- **Quick capture (phone):** `+` on home, two fields, saves to Inbox deck; file into real decks later from Mac.
- **Import:** CSV/TSV (Quizlet export format) and .apkg (zip + SQLite, parsed client-side with JSZip + sql.js; scheduling state reset to new).

## PWA / offline

Vite PWA plugin precaches the app shell; cold offline launch works. Only sync, AI generation, and first install need network. Manifest with icon/splash. No push notifications in v1; possible later Telegram nudge via cron is out of scope.

## UI

Anti-vibecode house standards (one accent, neutral greys, flat buttons per standing ban, 17px mobile type, SVG icons, sentence-case, no em dashes) — except card faces, which carry shadergradient animated backgrounds by explicit request. Shader guard-rails: bundle lazy-loaded (offline shell stays light), single shared canvas, paused when off-screen, `prefers-reduced-motion` respected, off by default in Match.

## Testing

- Vitest unit tests: FSRS integration, dirty-queue and cursor logic, typed-answer grader, cloze parser, apkg/CSV importers.
- Integration: sync round-trip against local Postgres.
- Playwright smoke: core study flow.
- UI beyond that verified by walking it.

## Repo / deploy

`~/elbert`, private repo `C-lb/elbert`, Vercel deploys on push to main. Commit + push straight to main (standing preference).
