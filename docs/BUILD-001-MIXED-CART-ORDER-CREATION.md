# Build 001 — Mixed-Cart Order Creation

Status: additive database migration and contract tests committed; not deployed or runtime-tested.

The new service-role-only mme_create_mixed_order_and_reserve RPC creates one pending order, one shared inventory reservation, and all order-line snapshots for aggregate and serialized cart entries. Aggregate lines use product_id, location_id, quantity and omit serialized_unit_id. Serialized entries include serialized_unit_id and require quantity=1; the unit must match the product/location and be in_stock. The RPC snapshots database catalog prices, serial/IMEI and condition details, locks records in deterministic order, and reserves both stock types within the same transaction. Any validation or stock failure rolls the entire transaction back.

Use one Stripe PaymentIntent for the authoritative total on the resulting order. The unified payment webhook consumes or releases both reservation types atomically.

This RPC does not yet replace the checkout Edge Function; the next integration step will route the trusted pricing result to this RPC and return one PaymentIntent for the mixed cart.