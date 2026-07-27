# Flowmap — Build Log

Records major decisions, verified checkpoints and genuine external blockers.

## Environment

- Xcode 26.6 (17F113), Swift 6.3.3
- SDKs: iOS 26.5, macOS 26.5
- Deployment targets: iOS 18.0, macOS 15.0
- Project generated from `project.yml` via XcodeGen; the generated
  `Flowmap.xcodeproj` is committed so the project opens without extra tooling.

## Decisions

1. **One multiplatform app target** (`supportedDestinations: [iOS, macOS]`) rather
   than two targets sharing a framework. The feature set is genuinely shared; the
   handful of divergences are handled with `#if os(macOS)` at the shell level
   (`PhoneRootView` / `MacRootView`) instead of duplicating the app.
2. **Enums persist as `String` raw values.** CloudKit-backed SwiftData is happiest
   with primitive columns, and raw strings stay usable from `#Predicate` — computed
   properties are not. Every model stores `...Raw: String` plus a computed enum.
3. **CloudKit-safe schema throughout**: no unique attributes, every stored attribute
   has a default, every relationship is optional, and every to-many relationship
   declares its inverse on exactly one side.
4. **Container degrades rather than fails.** `ModelContainerFactory.makeAppContainer()`
   tries the private CloudKit database first and falls back to a local-only store,
   reporting the reason through `CloudSyncStatus`. The app must run offline and
   without an iCloud account.
5. **Progress is always derived, never stored.** `Project.progress` computes from
   actionable tasks so a second stored value can never contradict it.
6. **Focus timing is timestamp-based.** `FocusSession` stores `startedAt`,
   `pausedAt` and `accumulatedPausedSeconds`; nothing decrements in memory, so a
   session survives backgrounding, sleep, process death and cross-device viewing.
   `transitionProcessed` makes the elapsed transition claimable exactly once.
7. **Builds run unsigned** (`CODE_SIGNING_ALLOWED=NO`) because no Apple Developer
   team is configured in this environment. Entitlements and the CloudKit container
   identifier are configured correctly regardless — see README for the exact
   remaining signing step.

## Verified checkpoints

| # | Checkpoint | Evidence |
|---|-----------|----------|
| 1 | Project scaffolding + full model layer compiles | `./scripts/build.sh both` → macOS BUILD SUCCEEDED, iOS BUILD SUCCEEDED |
