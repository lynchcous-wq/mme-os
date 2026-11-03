# Build 001 — Explicit Cycle Count Confirmation

**Status:** Additive hardening migration committed; not applied.

Every cycle-count line now has a count_confirmed flag. Barcode scans and the trusted manual quantity-entry RPC set it true. Submission marks unconfirmed lines as exceptions rather than silently converting them to zero. Independent approval is blocked until every line has a confirmed physical quantity. An employee can explicitly confirm zero when an item is physically absent. Serialized-unit counts are constrained to zero or one.

The trusted backend must authenticate the employee, enforce location/count permissions, require a reason for material manual adjustments, and log the human actor. Opener cannot approve their own count. Existing variance posting remains the only path that changes aggregate stock or quarantines a missing serialized unit.