# Build 001 — Shipping, Local Delivery & Customer Pickup Fulfillment

**Status:** Proposed additive migration; not applied.

Creates one fulfillment record per paid order and retains the order's original fulfillment method. Shipping records hold carrier, service level, tracking number/URL, label reference, package count and address snapshot. Pickup records require an active store location and retain ready/completed timestamps.

Status transitions are controlled: queued → picking → packed → shipped or ready_for_pickup → delivered or picked_up. Invalid method transitions are rejected. Completion requires a SHA-256 proof reference; store only a digest/reference, never raw identity documents or pickup secrets.

Carrier events are idempotent by provider/event ID and retain payload digest, timestamp, location and notes. The trusted carrier adapter must verify webhook signatures and account/environment before calling the RPC. This migration does not buy postage, generate carrier labels, send customer notifications, or perform pickup identity verification itself; those belong in trusted service integrations.

All records and RPCs are service-role only. Backend authorization must verify employee identity, role, location scope and permissions. Audit attribution UUIDs are not authentication. Fulfillment creation is restricted to paid or partially-refunded orders.

Verification: run disposable-database integration tests for unpaid-order rejection, pickup without active location, missing shipping address, invalid status transitions, method/status mismatch, missing tracking on shipment, missing completion proof, duplicate carrier events and cross-order data isolation.