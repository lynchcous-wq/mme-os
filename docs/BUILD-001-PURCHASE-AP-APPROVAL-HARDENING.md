# Build 001 — Purchase & AP Approval Hardening

**Status:** Proposed additive migration; not applied.

This hardening adds an explicit payment-schedule approval transition. The approver must differ from both the payment-schedule creator and the invoice approver. Only a matched invoice with a recorded independent invoice approval can advance from draft to approved. The existing event recorder can then record provider/bank settlement events against an approved schedule.

The PO budget trigger now also rejects self-approval when the PO meets the configured approval threshold. Trusted backend role and location authorization remains mandatory; distinct UUIDs alone do not establish authority.