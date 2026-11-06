# Build 001 — Receiving Reconciliation Controls

**Status:** Additive migration committed; not applied.

Adds a PO-line reconciliation view for each linked receiving session. It shows ordered and previously received quantity, matched scan quantity, remaining quantity if posted, line-level scan exceptions, session-wide unmatched/rejected/duplicate counts, and a reconciliation status (not scanned, partial, reconciled, overage or exceptions open).

Hardens session completion: unmatched, rejected and duplicate scans block posting. Matched products must belong to the linked purchase order at the receiving location, except individually registered serialized units already associated with the scanned product and location. Aggregate quantities still pass through the existing PO receiving function, which enforces remaining ordered quantities and writes inventory movements atomically.

This is an additive control layer over the existing scanner, inspection and receiving workflows. It does not silently discard exceptions or automatically write off damaged goods. The trusted application server must authenticate the actor and independently verify receiving approval permissions before invoking the service-role function.