# Build 001 — Supplier Performance & Procurement Intelligence

**Status:** Additive migration committed; not applied.

Adds two service-role-only reporting views:
- Supplier procurement intelligence: delivery counts, completed deliveries, delays/disputes, expected/received/damaged units, completion and non-damaged rates, schedule variance, quote coverage, invoice match/variance/pending counts, variance value, purchase-order counts and ordered value.
- Supplier quote cost trend: per supplier and product, quote sample count, low/high/average quote, earliest/latest quote and first-to-latest price change.

Metrics are independently aggregated before joining to prevent invoice, delivery, quote and PO row multiplication. Rates with no valid denominator remain null. Invoice control status flags pending review and variance/dispute attention. Quote trends describe recorded historical offers, not guaranteed current supplier prices.

No composite supplier grade is manufactured, and this reporting does not choose vendors or issue orders. CEO and authorized purchasing roles retain supplier selection and purchase approval. Access remains restricted to the trusted service layer.