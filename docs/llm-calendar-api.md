# Calendar control API

Flowmap's calendar layer (`CalendarHub`, one merged busy-time source across
every connected account) is exposed to an LLM agent two ways:

- **In-app assistant** — `AssistantToolRouter` dispatches these as named tools
  alongside the existing task/project/map/note tools, using the same
  `AssistantToolResult` / confirmation / undo plumbing. Implemented in
  `Flowmap/Services/Calendar/CalendarControlAPI.swift`.
- **App Intents** — `Flowmap/Intents/CalendarIntents.swift` exposes the read
  operations and the most common write as Shortcuts/Siri-callable intents, for
  an external agent that drives the app rather than chats with it.

Tokens never cross this API. `AppSettings` only ever stores the Google OAuth
*client id*, which is public by design (the sign-in flow is PKCE, so there is
no client secret) — the access/refresh tokens Google issues stay in the
Keychain, behind `KeychainService`, and are never read, returned, or logged by
any tool here. Any configuration value that merely *looks* like a credential
(an API-key-shaped or `Bearer ...`-shaped string) is passed through
`KeychainService.redact(_:)` before it can reach a result message.

## Tools

| Tool | Arguments | Returns |
|---|---|---|
| `listCalendarAccounts` | *(none)* | One line per `CalendarAccountKind`: connected state, account label, calendars (with selection/read-only flags), last error. Read-only. |
| `connectCalendarAccount` | `account: "apple"\|"google"` | Starts the connect flow in the background and returns immediately — the UI shows the sign-in sheet. |
| `disconnectCalendarAccount` | `account` | **Confirmed first.** Disconnects the account and clears its selected calendars and settings flags. |
| `setCalendarSelection` | `account`, `calendarIds: [String]` | Persists the chosen calendars to the right settings field and refreshes the calendar window. |
| `setCalendarConfiguration` | `account`, `enabled?`, `googleClientId?`, `writeBackCalendarId?`, `writesFocusBlocks?` | Configuration only — never a token. Updates whichever fields are supplied. |
| `listCalendarEvents` | `startISO8601`, `endISO8601`, `account?` | Merged busy events in range, as a JSON array (`id`, `title`, `startISO8601`, `endISO8601`, `isAllDay`, `account`) — the `id` is what a follow-up `moveCalendarEvent`/`deleteCalendarEvent` call needs. Read-only, served from the same cache the planner reads. |
| `createCalendarEvent` | `account`, `calendarId`, `title`, `startISO8601`, `endISO8601` | **Confirmed first.** Starts the write in the background (the real event id only exists once it lands, so this one has no working undo — the result message says so). |
| `moveCalendarEvent` | `account`, `eventId`, `startISO8601`, `endISO8601` | **Confirmed first.** Moves the event; falls back to delete-and-recreate for a provider (Apple's) that can't edit an event in place. |
| `deleteCalendarEvent` | `account`, `eventId` | **Confirmed first.** Deletes the event. No undo — the result message says so. |

Every result message is one short, plain sentence (`listCalendarEvents`
returns structured JSON instead, since a follow-up move/delete call needs the
real event id back). An unknown account string, a missing argument, a
malformed ISO 8601 date, or an operation a provider refuses always comes back
as `success: false` with a clear reason — never a crash.

### Why some writes only say "started"

`AssistantToolRouter.handle`/`execute` are called synchronously from
`Flowmap/Features/Assistant/AssistantViewModel.swift`, which this feature
didn't touch. `CalendarHub`'s connect/create/move/delete calls are genuinely
asynchronous (Google is a network round trip), so `connectCalendarAccount`,
`createCalendarEvent`, `moveCalendarEvent` and `deleteCalendarEvent` fire a
background `Task` and hand back an honest "this has started" result straight
away — the real outcome lands in `CalendarHub`'s own `@Observable` state,
which the timeline and Settings screen already watch. This is the same
fire-and-forget pattern `CalendarHub.disconnect(_:)` already uses.

App Intents don't have this constraint — `perform()` is genuinely `async`, so
`ConnectCalendarAccountIntent`, `ListCalendarEventsIntent` and
`CreateCalendarBlockIntent` await the real `CalendarHub` call and report a
confirmed outcome (a real success/failure, not just "started").

## How an agent connects Google

1. The user must first put a Google OAuth client id into Settings → Calendar
   (`AppSettings.googleOAuthClientID`) — the flow uses PKCE, so this id is the
   only thing needed and it isn't a secret. `setCalendarConfiguration` with
   `{"account":"google","googleClientId":"…"}` can do this from the assistant.
2. Call `connectCalendarAccount {"account":"google"}` (or the
   `ConnectCalendarAccountIntent`). This starts the OAuth sheet; the user
   completes sign-in in the app.
3. Once connected, `listCalendarAccounts` reports it as connected with the
   signed-in account's label.
4. Call `setCalendarSelection {"account":"google","calendarIds":[...]}` with
   ids from `listCalendarAccounts`' calendar list to choose which Google
   calendars count as busy time.

## App Intents

`Flowmap/Intents/CalendarIntents.swift`: `ListCalendarAccountsIntent`,
`ConnectCalendarAccountIntent`, `DisconnectCalendarAccountIntent`,
`ListCalendarEventsIntent`, `CreateCalendarBlockIntent`. Each builds its own
`AppEnvironment` from `IntentStore.context` (mirroring the pattern in
`Flowmap/Intents/FlowmapIntents.swift`) and calls straight into
`CalendarHub`/`CalendarControlAPI` — never a concrete provider type.
