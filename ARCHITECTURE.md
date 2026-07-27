# Flowmap — Architecture

## Shape of the app

One multiplatform SwiftUI app target builds both the iPhone and the Mac app
(`supportedDestinations: [iOS, macOS]`). There is no shared framework and no
second target: the feature set is genuinely shared, and the handful of real
divergences are handled at the shell level.

```
FlowmapApp
└── RootView
    ├── PhoneRootView   (iOS)    five-item tab bar + Assistant orb
    └── MacRootView     (macOS)  NavigationSplitView: Plan / Build / Review / AI
```

Everything below the shell — every feature view, every service, every model — is
the same code on both platforms.

## Layers

```
Features/          SwiftUI views. Own no logic that another feature needs.
   ↓ calls
Services/          The only place behaviour lives. Shared by the UI and the Assistant.
   ↓ mutates
Models/            SwiftData @Model types. The single source of truth.
   ↓ persisted by
Persistence/       Container construction, seed data, backup, sync status.
```

The rule that keeps this honest: **a feature never implements behaviour another
feature could need.** Scheduling lives in `SchedulingService`, focus timing in
`FocusEngine`, and the Assistant calls exactly those same entry points rather
than a second implementation of its own.

## Data model

Every persisted type carries a stable `UUID`, a `createdAt` and an `updatedAt`.

| Model | Purpose |
|---|---|
| `Workspace` | Top-level space (Personal, Work, Study) |
| `TaskList` | A user-created list. Smart views are queries, not lists. |
| `Project` | Work with its own tasks, maps and notes |
| `FlowTask` | The central unit of work. One identity for its whole life. |
| `TaskSegment` | One scheduled block of time belonging to one task |
| `Subtask` | Checklist item |
| `MapDocument` / `MapNode` | Mind map and its tree of ideas |
| `Note` / `NoteBlock` | Block-based notes |
| `FocusSession` | One run of the focus timer |
| `AssistantThread` / `AssistantMessage` | Conversation history |
| `AppSettings` | The single settings record |

### Three decisions worth knowing

**Enums persist as strings.** Each model stores `...Raw: String` and exposes a
computed enum. CloudKit-backed SwiftData wants primitive columns, and raw strings
stay usable from `#Predicate` — computed properties are not.

**Task identity is never duplicated.** When work is moved, missed or continued,
its *segments* change. The task itself is untouched. This is what makes
"unfinished work is requeued, never lost" possible without the task list
gradually filling with copies.

**Derived values are never stored.** `Project.progress` computes from its
actionable tasks every time it is read. There is no second progress field that
could disagree with it. The same applies to every Progress metric.

### CloudKit constraints observed throughout

- No unique attributes
- Every stored attribute has a default
- Every relationship is optional
- Every to-many relationship declares its inverse on exactly one side

## Scheduling

Two types, split by what they need to know:

**`SchedulingEngine`** is the maths — slot arithmetic, 5-minute snapping,
constraint narrowing, candidate ordering, chunking. It takes an explicit `now`
and `Calendar`, so its behaviour is reproducible in tests and correct across
time-zone and daylight-saving changes.

**`SchedulingService`** is the store-facing half: it reads the current schedule,
turns engine output into `TaskSegment`s, and provides undo.

### Planning

`proposePlan(for:now:replanExisting:)` returns a `PlanProposal` and writes
nothing. The UI previews it, then `apply(_:replanExisting:for:)` commits and
returns a `ScheduleSnapshot` that `undo(_:)` can restore exactly.

Order of respect, highest first:

1. External calendar events — never moved
2. Locked segments — never moved automatically, not even by an explicit replan
3. Overdue work, then work due today, then work flagged for today
4. Due-date urgency, then priority, then the user's manual order

`Plan my day` fills gaps and leaves existing placements alone. Only an explicit
*Replan the whole day* may lift unlocked blocks the user placed by hand.

### Requeueing

`reconcileMissedWork(now:)` marks passed-but-unfinished segments `.missed` and
gives their task a new segment — later today if there is room, otherwise the
earliest valid future day, searching up to 14 days ahead.

Idempotency comes from `TaskSegment.continuationOfSegmentID`. A missed segment
can be continued exactly once, so running reconciliation twice — or having two
devices run it after a sync — cannot produce duplicate blocks.

If there is genuinely nowhere to put the work, the task returns to the Inbox with
a stated reason. It never silently disappears.

## Focus

All timing is timestamps. `FocusSession` stores `startedAt`, an optional
`pausedAt`, and `accumulatedPausedSeconds`; remaining time is computed from them
on demand. Nothing decrements in memory, so a session survives backgrounding,
screen lock, process death, device sleep, and being watched from a second device.

`transitionProcessed` is claimed exactly once through `claimTransition()`. That
single boolean is what stops two app activations — or two devices — both
requeueing the same elapsed task.

### Wheel geometry

Angles are screen-space degrees: `0°` is east and, because the y axis points
down, increasing angle is **clockwise**. The bottom is `90°`.

The active task is centred on `90°` in every visibility mode. Upcoming tasks sit
one `sweep` further anticlockwise each — that is, up the right-hand side. When a
task ends, the ring turns clockwise by exactly one `sweep`, carrying the next
task down the right side into the bottom slot.

Elapsing time inside a task is drawn as a progress arc along the active segment
rather than by drifting the task off the bottom, which is what lets "the active
task is always at the bottom" and "the wheel turns clockwise" both hold at once.
Reduced Motion replaces the turn with a discrete update carrying the same
information.

## Services

| Service | Responsibility |
|---|---|
| `SchedulingService` / `SchedulingEngine` | All planning, placement and requeueing |
| `FocusEngine` | Timer, transitions, task hand-off |
| `CalendarService` | EventKit: permission, selected calendars, de-duplicated reads, optional write-back |
| `NotificationService` | Local notifications, keyed on segment id so rescheduling replaces rather than stacks |
| `SearchService` | Global search across five content types |
| `SpeechService` | Voice-to-text, entirely optional |
| `KeychainService` | API key values. Nowhere else holds them. |
| `AssistantService` / `AssistantToolRouter` | Provider adapters and the typed tool layer |
| `BackupService` | JSON export and UUID-keyed, duplicate-safe merge import |

`AppEnvironment` constructs these once at launch and injects them through
`@Environment(\.flow)`.

## Sync

SwiftData with `cloudKitDatabase: .automatic`, which reads the container from the
app's iCloud entitlement. Naming the container explicitly would hard-fail at
launch on an unsigned build; `.automatic` degrades to local-only storage instead,
and `CloudSyncStatus` reports why.

Conflict handling rests on stable UUIDs and `updatedAt` timestamps. Completion
and timer transitions are idempotent, so the same event arriving twice is
absorbed rather than doubled.

## Privacy

- No analytics SDK, no advertising SDK, no account server
- API key values live only in the Keychain — never in SwiftData, CloudKit,
  `UserDefaults`, logs, or error strings. `KeychainService.redact(_:)` strips
  anything key-shaped from text before it is shown or logged.
- Calendar access is optional and scoped to the calendars the user picks
- App content reaches an AI provider only when the user sends it
