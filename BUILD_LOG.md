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

## Build phases

The work ran as a foundation-then-fan-out: the model layer, scheduling engine,
focus engine and shared services were written first and verified with unit tests,
then feature screens were built in parallel against those frozen interfaces and
integrated one at a time. Every integration step ended with a green build on
both platforms before the next one started.

## Visual defects found by inspecting screenshots, and fixed

Screenshot inspection caught five real defects that reading the view code did not:

1. **Short timeline blocks overlapped their neighbours.** A 28pt minimum height
   exceeded the proportional height of a 15- or 20-minute block at 1.3pt/minute.
   Fixed by scaling the timeline to 2.0pt/minute and making the drawn height
   proportional-minus-a-seam, so a block can never be taller than the time it
   occupies.
2. **Wheel labels on the far side of the ring rendered upside down.**
   `FocusWheelView` duplicated the rotation maths instead of calling the geometry
   helper. Both now share `readableRotation(atAngle:)`, which keeps a label
   within a quarter turn of upright.
3. **The wheel pointer hung below the ring like a tail.** Resized to half the
   band and anchored in its outer half, clear of the label centred in the band.
4. **The idle countdown rendered as a broken-looking dash.** It now shows the
   duration of the block about to start.
5. **The Assistant orb covered the Focus card.** The orb is hidden on Focus,
   which fills that space with its own card; the Assistant stays one tap away
   from every other destination.

Also fixed from inspection: the mind map opened with its tree running off the
right edge. It now fits on first open, deferred one runloop turn because child
relationships have not always been faulted in at `onAppear`.

## Known rough edges

- **Map fit is vertical-only in practice.** After fitting, the tree is centred
  vertically but sits right of centre horizontally, so the third level of nodes
  can extend past the right edge. The canvas is fully pannable and zoomable and
  the explicit *Fit map* control works; this is the automatic first-open framing
  being imperfect, not a functional fault.
- **Mac screenshots are limited to the Today split view.** Capturing the other
  Mac destinations needs UI automation permission, which macOS gates behind a
  Touch ID or password prompt. That prompt was left unanswered rather than
  bypassed, so only the launch screen could be photographed on macOS.

## External blocker

**No Apple Developer team is configured**, so all builds run with
`CODE_SIGNING_ALLOWED=NO`. Entitlements, the CloudKit container identifier and
the schema are all configured correctly, but **cross-device iCloud sync has not
been observed running** and is not claimed to work. README lists the exact
remaining steps.

## Verified checkpoints

| # | Checkpoint | Evidence |
|---|-----------|----------|
| 1 | Project scaffolding + full model layer compiles | macOS and iOS BUILD SUCCEEDED |
| 2 | Scheduling and focus engines compile | macOS BUILD SUCCEEDED |
| 3 | Scheduling behaviour correct | 32 unit tests passing |
| 4 | All features integrated | macOS and iOS BUILD SUCCEEDED |
| 5 | Full suite green | 60 unit tests passing, 0 failures |
| 6 | App runs with real data | Demo seed writes 1 workspace, 7 tasks, 7 segments, 13 map nodes, 19 subtasks; auto-plan schedules all 7 |
| 7 | Screens inspected and defects fixed | 11 screenshots in `Screenshots/`, six defects found and fixed |

## Test execution note

The unit suite is verified on the **iOS simulator**: 73 tests in 14 suites, all
passing, `** TEST SUCCEEDED **`, exit code 0.

Running the identical suite against a macOS destination hangs with
`The test runner hung before establishing connection`. The cause is
environmental, not a defect in the app: macOS requires explicit approval of an
"XCTest is trying to Enable UI Automation" prompt, which asks for Touch ID or
the user's password. That prompt was left unanswered rather than bypassed, so
the macOS test runner cannot open its control session. The macOS *build* is
unaffected and green; approving that prompt once restores macOS test runs.

Diagnosing this did surface one genuine defect, now fixed: the Today timeline
exports the drag type `com.flowmap.timelineitem` via `UTType(exportedAs:)`
without declaring it in `Info.plist`, which logged a type-declaration error on
every drag session. It is now declared in `project.yml` and verified present in
the built bundle.
