# Issue tracker: Task Master (MCP)

Issues for this repo live in the **taskmaster-ai MCP server**, on the **`flowmap-pages` tag** — never the `master` tag. Pass `tag: "flowmap-pages"` explicitly on every taskmaster-ai call, or lookups silently miss.

A GitHub remote exists, but GitHub Issues are NOT used for tracking work.

## When a skill says "publish to the issue tracker"

Create a task with `mcp__taskmaster-ai__add_task` (tag `flowmap-pages`). Put the spec or ticket body in the task's description/details. For a set of tracer-bullet tickets, create one task per ticket and record blocking edges as dependencies.

## When a skill says "fetch the relevant ticket"

`mcp__taskmaster-ai__get_task` with the task id, tag `flowmap-pages`. The user will normally pass the id.

## When a skill says "comment on the issue"

Append with `mcp__taskmaster-ai__update_subtask` (or update the task) — that is this tracker's comment trail.

## Triage state

Task Master has no labels. Record the triage role (see `triage-labels.md`) as a `Triage:` line at the top of the task's details, and mirror lifecycle with `set_task_status` (`pending` / `in-progress` / `done` / `deferred` / `cancelled`).

## PRs as a request surface

Off. External PRs are not part of the triage queue.
