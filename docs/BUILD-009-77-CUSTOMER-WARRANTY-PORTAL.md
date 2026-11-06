# Build 009.77 — Customer Warranty Claims Portal

## Delivered
Adds the customer-facing warranty center at /account/warranty, linked to the existing MME account route. The page explains the claim lifecycle, privacy expectations and account-first access pattern, with responsive presentation and explicit empty-state messaging.

## Account and data boundary
The current repository account page is a placeholder and no authenticated customer session helper or account claims API was found in the inspected route paths. Therefore this release does not expose claim data, accept claim submissions, request serial/IMEI values, accept evidence uploads or imply a customer is signed in. The empty state explicitly states that live account lookup is not enabled.

## Required next integration
Implement and verify the shared customer authentication/session layer first. Derive customer identity server-side, then query claim records only for that identity. Add ownership checks and RLS tests before exposing case status. Uploads must use private storage, signed short-lived upload/download URLs, strict MIME/size limits, malware scanning, content hashing and quarantine. Serial and IMEI values must be masked in customer and staff displays unless the workflow explicitly requires full values.

## Planned customer workflows
- Purchase-linked warranty coverage list.
- Claim intake with issue category and purchase selection.
- Secure receipt/photo/video evidence uploads.
- Serial/IMEI verification with masked display.
- Eligibility and missing-evidence status.
- Claim timeline, provider updates and resolution details.
- Repair appointment and shipment tracking.
- Secure support messaging and notification preferences.

## Validation
Run npm run lint and npm run test:build009:warranty-claims-portal. Before live rollout add authenticated integration tests for cross-customer isolation, session expiry, CSRF protection, upload quarantine, signed URL expiry, serial/IMEI masking and audit history.

## Rollout boundary
Customer portal presentation foundation only. No authenticated customer account, live claims API, claim submission, evidence upload, identity verification, provider integration, appointment booking, messaging or production deployment is claimed.
