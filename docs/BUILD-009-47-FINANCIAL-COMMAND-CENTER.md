# Build 009.47 — Enterprise Financial Intelligence Command Center

## Purpose
Create immutable executive briefings and store-level comparisons from Build 009.46 intelligence snapshots, Build 009.45 exception cases and imported settlement batches.

## Executive view
- Latest available risk snapshot per store and ISO currency.
- Highest observed risk band and maximum store score.
- Store-level unresolved exposure, overdue exceptions and delayed settlement counts.
- Source run identifiers for traceability.
- Generated executive narrative that explicitly labels the briefing advisory.

## Multi-store access
The briefing RPC accepts 1–100 unique location identifiers and checks the caller's settlement-exception-management permission for every requested location before reading data. It produces separate briefings per currency; amounts from different currencies are never combined.

## Data integrity
Briefings and store comparison rows are append-only snapshots. They do not rewrite financial facts, close periods, confirm bank deposits, initiate refunds, create payouts or transfer funds. Historical briefings remain available for audit.

## RPC
`mme_pos_build_financial_command_center_briefing(location_ids, actor_person_id, as_of_date)`

## Dashboard view
`mme_pos_financial_command_center_store_comparison` provides store-granular comparisons with source intelligence run references.

## Validation
Run `npm run lint`, `npm run test:build009:financial-command-center`, and the financial intelligence, settlement exception, settlement integrity and reporting suites. Replay ordered migrations and test multi-store permission boundaries, duplicate location rejection, currency isolation, no-snapshot stores, source traceability, append-only behavior and concurrent briefing generation.

## Rollout boundary
Implementation branch only. The briefing is generated from existing snapshots; it is not a real-time Stripe or bank feed. No production deployment, live alert delivery, or automated financial action is claimed.
