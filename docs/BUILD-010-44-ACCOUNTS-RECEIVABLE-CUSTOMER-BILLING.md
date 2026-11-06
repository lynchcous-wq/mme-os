# Build 010.44 — Enterprise Accounts Receivable & Customer Billing

## Delivered
- Customer invoice ledger with unique invoice numbers and source references.
- Payment ledger and invoice allocation RPC with row locks, customer validation and balance caps.
- Credit memo issuance RPC with invoice ceiling validation.
- Manual collections reminder queue.
- Invoice outstanding-balance view and customer aging buckets.
- Authenticated finance API and dashboard.
- RLS, service-role-only access, acceptance contracts.

## Release boundaries
- Customer UUID must match the existing MME customer identity source; this build does not create or synchronize customer profiles.
- Payment recording is an accounting entry only. It does not charge cards, initiate ACH, verify settlement or integrate Stripe subscriptions.
- Payment allocations must be manually recorded and independently reconciled to processor/bank settlement.
- Credit memos are issued in pending-application state; no apply/void workflow is exposed yet, so issued memos do not reduce balances.
- Reminder queue records are not delivered; email/SMS provider integration and opt-out/compliance controls remain future work.
- No invoice PDF/email delivery, recurring billing scheduler, tax calculation, customer statement delivery, write-off workflow, refund processor or GL journal bridge.
- Invoice creation and reminder creation use restricted service-role API writes; full audit-trigger coverage for those direct inserts must be added before production.
- Currency consistency and customer identity mapping need staging validation.

## Validation
Run `npm run test:build010:ar`, `npm run lint`, and `npm run build`. Apply migration in staging after Build 010.43. Validate customer ownership, allocation concurrency, duplicate references, partial payments, overpayment rejection, credit memo ceilings, aging cutoffs and RLS. Not merged, migrated or production deployed.
