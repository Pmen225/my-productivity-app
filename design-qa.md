# Flowmap dependency stack — design QA

final result: passed

## Scope

- Reference: `state/design-refs/timo/timo-13.png` — 384 × 767 px.
- Implementation capture: `Screenshots/premium-ios26/timo-hierarchy/iphone-task-dependency-stack.png` — 1206 × 2622 px.
- State: iPhone dark appearance, Plan → Inbox, one parent task, one dependency, then one unrelated root task.
- The requested scope is the dependency relationship inside Flowmap's existing native shell, not a full Tiimo screen clone.

## Normalised comparisons

- Full-screen comparison: `Screenshots/premium-ios26/timo-hierarchy/full-comparison.png`.
- Focused task-region comparison: `Screenshots/premium-ios26/timo-hierarchy/task-region-comparison.png`.
- The full comparison removes Tiimo's device bezel and normalises both screens by content height. The focused comparison crops to the task-list region so hierarchy, spacing, shape, and type can be judged without unrelated chrome.

## Findings

- Structure: passed. The dependency sits directly beneath its parent within one joined visual group. The next root starts a separate card with a larger gap.
- Geometry: passed. Parent and dependency share the same outer leading edge and width; the shared boundary has no card gap; only the dependency content is indented.
- Shape: passed. The parent owns the top corners, the dependency owns the bottom corners, and a subtle separator makes the relationship readable without creating a second standalone card.
- Typography and copy: passed. Flowmap's shared SF typography is retained, with the dependency relationship capped at two lines (`Subtask B` and `Project A`).
- Colour and materials: passed. Near-black neutral surfaces, lavender duration chips, and purple accents match the reference direction while staying within Flowmap's semantic design tokens.
- Native behaviour: passed. Each visual row remains its own native List cell, preserving swipe actions, context actions, Dynamic Type, VoiceOver, and the 44 pt completion target.
- Accessibility: passed. The dependency exposes an explicit parent relationship and a stable outer-row accessibility frame used by the geometry acceptance test.

## Three-pillar review

- Frictionless — PASS: the parent/dependency relationship is visible without opening an editor, and each task keeps its familiar completion and row actions.
- Quality Craft — PASS: shared edges, complementary corners, separator alignment, child-only indentation, and the Flowmap token system produce one deliberate group rather than two shifted cards.
- Trustworthy — PASS: hierarchy order matches the stored relationship, unrelated roots remain visually separate, and VoiceOver names the dependency's parent.

## Comparison history

1. Initial implementation still read as equal cards shifted sideways; its dependency rail was centred inside the child inset and the two surfaces did not form a single stack.
2. Final pass aligned the rail to the group's outer edge, removed intra-group spacing, introduced top/middle/bottom card positions, indented only child content, and exposed the full row frame to accessibility.
3. Final screenshot review found no P0, P1, or P2 discrepancies within the requested dependency-stack scope.
