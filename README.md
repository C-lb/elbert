# Elbert

A spaced-repetition PWA: decks, notes (basic + cloze), FSRS-scheduled review, Learn/Study/Test/Match
modes, offline-first IndexedDB storage with optional sync, CSV/apkg import, and AI-assisted card
generation.

**`ios/` is where all new work goes.** The native SwiftUI app under `ios/` is the actively
developed client, with its own Xcode project, unit tests, and XCUITest suites (see
`ios/Elbert/Tests/`).

**The web app under `src/` is frozen.** It still builds and deploys as-is and is not being
deleted, but it receives no new features — treat it as a stable artifact, not a place to add code.
The Neon sync setup (`src/sync/client.ts` → `/api/sync` → `@neondatabase/serverless`) is no longer
needed by anything under active development — the frozen web app's optional sync is its only
remaining consumer, and that endpoint is still live. Do not tear down the Neon database on the
strength of this note.

- `npm run dev`: local dev server
- `npm test`: unit tests (vitest)
- `npm run e2e`: Playwright smoke test (builds and serves via `vite preview`)
- `npm run build`: production build
