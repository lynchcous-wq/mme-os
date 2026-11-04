# Build 001 — Integration checkpoint

This checkpoint is a review artifact only. It does not alter production schema or enable payment processing.

## Verified architecture boundary

- The catalog domain is `public.products`; it owns descriptions, specifications, category, catalog state, and employee approval/publication workflow.
- The commerce domain is `public.mme_products`; it owns the authoritative checkout price and inventory-facing product flags.
- The two domains are not currently joined by a foreign key, and their SKUs are independently unique. A matching SKU is not proof of identity.

## Required public-sale invariant

A product may appear as purchasable only when:
1. A catalog record is explicitly linked to its commerce record.
2. The catalog record is published.
3. The commerce record is active.
4. The selected location has available, unreserved stock (or an eligible serialized unit).
5. The server computes price from the commerce record, never from browser input.

Draft, pending approval, changes requested, archived, or unlinked products must fail closed for public listing and checkout.

## Integration order

1. Preserve catalog migrations 00100–00800.
2. Preserve the original order of Build 001 migrations while moving them into a unique version range after 00800.
3. Add an audited catalog-to-commerce mapping migration only after both tables exist.
4. Test the complete migration chain from an empty disposable database.
5. Test the public-sale invariant and rollback/concurrency cases before deploying any migration.

## Release boundary

No production migration, Stripe deployment, or live payment activation is authorized by this document.