# Build 001 — Cart Recovery Token Hardening

**Status:** Additive hardening migration; not applied.

Recovery challenges now have a configurable maximum attempt count (default five). Every attempted verification increments the counter, including incorrect tokens; exhausted challenges cannot restore a cart. Issuing a replacement resets the counter and replaces the stored token digest. The token digest is used directly in the event idempotency key, avoiding an unnecessary dependency on the pgcrypto digest function.

The trusted service must generate high-entropy random tokens, hash them with SHA-256, send the raw token only through a verified customer channel, rate-limit requests, and never log raw tokens. The database RPC remains service-role only. Checkout must revalidate current product activity, price, location and available stock; a recovered cart is not an inventory reservation or price guarantee.