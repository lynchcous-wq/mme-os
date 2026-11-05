import type { Money, TenderAllocation } from "../contracts/payments-center";

export type PosTransactionStatus =
  | "draft"
  | "inventory_reserved"
  | "pricing_confirmed"
  | "tendering"
  | "partially_tendered"
  | "fully_tendered"
  | "finalization_pending"
  | "finalized"
  | "reconciliation_required"
  | "cancelled";

export interface PosTransaction {
  id: string;
  orderId: string;
  currency: string;
  total: number;
  status: PosTransactionStatus;
  inventoryReservationReference?: string;
  calculationReference?: string;
  allocations: TenderAllocation[];
  finalizedAt?: string;
  revision: number;
}

export type PosTransactionEvent =
  | { type: "inventory_reserved"; reservationReference: string }
  | { type: "pricing_confirmed"; calculationReference: string; total: Money }
  | { type: "tender_submitted" }
  | { type: "tender_result"; allocation: TenderAllocation; confirmed: boolean; outcomeUnknown: boolean }
  | { type: "reconciliation_result"; allocations: TenderAllocation[]; matched: boolean }
  | { type: "finalization_started" }
  | { type: "finalization_confirmed"; finalizedAt: string }
  | { type: "cancelled" };

export class PosTransitionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PosTransitionError";
  }
}

function assertMoney(money: Money): void {
  if (!Number.isSafeInteger(money.amount) || money.amount < 0) {
    throw new PosTransitionError("Money must be a non-negative safe integer in minor units");
  }
  if (!/^[A-Z]{3}$/.test(money.currency)) {
    throw new PosTransitionError("Currency must be a three-letter uppercase ISO code");
  }
}

function capturedTotal(allocations: TenderAllocation[]): number {
  return allocations.reduce((sum, allocation) => {
    const amount = allocation.capturedAmount?.amount ?? 0;
    if (!Number.isSafeInteger(amount) || amount < 0) {
      throw new PosTransitionError("Captured amounts must be non-negative integer minor units");
    }
    return sum + amount;
  }, 0);
}

function assertAllocation(transaction: PosTransaction, allocation: TenderAllocation): void {
  if (allocation.transactionId !== transaction.id || allocation.orderId !== transaction.orderId) {
    throw new PosTransitionError("Tender allocation is bound to a different transaction or order");
  }
  assertMoney(allocation.requestedAmount);
  if (allocation.requestedAmount.currency !== transaction.currency) {
    throw new PosTransitionError("Tender currency does not match transaction currency");
  }
  if (allocation.capturedAmount) {
    assertMoney(allocation.capturedAmount);
    if (allocation.capturedAmount.currency !== transaction.currency) {
      throw new PosTransitionError("Captured currency does not match transaction currency");
    }
  }
  if (transaction.allocations.some(existing =>
    existing.allocationId === allocation.allocationId ||
    existing.idempotencyKey === allocation.idempotencyKey
  )) {
    throw new PosTransitionError("Duplicate tender allocation or idempotency key");
  }
}

export function createPosTransaction(input: {
  id: string;
  orderId: string;
  currency: string;
}): PosTransaction {
  if (!input.id || !input.orderId) throw new PosTransitionError("Transaction and order IDs are required");
  if (!/^[A-Z]{3}$/.test(input.currency)) throw new PosTransitionError("Currency must be a three-letter uppercase ISO code");
  return {
    id: input.id,
    orderId: input.orderId,
    currency: input.currency,
    total: 0,
    status: "draft",
    allocations: [],
    revision: 0,
  };
}

/**
 * Pure state transition only. It does not persist state, authorize a user,
 * reserve stock, call a provider, verify a webhook, or finalize an order.
 * The server-side caller must perform those operations through owning modules
 * and persist the resulting event atomically with its audit/outbox record.
 */
export function transitionPosTransaction(
  current: PosTransaction,
  event: PosTransactionEvent,
): PosTransaction {
  const next = { ...current, allocations: [...current.allocations], revision: current.revision + 1 };

  switch (event.type) {
    case "inventory_reserved":
      if (current.status !== "draft") throw new PosTransitionError("Inventory can only be reserved from draft");
      if (!event.reservationReference) throw new PosTransitionError("Reservation reference is required");
      next.inventoryReservationReference = event.reservationReference;
      next.status = "inventory_reserved";
      return next;

    case "pricing_confirmed":
      if (current.status !== "inventory_reserved") throw new PosTransitionError("Pricing requires an active inventory reservation");
      assertMoney(event.total);
      if (event.total.currency !== current.currency || event.total.amount <= 0) {
        throw new PosTransitionError("Transaction total must be positive and use the transaction currency");
      }
      if (!event.calculationReference) throw new PosTransitionError("Trusted calculation reference is required");
      next.total = event.total.amount;
      next.calculationReference = event.calculationReference;
      next.status = "pricing_confirmed";
      return next;

    case "tender_submitted":
      if (!["pricing_confirmed", "partially_tendered"].includes(current.status)) {
        throw new PosTransitionError("Tender can only start after trusted pricing and reservation");
      }
      next.status = "tendering";
      return next;

    case "tender_result": {
      if (current.status !== "tendering") throw new PosTransitionError("No tender operation is pending");
      assertAllocation(current, event.allocation);
      if (event.outcomeUnknown || event.allocation.status === "unknown_reconciliation") {
        next.allocations.push(event.allocation);
        next.status = "reconciliation_required";
        return next;
      }
      if (!event.confirmed) {
        if (event.allocation.status !== "declined" && event.allocation.status !== "cancelled") {
          throw new PosTransitionError("Unconfirmed tender result cannot advance transaction");
        }
        next.allocations.push(event.allocation);
        next.status = "partially_tendered";
        return next;
      }
      if (event.allocation.status !== "captured" && event.allocation.status !== "partially_refunded") {
        throw new PosTransitionError("Only provider-confirmed captured tender counts toward payment");
      }
      next.allocations.push(event.allocation);
      const totalCaptured = capturedTotal(next.allocations);
      if (totalCaptured > current.total) throw new PosTransitionError("Captured tender exceeds transaction total");
      next.status = totalCaptured === current.total ? "fully_tendered" : "partially_tendered";
      return next;
    }

    case "reconciliation_result":
      if (current.status !== "reconciliation_required") throw new PosTransitionError("Transaction is not awaiting reconciliation");
      if (!event.matched) {
        next.status = "reconciliation_required";
        return next;
      }
      if (event.allocations.some(a => a.transactionId !== current.id || a.orderId !== current.orderId)) {
        throw new PosTransitionError("Reconciliation returned an allocation for another transaction");
      }
      if (new Set(event.allocations.map(a => a.allocationId)).size !== event.allocations.length ||
          new Set(event.allocations.map(a => a.idempotencyKey)).size !== event.allocations.length) {
        throw new PosTransitionError("Reconciliation returned duplicate allocations");
      }
      for (const allocation of event.allocations) {
        assertMoney(allocation.requestedAmount);
        if (allocation.requestedAmount.currency !== current.currency) {
          throw new PosTransitionError("Reconciled tender currency mismatch");
        }
      }
      next.allocations = [...event.allocations];
      const totalCaptured = capturedTotal(next.allocations);
      if (totalCaptured > current.total) throw new PosTransitionError("Reconciled captures exceed transaction total");
      next.status = totalCaptured === current.total ? "fully_tendered" : "partially_tendered";
      return next;

    case "finalization_started":
      if (current.status !== "fully_tendered") throw new PosTransitionError("Finalization requires fully captured tender");
      next.status = "finalization_pending";
      return next;

    case "finalization_confirmed":
      if (current.status !== "finalization_pending") throw new PosTransitionError("No finalization is pending");
      if (!event.finalizedAt) throw new PosTransitionError("Finalization timestamp is required");
      next.finalizedAt = event.finalizedAt;
      next.status = "finalized";
      return next;

    case "cancelled":
      if (["fully_tendered", "finalization_pending", "finalized", "reconciliation_required"].includes(current.status)) {
        throw new PosTransitionError("Transaction cannot be cancelled in its current payment state");
      }
      next.status = "cancelled";
      return next;
  }
}
