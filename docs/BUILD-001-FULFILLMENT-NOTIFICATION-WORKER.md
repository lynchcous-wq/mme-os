# Build 001 — Fulfillment Notification Worker Reliability

**Status:** Proposed additive migration; not applied.

Adds an atomic notification-worker lease using row locks and SKIP LOCKED, bounded batch size and lease duration, worker ownership checks, provider completion receipts, and exponential retry scheduling. Retryable failures stop after eight attempts and become suppressed; permanent failures are suppressed immediately. Expired worker leases can be reclaimed.

The worker must send only after claiming a lease, honor channel consent/opt-out and contact preferences, redact recipient data from logs, and use provider idempotency where supported. Delivery acceptance is not proof the customer read a message. The worker identity must be authenticated by the trusted backend; the worker ID string is an audit/lease label, not authentication. Provider webhook signature verification remains in the trusted adapter.

Run disposable database tests for concurrent workers, lease expiry/reclaim, wrong worker completion, retry schedule, max attempts, permanent failure suppression, and duplicate provider receipts.