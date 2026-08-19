# UI rules

- Treat the existing SwiftUI screens and design tokens as the product source
  of truth. Keep user-visible behavior observable through accessibility IDs,
  text, and stable state.
- For governed UI changes, record the affected components and evidence in the
  local governance record, then run the simulator harness when required.
- Preserve platform boundaries: iPhone-only views and tests must not compile
  into the Mac target.
