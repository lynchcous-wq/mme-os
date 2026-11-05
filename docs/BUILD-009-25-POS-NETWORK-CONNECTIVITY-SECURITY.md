# Build 009.25 — POS Hardware Network Connectivity & Secure Device Communications

Status: implementation committed to a review branch; migration replay, integration tests and network/vendor validation pending.

## Reused foundation
- Build 009.15 hardware registry and IT incident path.
- Build 009.16 trusted device pairing and heartbeat supervision.
- Build 009.20 authenticated hardware command dispatch.
- Build 009.21 acknowledgment and uncertain-outcome reconciliation.
- Build 009.22 network/device health telemetry.
- Build 009.23 fleet identity and location-scoped administration.
- Build 009.24 staged firmware/configuration orchestration.

## Implemented database foundation
- `mme_pos_network_zones`: POS, payment, peripherals, management, guest and infrastructure trust zones.
- `mme_pos_network_devices`: device-to-zone assignment, network identifiers, IP/MAC/VLAN metadata, connection type and security posture.
- `mme_pos_network_connections`: timestamped authenticated/encrypted connection observations and latency/loss metadata.
- `mme_pos_device_certificates`: certificate fingerprints, issuer/subject, validity period, external secret-manager reference, activation and revocation state.
- `mme_pos_network_health`: availability, latency, packet loss, jitter, bandwidth and certificate-expiry observations.
- `mme_pos_network_incidents`: connectivity, encryption, authentication, certificate and segmentation incident workflow.
- `mme_pos_network_failover_events`: failover intent and outcome records.
- `mme_pos_network_security_events`: unauthenticated peer, unencrypted session, certificate mismatch, suspected replay and unexpected peer event history.

## Workflows and controls
1. Map registered devices to a planned or active trust zone and record approved connection metadata.
2. A trusted network agent records timestamped connectivity observations. Stale or future-dated observations are rejected.
3. Unauthenticated or unencrypted sessions are recorded as critical security events/incidents, the device is marked noncompliant and the observation is rejected. The function returns NULL after writing those records so the incident evidence is not rolled back by an exception.
4. Certificate registration stores fingerprint and a secret-manager reference only. Private keys and certificate bytes remain outside the application database.
5. Certificate activation requires an external signature-validation evidence reference, valid time window and authorized certificate administrator. The reference is an audit pointer; cryptographic verification must be performed by the trusted certificate service.
6. Certificate revocation is an authorized operation with a reason. Expiry monitoring can be driven from certificate validity metadata.
7. Health observations create network incidents when health is degraded or critical.
8. Failover events record source/target path, reason, actor and observed outcome. This schema does not reconfigure routers, VLANs, firewalls, Wi-Fi or payment routing.

## Recommended segmentation
- Payment: restricted; isolate payment terminal and processor traffic.
- POS: high trust; register controllers and transaction services.
- Peripherals: dedicated approved-device zone; deny unnecessary lateral access.
- Management: restricted; administrative agents and monitoring only.
- Guest: untrusted; no route into POS, payment or management.
- Infrastructure: tightly controlled store network services.

Actual VLAN, firewall ACL, routing and PCI scope must be reviewed and implemented by qualified network/security personnel and the payment provider.

## Security and payment continuity
- New tables use RLS; direct public/anonymous/authenticated access is revoked. Service role only is granted.
- Existing identity, active employment and CEO employee-access-freeze checks are retained in the extended hardware permission function.
- New permissions cover network view, management, certificate administration and incident management.
- Mutual TLS is represented as an observed property where supported; do not assume every peripheral supports it.
- TLS versions, cipher suites, certificate chain and endpoint identity must be validated by the trusted transport adapter, not inferred from a database boolean.
- Payment terminals must not silently fall back to plaintext or untrusted networks. If secure connectivity is unavailable, payment is unavailable until processor-supported continuity is verified.
- No offline payment is marked completed without processor confirmation. Reconcile uncertain payments before retrying.
- Failover must be explicitly approved and tested; payment routing failover is controlled by the processor/acquirer, not this database feature.

## Validation required
Run:
- `npm run test:build009:network-security`
- `npm run test:build009:firmware-orchestration`
- `npm run test:build009:hardware-fleet-administration`
- `npm run test:build009:hardware-health-intelligence`
- `npm run test:build009:hardware-ack-reconciliation`
- `npm run lint`
- Full ordered Supabase migration replay and PostgreSQL integration tests in an isolated environment.

Integration tests must verify zone assignment scope, stale observation rejection, rejected insecure session evidence persistence, certificate expiry/activation/revocation, unauthorized cross-location changes, health incident generation, and service-role boundaries. Network testing must verify segmentation, firewall rules, TLS/mTLS and payment-provider requirements in a representative store environment.

## Not claimed complete
No migration has been applied to production Supabase. No switch, firewall, VLAN, Wi-Fi, certificate authority, secret manager, device agent or payment processor has been connected or reconfigured. The schema stores trusted observations and administrative intent; it is not proof that the physical network is compliant or secure.
