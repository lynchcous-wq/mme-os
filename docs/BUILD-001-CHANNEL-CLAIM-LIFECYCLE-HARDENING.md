# Build 001 — Channel Claim Lifecycle Hardening

**Status:** Additive corrective migration committed; not applied.

Fixes two edge cases in cross-channel inventory claims. First, serialized-device uniqueness now applies only while a claim line actively owns the unit. Release, expiry and conversion deactivate claim lines while retaining history, allowing a legitimately released device to be reserved again. Second, conversion retries calculate and compare the original request fingerprint before returning an already converted order. Reusing the same idempotency key with different customer, fulfillment or amount inputs is rejected.

The correction preserves service-role-only access and existing order/payment flows.