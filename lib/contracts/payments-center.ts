/**
 * Build 009 / Payments Center boundary contract.
 *
 * Types only: this is not a provider SDK, payment implementation, or proof that
 * a Payments Center endpoint currently exists. POS must call an authenticated
 * server-side adapter that implements the approved Payments Center contract.
 * Never put PAN, CVV, PIN, track data, or other cardholder authentication data here.
 */

export type IsoCurrency = string & { readonly __brand: "IsoCurrency" };
export type MinorAmount = number & { readonly __brand: "MinorAmount" };
export type IdempotencyKey = string & { readonly __brand: "IdempotencyKey" };

export type TenderMethod =
  | "card_present"
  | "card_not_present"
  | "cash"
  | "gift_card"
  | "financing"
  | "store_credit"
  | "other_approved";

export type TenderOperation = "authorize" | "capture" | "sale" | "void" | "refund";
export type TenderStatus =
  | "created"
  | "requires_customer_action"
  | "pending"
  | "authorized"
  | "partially_captured"
  | "captured"
  | "declined"
  | "cancelled"
  | "voided"
  | "partially_refunded"
  | "refunded"
  | "unknown_reconciliation";

export type ReconciliationStatus =
  | "not_required"
  | "pending"
  | "matched"
  | "mismatch"
  | "manual_review";

export interface Money {
  /** Integer minor units only; never floating-point currency values. */
  amount: MinorAmount;
  currency: IsoCurrency;
}

export interface TenderAllocationRequest {
  transactionId: string;
  orderId: string;
  storeId: string;
  registerSessionId: string;
  /** Derived by the trusted POS server, never accepted from browser as authority. */
  actorPersonId: string;
  method: TenderMethod;
  operation: TenderOperation;
  amount: Money;
  idempotencyKey: IdempotencyKey;
  /** Stable, non-sensitive reference to the tax/pricing calculation snapshot. */
  calculationReference: string;
  /** Optional provider token/reference only; never raw card data. */
  paymentMethodReference?: string;
  /** Required for cash, gift card and financing according to their approved policies. */
  policyReference?: string;
  metadata?: Record<string, string>;
}

export interface TenderAllocation {
  allocationId: string;
  transactionId: string;
  orderId: string;
  method: TenderMethod;
  operation: TenderOperation;
  requestedAmount: Money;
  authorizedAmount?: Money;
  capturedAmount?: Money;
  refundedAmount?: Money;
  status: TenderStatus;
  provider: string;
  providerAccountReference: string;
  providerPaymentReference?: string;
  providerOperationReference?: string;
  idempotencyKey: IdempotencyKey;
  createdAt: string;
  updatedAt: string;
  reconciliationStatus: ReconciliationStatus;
  /** Safe, allowlisted display value, e.g. "Visa •••• 4242"; no PAN. */
  displayReference?: string;
  failure?: TenderFailure;
}

export interface TenderFailure {
  code: string;
  category:
    | "declined"
    | "validation"
    | "authorization"
    | "provider_unavailable"
    | "timeout"
    | "conflict"
    | "unknown";
  retryable: boolean;
  /** Safe customer/employee message. Never include provider secrets or card data. */
  message: string;
  /** True means POS must reconcile before any retry. */
  requiresReconciliation: boolean;
}

export interface TenderCommandResult {
  allocation: TenderAllocation;
  /** True only when Payments Center has confirmed the requested state transition. */
  confirmed: boolean;
  /** True if the result is indeterminate; callers must not retry blindly. */
  outcomeUnknown: boolean;
}

export interface RefundRequest {
  transactionId: string;
  originalAllocationId: string;
  amount: Money;
  reasonCode: string;
  reasonText: string;
  actorPersonId: string;
  approvalReference?: string;
  idempotencyKey: IdempotencyKey;
}

export interface ReconciliationQuery {
  transactionId: string;
  allocationId?: string;
  providerReference?: string;
}

export interface ReconciliationResult {
  status: ReconciliationStatus;
  allocations: TenderAllocation[];
  checkedAt: string;
  exceptionReference?: string;
}

export interface VerifiedPaymentEvent {
  /** Internal deduplication key created after signature verification. */
  eventId: string;
  provider: string;
  providerAccountReference: string;
  eventType: string;
  providerObjectReference: string;
  transactionId: string;
  allocationId: string;
  occurredAt: string;
  receivedAt: string;
  /** Digest/reference only; do not persist raw sensitive provider payload. */
  payloadDigest: string;
}

export interface PaymentsCenterAdapter {
  createTender(request: TenderAllocationRequest): Promise<TenderCommandResult>;
  captureTender(input: {
    transactionId: string;
    allocationId: string;
    amount: Money;
    actorPersonId: string;
    idempotencyKey: IdempotencyKey;
  }): Promise<TenderCommandResult>;
  voidTender(input: {
    transactionId: string;
    allocationId: string;
    actorPersonId: string;
    reasonCode: string;
    idempotencyKey: IdempotencyKey;
  }): Promise<TenderCommandResult>;
  refundTender(request: RefundRequest): Promise<TenderCommandResult>;
  reconcile(query: ReconciliationQuery): Promise<ReconciliationResult>;
}

/**
 * Invariants enforced by the consuming server implementation:
 * - derive actorPersonId from authenticated server context, not request JSON;
 * - bind idempotency keys to transaction + operation + amount + currency;
 * - never retry outcomeUnknown until reconcile() has resolved provider state;
 * - do not mark a sale fully paid from a client response or unverified event;
 * - do not treat authorization as capture or refund request as refund completion;
 * - cash acceptance requires a separately approved register/cash policy;
 * - every amount uses integer minor units and one transaction currency;
 * - webhook signature verification occurs before creating VerifiedPaymentEvent;
 * - never include raw provider payloads, cardholder data, secrets or PAN fragments
 *   beyond an allowlisted masked display value in logs or persisted metadata.
 */
