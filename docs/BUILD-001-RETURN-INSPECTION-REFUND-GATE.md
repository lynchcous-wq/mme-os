# Build 001 — Return Inspection & Refund Gate

**Status:** Additive migration committed; not applied.

Adds a disposition function that links a return line to a matching customer-return inspection, validates product, location and serialized-unit identity, resolves the inspection through the existing aggregate or serialized inventory workflow, and updates the return line and case status.

A database trigger blocks refund-approval records until every non-rejected return line has a linked, completed customer-return inspection matching its product, location and serialized device. Pending, missing, mismatched or incomplete inspections prevent approval.

The existing refund provider event ledger remains separate: this change does not initiate Stripe or other payment refunds. Trusted server-side authentication and role checks remain required; identity UUID parameters alone are not proof of authorization.