# Flowmap project rules

## Identity and scope

Flowmap is a SwiftUI productivity app for iPhone, Mac, and Apple Watch. The
repository is source-visible with all rights reserved. This checkout is for
software work only: never automate TestFlight, App Store, payments, or
production distribution.

## Architecture

- `Flowmap/Features` owns user-facing screens and view models.
- `Flowmap/Services` owns persistence, scheduling, calendar, assistant, and
  watch communication.
- `Flowmap/Models`, `Flowmap/DesignSystem`, and `FlowmapWatch` are shared/core
  boundaries; keep platform-only code behind its real compiler boundary.
- `project.yml` is authoritative; regenerate the Xcode project after source
  or test membership changes.

## Safety and privacy

- Preserve unrelated dirty work. Never use `git reset --hard`, broad checkout,
  recursive deletion, or history rewriting without an explicit approved task,
  a verified recovery backup, and a clean restoration proof.
- Private operational material belongs in the private companion repository and
  must remain ignored locally. Never commit credentials, personal content,
  cognitive data, local paths, screenshots of private evidence, or provider
  prompts/tool arguments.
- Destructive assistant actions must continue to require confirmation.
- Fail closed when a required check, evidence record, or privacy scan is absent.

## Required workflow

- Track substantial work in Task Master. Keep the active task updated with
  evidence and do not mark it complete until verification is recorded.
- Before exploring Swift code, use codebase-memory search/trace/snippet tools;
  index the repository first when no current index exists. Read configs and
  non-code files before editing them.
- Use TDD: write a focused failing test, implement the smallest change, then
  run the relevant regression and full verification loop.
- Use `review-2` and the mirrored `ship` workflow for governed changes. The
  user does not need to inspect pull requests; Codex diagnoses failed checks
  and retries within this task.
- Required UI skill: `openai-apps-design-system`; `openai-native-ios` is excluded for Flowmap.
- For governed UI work, update `state/governance/current-ios-task.md` locally
  and provide the required HIG, accessibility, screenshot, and simulator
  evidence. Public CI receives only sanitized governance data.

## Verification commands

```sh
xcodegen generate
xcodebuild -project Flowmap.xcodeproj -scheme Flowmap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FlowmapTests CODE_SIGNING_ALLOWED=NO test
./scripts/build.sh mac test
./scripts/build.sh watch build
./scripts/check-instruction-clones.sh
```

The canonical iPhone baseline is 372 passing tests. If a destination is not
installed, report that as an environment failure rather than substituting an
unverified device. Use deterministic clocks for planning-boundary tests.

## Assistant boundary

Assistant execution is bounded and injectable: maximum four provider turns,
four tool calls per turn, eight total, newest 20 messages within 24,000
characters, 30-second request timeout, two transient retries, capped retry
delay, cancellation propagation, and a circuit breaker after three transient
failures. Feed every tool result back to the provider in order. Keep core
tools available normally and defer calendar tools until calendar intent or an
existing calendar exchange. Diagnostics contain only provider, latency,
retry count, tool count, and outcome.

## Public/private boundary

Public history must contain only sanitized source, governance, workflows, and
documentation. Before changing visibility, verify the encrypted backup can be
restored, the private companion repository is private, Gitleaks is clean, all
declared private paths are absent from every rewritten ref, and builds/tests
pass. Public licensing text must state `Flowmap — All rights reserved`.
