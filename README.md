# Elbert

A spaced-repetition PWA: decks, notes (basic + cloze), FSRS-scheduled review, Learn/Study/Test/Match
modes, offline-first IndexedDB storage with optional sync, CSV/apkg import, and AI-assisted card
generation.

**`ios/` is where all new work goes.** The native SwiftUI app under `ios/` is the actively
developed client, with its own Xcode project, unit tests, and XCUITest suites (see
`ios/Elbert/Tests/`).

**The web app under `src/` is frozen.** It still builds and deploys as-is and is not being
deleted, but it receives no new features — treat it as a stable artifact, not a place to add code.
The Neon sync setup that the web app's optional sync used is no longer needed by anything and can
be considered dead infrastructure from here on.

- `npm run dev`: local dev server
- `npm test`: unit tests (vitest)
- `npm run e2e`: Playwright smoke test (builds and serves via `vite preview`)
- `npm run build`: production build
