# Flowmap

A native iPhone and Mac productivity app built around one loop:

> Capture an idea → expand it visually → turn branches into tasks → schedule them
> automatically → work through one at a time → requeue whatever you did not finish.

Swift and SwiftUI throughout. SwiftData for persistence, CloudKit for private
sync, EventKit for optional calendar integration.

## Requirements

- Xcode 26.6 or later
- iOS 18.0+ / macOS 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you want to regenerate the
  project file (`brew install xcodegen`)

## Build and run

The generated `Flowmap.xcodeproj` is committed, so the project opens directly:

```bash
open Flowmap.xcodeproj
```

Pick the **Flowmap** scheme and choose either a Mac destination or an iPhone
simulator. If you change `project.yml` or add files outside Xcode, regenerate:

```bash
xcodegen generate
```

### From the command line

```bash
./scripts/build.sh both          # build macOS and iOS
./scripts/build.sh mac           # macOS only
./scripts/build.sh ios           # iOS simulator only
./scripts/build.sh mac test      # build and run the test suite
```

The script prints only the failure lines when something breaks. Set
`FLOWMAP_DERIVED` to use a separate build directory, and `FLOWMAP_SIM` to pick a
different simulator (default: `iPhone 17 Pro`).

## Signing and CloudKit — the remaining manual step

**This build is unsigned.** No Apple Developer team was available in the
environment where it was written, so builds run with `CODE_SIGNING_ALLOWED=NO`.

Everything that does not require an Apple Developer account is complete and
verified: both platforms compile, the full local data layer works, and the
entitlements and container identifier are configured correctly in
`Flowmap/Resources/Flowmap.entitlements`.

**Cross-device iCloud sync has therefore not been observed running.** The schema
is CloudKit-compatible and the container is configured, but nobody has watched a
task created on an iPhone appear on a Mac. Treat sync as configured-but-unverified
until you complete these steps:

1. Open `Flowmap.xcodeproj` and select the **Flowmap** target.
2. **Signing & Capabilities** → tick *Automatically manage signing* and choose
   your Team.
3. Change the bundle identifier from `com.flowmap.app` to something you own, for
   example `com.yourname.flowmap`.
4. Add the **iCloud** capability, tick **CloudKit**, and create a container named
   `iCloud.<your bundle identifier>`.
5. Add the **Background Modes** capability and tick **Remote notifications** —
   CloudKit needs it to push changes between devices.
6. Update `cloudKitContainerIdentifier` in
   `Flowmap/Persistence/ModelContainerFactory.swift` to match your container.
7. Build and run on two devices signed into the same iCloud account.

The app deliberately does not fail without any of this. `ModelContainerFactory`
uses `cloudKitDatabase: .automatic`, which reads the container from the
entitlement and falls back to a local-only store when there isn't one. The app
runs fully offline and without an iCloud account; `CloudSyncStatus` reports the
reason in **Settings → Data**.

## Optional permissions

Each is requested in context, and the app works without any of them.

| Permission | Asked when | Without it |
|---|---|---|
| Calendar | You enable calendar integration in Settings | Planning simply has no external events to avoid |
| Notifications | You first schedule work worth a reminder | No reminders; scheduling still works |
| Speech | You first tap the microphone | The mic hides itself; typing is unaffected |

## The AI Assistant is optional

The entire app works with no API key. Without one, the Assistant explains setup
in a line or two and still runs local deterministic commands such as
`Add gym tomorrow at 9 for 1 hour`.

To enable the full assistant, go to **Settings → Assistant**, choose a provider
(Anthropic or OpenAI) and paste a key.

**Keys are stored in the Keychain only.** They are never written to SwiftData,
CloudKit, `UserDefaults`, logs or error messages. `KeychainService.redact(_:)`
strips anything key-shaped from text before it is displayed.

## Demo data

On first launch, **Settings → Data → Load demo workspace** creates the Personal
workspace, the Weekly Plan map and the seven demo tasks. It is offered rather
than loaded silently, so it never pollutes real data. **Reset demo data** removes it.

## Project layout

```
Flowmap/
  App/            entry point, environment, menu commands, deep links
  Models/         SwiftData models and the enums they persist
  Persistence/    container, seed data, backup, sync status
  Services/       scheduling, focus, calendar, notifications, search, speech, keychain
  Features/       one folder per screen area
  DesignSystem/   theme, typography, spacing, shared components
  Intents/        App Intents (Add Task, Start Focus, Open Today)
Tests/            unit tests
UITests/          UI tests
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit together,
[TEST_PLAN.md](TEST_PLAN.md) for what is verified and how, and
[BUILD_LOG.md](BUILD_LOG.md) for the decisions taken along the way.

## Keyboard shortcuts (Mac)

| Shortcut | Action |
|---|---|
| `⌘N` | New task (quick capture) |
| `⌘⇧N` | New note |
| `⌘K` | Global search |
| `⌘↩` | Start focus on the selected task |
| `⌘⇧P` | Pause or resume focus |
| `⌘1`–`⌘5` | Today, Inbox, Calendar, Focus, Map |
