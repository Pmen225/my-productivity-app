# Flowmap — Test Plan

## How to run

Run the unit tests on the **iOS simulator** — that is the verified path:

```bash
xcodebuild -project Flowmap.xcodeproj -scheme Flowmap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FlowmapTests CODE_SIGNING_ALLOWED=NO test
```

Latest run: **73 tests in 14 suites, all passing** (`** TEST SUCCEEDED **`).

The same suite on a macOS destination currently hangs before the test runner
connects. This is an environment problem, not a code one: macOS gates XCTest
behind a "trying to Enable UI Automation" prompt that needs Touch ID or the
user's password. That prompt was deliberately left unanswered, so the macOS
runner cannot establish its control session. Granting it once, or running
`xcodebuild ... -destination 'platform=macOS' test` from Xcode and approving the
prompt, unblocks macOS test runs. The macOS **build** is unaffected and green.

## Strategy

The riskiest logic in this app is invisible: whether a plan overlaps, whether a
missed task gets exactly one continuation, whether a timer survives being killed.
None of that is verifiable by looking at the screen, so it is covered by unit
tests that inject an explicit `now` and a fixed UTC `Calendar` — no test depends
on the machine's clock, locale or time zone.

What *is* only verifiable by looking — spacing, clipping, overlap, contrast — is
covered by screenshot inspection rather than assertions, because no assertion
proves a layout looks right.

`TestWorld` (`Tests/TestSupport.swift`) gives each test a fresh in-memory store,
a settings record, and helpers for building tasks and segments.

## Automated coverage

### Scheduling — `Tests/SchedulingTests.swift`

| Area | What is asserted |
|---|---|
| Candidate ordering | Overdue before due-today before flagged before the rest; priority then manual order within a group; satisfied and closed work excluded |
| Free slots | Busy time splits the day correctly; overlapping busy intervals collapse; nothing is offered before the `notBefore` floor |
| Constraints | Preferred period, earliest start and latest finish each narrow the usable window |
| No-overlap invariant | After planning, no two live segments overlap |
| Fixed events | External calendar events are never planned over |
| Locks | A locked block does not move, even under an explicit full replan, and nothing is placed on top of it |
| Gap filling | Plain *Plan my day* leaves manually placed blocks where the user put them |
| Splitting | A splittable task divides into chunks no smaller than its minimum, summing to its full estimate |
| Unsplittable work | Takes a whole gap or waits for a later day; never silently truncated |
| Overflow | Work that cannot fit today lands on a later day rather than being dropped |
| Idempotency | Planning twice produces no duplicate blocks |
| Undo | Restores the schedule exactly |
| Manual placement | Drops snap to five minutes; overlapping drops and moves are refused; locked blocks refuse to move |

### Missed and unfinished work — `Tests/SchedulingTests.swift`

| Area | What is asserted |
|---|---|
| Same-day requeue | A passed, unfinished block is marked missed and given a later slot today |
| Next-day carryover | With no room left today, the work moves to the next valid day |
| One identity | Requeueing never creates a second `FlowTask` |
| Idempotency | Reconciling three times creates one continuation and increments `carryoverCount` once |
| Closed work | Completed and cancelled tasks are not requeued |
| Continuation claim | The same segment can only ever be continued once |
| Nowhere to go | Unplaceable work returns to the Inbox with a stated reason — never vanishes |

### Focus — `Tests/FocusTests.swift`

| Area | What is asserted |
|---|---|
| Timestamp timing | Remaining time is correct for any moment, including long after the app died, and never goes negative |
| Pause and resume | The countdown freezes while paused and resumes without jumping |
| Repeated pauses | Paused seconds accumulate correctly; a double pause does not double-count |
| Transition claim | `claimTransition()` succeeds exactly once |
| Finish | Idempotent; the first outcome and actual time stand |
| Elapsed hand-off | An unfinished task gets exactly one continuation, even when processed twice |
| Completion | A finished task gets no continuation, and the time worked is recorded |
| Skip | Requeues the remainder instead of dropping it |
| Relaunch | A running session is recovered by a fresh engine |
| Queue | Ordered by start time, closed work excluded |

### Wheel geometry — `Tests/FocusTests.swift`

| Area | What is asserted |
|---|---|
| Bottom anchor | The active task centres on the bottom angle in all of 1, 2, 3 and All |
| Clockwise arrival | Upcoming tasks sit at lower angles, so they reach the bottom turning clockwise |
| Tiling | Segments divide the circle exactly, with no gap or overlap |
| Legibility | The active task's label is horizontal |
| Clamping | Visibility never asks for more segments than there are tasks, and an empty queue still draws one ring |

### Data integrity — `Tests/DataIntegrityTests.swift`

| Area | What is asserted |
|---|---|
| Project progress | Derived from actionable tasks; cancelled work excluded; paused work counts as outstanding; empty projects report zero |
| Map links | Conversion creates one task inheriting the idea's attributes; converting again returns the same task; node completion mirrors the task |
| Backup round-trip | Export and import preserve tasks, relationships and estimates |
| Duplicate-safe merge | Importing twice creates nothing the second time |
| Newer-wins | An older backup never overwrites a newer local edit |
| Malformed input | Rejected with a readable reason rather than a crash |
| Version guard | A newer format version is refused |
| Markdown export | Filenames are unique; block types render correctly |
| Capture parsing | Days, weekdays, 12- and 24-hour times, and compound durations; a bare number is not mistaken for a time; unparseable input still becomes a task |
| Smart views | Inbox, Today and Completed select the right work; priority grouping omits empty groups |

### UI tests — `UITests/`

Cover the flows from spec §22 that are checkable without accessibility
identifiers the features do not yet expose: launch, the absence of any permanent
full-width add row, the list ellipsis popover hierarchy, calendar month
navigation without crash or duplicated dates, and persistence across relaunch.

## Manual verification

These need a person looking at the screen.

### Visual (screenshots in `Screenshots/`)

- iPhone Today, Focus wheel at the default 2-task visibility, expanded subtask
  card, Map
- Mac Today split view, Map with inspector, Notes editor
- Dark mode versions of Today and Focus

Check specifically: the active task is the bottom wheel segment; the pointer is
stationary; the resting card does not touch the wheel; the expanded card reaches
at least three fifths of the screen; segment titles and durations stay legible;
the tab bar and Assistant orb never cover content.

### Behaviour that needs real hardware or accounts

| Check | Why it cannot be automated here |
|---|---|
| Cross-device iCloud sync | Needs Apple signing credentials and two devices — **not verified**, see README |
| Notification delivery and deep links | Needs a device and granted permission |
| Calendar read and write-back | Needs a real calendar and granted permission |
| Speech recognition | Needs a microphone and granted permission |
| Assistant against a live provider | Needs an API key |
| VoiceOver rotor and focus order | Needs the screen reader |
| Time-zone change mid-session | Needs the system clock changed |

## Known gaps

- **Cross-device sync is unverified.** The schema is CloudKit-compatible and the
  entitlements are configured, but no signed build has run on two devices. The
  README states the exact remaining steps.
- UI test coverage is narrower than the fourteen flows listed in the spec,
  because most feature views do not yet expose accessibility identifiers stable
  enough to query. The flows above are the subset that can be asserted honestly.
