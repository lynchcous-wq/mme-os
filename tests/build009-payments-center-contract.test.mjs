import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../lib/contracts/payments-center.ts", import.meta.url), "utf8");

test("Payments Center contract models tender lifecycle and approved methods", () => {
  for (const value of ["card_present", "card_not_present", "cash", "gift_card", "financing", "store_credit"]) {
    assert.match(source, new RegExp(`"${value}"`));
  }
  for (const value of ["authorize", "capture", "sale", "void", "refund"]) {
    assert.match(source, new RegExp(`"${value}"`));
  }
  assert.match(source, /unknown_reconciliation/);
  assert.match(source, /partially_refunded/);
});

test("Tender contract includes idempotency, actor, reconciliation and safe failure data", () => {
  for (const value of ["idempotencyKey", "actorPersonId", "reconcile(", "requiresReconciliation", "outcomeUnknown", "providerAccountReference"]) {
    assert.ok(source.includes(value), `Missing contract field: ${value}`);
  }
});

test("Contract excludes raw cardholder data fields and marks provider events as verified", () => {
  for (const forbidden of ["cardNumber:", "pan:", "cvv:", "cvc:", "pin:", "trackData:"]) {
    assert.ok(!source.toLowerCase().includes(forbidden.toLowerCase()), `Forbidden sensitive field: ${forbidden}`);
  }
  assert.match(source, /interface VerifiedPaymentEvent/);
  assert.match(source, /after signature verification/);
});

test("Adapter exposes create, capture, void, refund and reconciliation operations", () => {
  for (const method of ["createTender(", "captureTender(", "voidTender(", "refundTender(", "reconcile("]) {
    assert.ok(source.includes(method), `Missing adapter operation: ${method}`);
  }
});
