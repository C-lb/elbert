# Elbert, iOS

Swift 6 / SwiftUI / SwiftData, iOS 17+. The project is generated from `project.yml`, so
`Elbert.xcodeproj` is disposable.

```sh
brew install xcodegen          # once
cd ios && xcodegen generate
xcodebuild -project Elbert.xcodeproj -scheme Elbert \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ElbertTests test
```

Anything added under `Elbert/App`, `Design`, `Models`, `Engine`, `Screens`, or `Resources` is
picked up by a regenerate. New folders need a `sources` entry in `project.yml` first.

The spec and the task list live in
`docs/superpowers/specs/2026-07-29-elbert-ios-native-design.md`.

## Turning CloudKit sync on

Sync is written but compiled out. `Persistence` opens a local store and reports
`StoreHealth.localOnly`, because signing a build against an iCloud container that is not
registered in the developer account fails outright, so the entitlement cannot be attached
speculatively.

To enable it:

1. In the Apple developer console, register the iCloud container `iCloud.com.calebl.elbert`
   against the `com.calebl.elbert` app id, with the CloudKit capability on. Same account as
   Remy and Blocks.
2. In `project.yml`, uncomment the two lines under the `Elbert` target's `settings.base`:
   `CODE_SIGN_ENTITLEMENTS` and `SWIFT_ACTIVE_COMPILATION_CONDITIONS`.
3. `xcodegen generate`, then build to a real device. The simulator does not exercise the mirror.

`Elbert/Elbert.entitlements` is already written and requests only the private database. If the
container id ever changes it has to change in three places: that file, `Persistence.cloudKitContainerID`,
and the test that asserts the two agree.

Sync itself is verified by hand, on two devices signed into the same iCloud account. There is no
meaningful automated substitute for that.

## Model layer gotchas

- **No `@Attribute(.unique)`.** The CloudKit mirror rejects unique constraints. `id` is a plain
  `UUID` and de-duplication is application logic.
- **Every property optional or defaulted, every relationship optional with an inverse.** The
  "every model constructs with no arguments" test is what keeps the first half honest.
- **Never name a persisted property `hash`.** SwiftData reads properties through key-value
  coding and `hash` is already `NSObject`'s `Int`, so a `String` under that name compiles fine
  and then crashes on first fetch with an `NSNumber` to `NSString` cast failure. `MediaAsset`
  uses `contentHash`. The same trap applies to `description` and `superclass`.
- **Deleting a deck cascades to its notes but promotes its subdecks.** Deck deletion has no
  undo, and taking a whole subtree with it is not something a confirmation dialog really warns
  about.
