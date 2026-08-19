# Public governance record

This file is the sanitized public counterpart of the local UI governance
record. Detailed screenshots, handovers, course audits, and private design
evidence remain in the private companion repository.

- Active task: `148.16` — safe hands-off Flowmap automation
- Governed scope: Assistant conversation behavior and platform-safe tests
- Deterministic time: tests inject a fixed `now`; no planning-boundary test
  reads the wall clock
- Required evidence: unit tests, accessibility output, and simulator evidence
  when a visible UI surface changes
- Distribution boundary: no TestFlight or App Store upload
