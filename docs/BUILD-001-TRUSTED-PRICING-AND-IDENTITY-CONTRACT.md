# Build 001 — Trusted Pricing and Customer Identity Contract

**Status:** Contract specification only. No pricing service or customer-to-auth identity mapping is implemented or verified in this repository.

## Purpose

The checkout Edge Function must never accept prices, discounts, tax, fulfillment charges, or customer identity from the browser as authoritative. It authenticates the Supabase user, calls a trusted server-side pricing service, creates one mixed-inventory order using database catalog prices, and creates one PaymentIntent for the resulting order total.

## Trust boundaries

1. The browser submits only requested product identifiers, quantities, optional serialized-unit identifiers, fulfillment choice, and fulfillment details.
2. The checkout Edge Function validates the caller's Supabase access token with `auth.getUser()`. It does not trust a user ID supplied in the request body.
3. The pricing service is a private server-to-server dependency. Its URL and credential are server-side secrets. It must reject unauthenticated callers, validate its own request schema, and never expose its credential to a browser.
4. The pricing service resolves the authenticated Supabase subject to an active MME person/login identity and an active customer relationship. It must not accept an arbitrary `customer_identity_id` from the browser.
5. The service response is bound to the exact authenticated subject supplied by the checkout Edge Function. The Edge Function rejects a missing or mismatched subject binding.
6. The mixed-order database function independently calculates item subtotal from current database catalog prices and inventory records. Client or pricing-service item prices are never accepted as authoritative.
7. Tax, discounts, and fulfillment charges require explicit trusted calculation and validation rules. Until those rules are implemented, the pricing service must fail closed rather than invent or default charges.

## Request contract

Server-to-server POST body:

- `auth_user_id`: Supabase Auth subject obtained from the verified access token.
- `items[]`: `product_id`, `location_id`, `quantity`, and optional `serialized_unit_id`.
- `fulfillment_method`: `pickup` or `shipping`.
- `fulfillment_details`: validated pickup or shipping information, minimized to what is required.

The pricing service must validate UUIDs, quantities, duplicate lines, serialized-unit quantity of exactly one, allowed fulfillment method, customer eligibility, shipping destination/pickup location eligibility, and request size. It must re-resolve the customer identity from `auth_user_id` on every request; never trust a caller-supplied customer identity ID.

## Required response contract

The response must include:

- `auth_user_id`: exact subject from the verified checkout request.
- `customer_identity_id`: opaque active MME customer identity resolved by the service for that subject.
- `customer_relationship_status`: `active`.
- `items[]`: validated inventory identifiers and quantities only; no client-authoritative unit prices.
- `tax_cents`: nonnegative integer calculated by an approved tax engine/rule set.
- `fulfillment_cents`: nonnegative integer calculated from the approved shipping/pickup policy.
- `discount_cents`: nonnegative integer from an approved, eligible discount rule.
- `fulfillment_snapshot`: object containing the validated method and minimal immutable destination/pickup details needed for fulfillment and audit.
- `pricing_version` and `quote_expires_at`: version and short expiry for the quote.

The Edge Function must reject malformed responses, a subject mismatch, inactive customer relationship, invalid identifiers/quantities, expired quotes, unsupported versions, negative or non-integer monetary amounts, and non-object snapshots. It must cap item count and monetary values to database/Stripe safe limits.

## Identity mapping prerequisite

The Build 004 Identity Matrix specification explicitly describes a conceptual identity and customer relationship model and states that no authentication provider, customer identity service, or relationship store is established by the inspected repository. Therefore, no table or RPC name should be guessed for the user-to-customer mapping.

Before enabling checkout, select and verify the actual identity provider and authoritative data store, then implement an additive, uniquely constrained mapping between the provider's immutable subject and the MME person/customer relationship. Define account linking, duplicate prevention, customer eligibility, revocation, and audit semantics. The lookup must be server-side and deny by default. Employment status must remain independent of customer relationship status.

## Failure behavior

- Missing pricing configuration or unavailable pricing service: fail closed with a service-unavailable response; create no order.
- Unknown auth subject, missing mapping, inactive customer relationship, or subject mismatch: deny; create no order or reservation.
- Invalid quote, unsupported pricing version, invalid amounts, or expired quote: reject; create no order or reservation.
- Inventory reservation conflict: database transaction rolls back; no PaymentIntent is created.
- PaymentIntent creation/binding failures: follow the existing reconciliation workflow; do not mark the order paid without verified webhook processing.

## Release gates

- [ ] Identity provider and authoritative subject confirmed.
- [ ] Customer-to-auth mapping implemented with uniqueness, status, and audit controls.
- [ ] Pricing service implemented and authenticated server-to-server.
- [ ] Subject binding and customer relationship status verified by checkout.
- [ ] Tax, fulfillment, discount and quote-expiry rules approved and implemented.
- [ ] Contract and negative tests cover mismatched subject, unknown identity, inactive customer, forged prices, malformed quote, duplicate lines, invalid fulfillment, and expired quote.
- [ ] CI and database migration checks pass in a controlled test environment.
- [ ] Payment tests are separately authorized; they are intentionally excluded from the current work.

**Do not enable or describe online checkout as production-ready until all release gates are evidenced.**
