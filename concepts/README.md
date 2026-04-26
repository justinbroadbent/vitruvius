# concepts/

Sketches of ideas the platform team has thought through but not yet built.

A `concepts/` entry is a deliberate signal: *we have considered this and produced a design.* It is not a commitment to ship. It is a working surface for the team's thinking, kept in the repo so the design exists if and when a build is funded.

## Lifecycle

A concept graduates one of three ways:

1. **Build.** Concept becomes an ADR and gets implemented. The original sketch is preserved in git history; the live docs move to the appropriate place (`docs/decisions/`, a new module, etc.).
2. **Reject.** Concept becomes an ADR-as-rejection — *"we considered this, here's why we chose not to."* The sketch is retained as historical record.
3. **Delete.** Concept is no longer interesting. Deletion goes through PR with a one-line note about why.

## Rules

- Concepts have **no enforcement**, no CI gates, no schema requirements.
- Concepts can be incomplete. They are working artifacts, not finished products.
- Concepts must be honest about their status — see the *Status* section every concept doc carries.
- Concepts should not pretend to be more than they are. A sketch is a sketch.

## Why this directory exists

Without a `concepts/` directory, designs that aren't ready to commit either (a) live in someone's notes and disappear, or (b) get prematurely promoted to ADRs and accumulate as commitments the team can't keep. Both are forms of [doc rot](../docs/anti-patterns.md#ap-009--doc-rot). A dedicated, clearly-labeled space for *thinking-in-progress* prevents both.
