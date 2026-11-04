# Build 001 — Atomic Channel Claim-to-Order Conversion

**Status:** Additive migration committed; not applied.

Converts an active, unexpired POS quote, customer hold, subscription allocation, auction allocation or manual stock claim into the existing order and inventory-reservation ledger in one database transaction. The conversion preserves already-reserved stock and does not increment reserved quantities a second time.

The conversion snapshots current catalog prices and creates order lines plus the matching aggregate or serialized reservation records expected by the existing payment processors. Idempotency is enforced through the order key and the claim-to-order link. Converted claims become terminal and cannot be released by the claim expiry worker.

**Safety boundary:** mixed aggregate-plus-serialized claims are rejected until one payment processor can consume both reservation types atomically. The trusted server must bind the Stripe PaymentIntent to the resulting order and process only signature-verified webhooks using the existing aggregate or serialized payment RPC. Conversion itself does not charge a customer. Identity UUIDs are attribution, not authentication; server-side authorization is mandatory.