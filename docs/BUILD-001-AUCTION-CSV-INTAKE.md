# Build 001 — Auction CSV & Document Intelligence Intake

**Status:** Proposed additive migration; not applied.

## CEO intake
The trusted intake worker accepts a CEO-submitted CSV and supporting documents, stores private storage paths and file hash, and stages normalized source rows. Batch financial inputs include acquisition, freight, auction fees, handling, other costs and allocation method.

## Row-level records
Each row preserves the source row reference/number, original item title and description, quantity, inventory type, acquisition line cost, optional condition, product/location match and confidence. Retail research evidence stores the estimate, source URL/name, checked timestamp and structured evidence. Research must be performed by an approved external agent and independently reviewable; this database does not scrape websites.

## Review and CEO decision
Unmatched or uncertain rows remain visible for review. A reviewer maps each line to an active MME product and store location. The approval RPC blocks approval until every row is matched, the total line acquisition cost reconciles exactly to the CEO's pallet purchase price, and aggregate/serialized product types agree. Trusted server authorization must verify that the approver has CEO authority; service_role alone is not an end-user permission check.

## Audit and security
Source documents remain private; only storage paths are stored. SHA-256 records source-file identity. Batch and line review decisions create audit events. Tables and RPCs are service-role only; no browser service key.

## Integration boundary
This migration stages and approves the intake but does not itself parse arbitrary CSV/XLSX/PDF files, run web retail research, or receive stock. A trusted worker must parse files, normalize rows and attach research evidence. A later receiving adapter must route approved aggregate lines through the landed-cost receipt RPC and serialized lines through per-unit serialized intake/cost workflows. No stock is posted merely because a batch was approved.