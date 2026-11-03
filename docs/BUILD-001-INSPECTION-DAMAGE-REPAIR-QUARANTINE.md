# Build 001 — damage, repair, quarantine, and returns

**Status:** Proposed additive migration; not applied.

## Inspection record
Each inspection records a unique reference, product/location, inspection type, condition before/after, findings, photo-evidence references, reason, inspector, approver, resolver and timestamps. Evidence is stored as references/metadata; upload storage must use a private bucket with signed, expiring access and malware/type/size validation.

## Aggregate stock
Units placed into repair, quarantine, damage, write-off or supplier-return disposition are removed from sellable on-hand stock. An aggregate hold ledger tracks the held quantity and cost. Only an approved return-to-stock resolution puts units back into on-hand. Write-off and supplier return permanently close the hold without increasing sellable stock.

## Serialized devices
The individual device is moved from in-stock/sold into repair or quarantine and retains its serial/IMEI identity. Resolution can return it to stock only with a saleable condition grade. Write-off/supplier-return remain quarantined pending a later financial/disposal workflow; the record is not deleted.

## Security and approvals
All mutation functions are service-role only. The trusted server must authenticate the acting employee, enforce permission and CEO/manager approval thresholds, validate photo references, and pass verified actor/approver identities. UUID fields alone do not prove authorization. IMEI/serial data and inspection photos are never public catalog fields.

## Important limits
This migration does not automatically convert a customer return into inventory. The returns/refunds build must link the original order, verify refund/return authorization, then invoke inspection. It also does not issue refunds, send supplier claims, or delete sold history. Test aggregate and serialized transitions, reserved-stock protection, duplicate references, photo limits, rollback, and concurrent inspection resolution in disposable PostgreSQL.
