# Build 010.41 — Enterprise Purchasing & Vendor Management

## Delivered
- Vendor directory, status, payment-term reference and contacts.
- Purchase orders and item lines with quantity, cost and subtotal.
- Locked submit/approve/cancel workflow with event history.
- Partial receiving and automatic completed/partial status.
- Transactional PO line receipt that updates inventory balance, movement ledger, received quantity and PO event together.
- Vendor invoice register with due dates and review/payment-status metadata.
- Authenticated role-restricted API, dashboard, acceptance contracts.

## Controls and limitations
- RLS enabled on six purchasing tables; direct client access revoked; service role is server-only.
- Purchase approval currently uses an allowlisted role gate, not a distinct approver permission matrix, dollar thresholds, or segregation-of-duties engine. Verify role claims and enforce stronger approval policy before production.
- Draft PO header and lines are separate API writes; failed line creation leaves a draft header requiring reconciliation.
- Invoice register is not accounts payable; no payment, bank, ACH, card, tax, accounting or supplier portal integration.
- No automatic replenishment, purchase suggestions or vendor price synchronization.
- PO receiving RPC performs balance, movement, line quantity and PO state updates in one database transaction.

## Validation
Run `npm run test:build010:purchasing`, `npm run lint`, and `npm run build`. Apply migration in staging after Build 010.40. Test RLS, role claims, state transition rejection, concurrent receiving, over-receipt prevention, partial/full receipt, and inventory balance reconciliation. Not merged, migrated or deployed.
