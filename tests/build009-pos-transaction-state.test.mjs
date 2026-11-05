import test from "node:test";
import assert from "node:assert/strict";
import {
  createPosTransaction,
  transitionPosTransaction,
  PosTransitionError,
} from "../lib/pos/transaction-state.ts";

const money = (amount, currency = "USD") => ({ amount, currency });
function allocation(overrides = {}) {
  return {
    allocationId: "alloc-1",
    transactionId: "tx-1",
    orderId: "order-1",
    method: "card_not_present",
    operation: "sale",
    requestedAmount: money(1000),
    capturedAmount: money(1000),
    status: "captured",
    provider: "test-provider",
    providerAccountReference: "test-account",
    providerPaymentReference: "pay-ref-1",
    idempotencyKey: "idem-1",
    createdAt: "2026-11-05T12:00:00.000Z",
    updatedAt: "2026-11-05T12:00:01.000Z",
    reconciliationStatus: "matched",
    ...overrides,
  };
}
function pricedTransaction(total = 1000) {
  let tx = createPosTransaction({ id: "tx-1", orderId: "order-1", currency: "USD" });
  tx = transitionPosTransaction(tx, { type: "inventory_reserved", reservationReference: "res-1" });
  tx = transitionPosTransaction(tx, { type: "pricing_confirmed", calculationReference: "calc-1", total: money(total) });
  return tx;
}

test("transaction requires reservation and trusted pricing before tender", () => {
  const tx = createPosTransaction({ id: "tx-1", orderId: "order-1", currency: "USD" });
  assert.throws(() => transitionPosTransaction(tx, { type: "tender_submitted" }), PosTransitionError);
  assert.throws(() => transitionPosTransaction(tx, { type: "pricing_confirmed", calculationReference: "calc-1", total: money(1000) }), PosTransitionError);
});

test("fully captured tender is required before finalization", () => {
  let tx = pricedTransaction();
  tx = transitionPosTransaction(tx, { type: "tender_submitted" });
  tx = transitionPosTransaction(tx, { type: "tender_result", allocation: allocation(), confirmed: true, outcomeUnknown: false });
  assert.equal(tx.status, "fully_tendered");
  tx = transitionPosTransaction(tx, { type: "finalization_started" });
  assert.equal(tx.status, "finalization_pending");
  tx = transitionPosTransaction(tx, { type: "finalization_confirmed", finalizedAt: "2026-11-05T12:01:00.000Z" });
  assert.equal(tx.status, "finalized");
});

test("unknown provider outcome enters reconciliation and cannot be retried as a fresh tender", () => {
  let tx = pricedTransaction();
  tx = transitionPosTransaction(tx, { type: "tender_submitted" });
  tx = transitionPosTransaction(tx, {
    type: "tender_result",
    allocation: allocation({ status: "unknown_reconciliation", capturedAmount: undefined }),
    confirmed: false,
    outcomeUnknown: true,
  });
  assert.equal(tx.status, "reconciliation_required");
  assert.throws(() => transitionPosTransaction(tx, { type: "tender_submitted" }), PosTransitionError);
  const stillBlocked = transitionPosTransaction(tx, { type: "reconciliation_result", allocations: [], matched: false });
  assert.equal(stillBlocked.status, "reconciliation_required");
});

test("split tender accumulates captured minor units and blocks overpayment", () => {
  let tx = pricedTransaction(1000);
  tx = transitionPosTransaction(tx, { type: "tender_submitted" });
  tx = transitionPosTransaction(tx, {
    type: "tender_result",
    allocation: allocation({ allocationId: "alloc-a", idempotencyKey: "idem-a", requestedAmount: money(400), capturedAmount: money(400) }),
    confirmed: true,
    outcomeUnknown: false,
  });
  assert.equal(tx.status, "partially_tendered");
  tx = transitionPosTransaction(tx, { type: "tender_submitted" });
  tx = transitionPosTransaction(tx, {
    type: "tender_result",
    allocation: allocation({ allocationId: "alloc-b", idempotencyKey: "idem-b", requestedAmount: money(600), capturedAmount: money(600) }),
    confirmed: true,
    outcomeUnknown: false,
  });
  assert.equal(tx.status, "fully_tendered");
  let over = pricedTransaction(1000);
  over = transitionPosTransaction(over, { type: "tender_submitted" });
  assert.throws(() => transitionPosTransaction(over, {
    type: "tender_result",
    allocation: allocation({ requestedAmount: money(1200), capturedAmount: money(1200) }),
    confirmed: true,
    outcomeUnknown: false,
  }), PosTransitionError);
});

test("rejects cross-order, cross-currency, duplicate allocation and premature cancellation", () => {
  let tx = pricedTransaction();
  tx = transitionPosTransaction(tx, { type: "tender_submitted" });
  assert.throws(() => transitionPosTransaction(tx, {
    type: "tender_result",
    allocation: allocation({ orderId: "other-order" }),
    confirmed: true,
    outcomeUnknown: false,
  }), PosTransitionError);
  assert.throws(() => transitionPosTransaction(tx, {
    type: "tender_result",
    allocation: allocation({ requestedAmount: money(1000, "EUR"), capturedAmount: money(1000, "EUR") }),
    confirmed: true,
    outcomeUnknown: false,
  }), PosTransitionError);
  tx = transitionPosTransaction(tx, { type: "tender_result", allocation: allocation(), confirmed: true, outcomeUnknown: false });
  assert.throws(() => transitionPosTransaction(tx, { type: "cancelled" }), PosTransitionError);
  tx = transitionPosTransaction(tx, { type: "finalization_started" });
  assert.throws(() => transitionPosTransaction(tx, { type: "finalization_confirmed", finalizedAt: "" }), PosTransitionError);
});
