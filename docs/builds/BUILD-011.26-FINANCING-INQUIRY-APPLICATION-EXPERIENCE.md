# Build 011.26 — Financing Inquiry & Application Experience

## Objective
Create a safe customer-facing financing inquiry workflow without misrepresenting an inquiry as a credit application, approval, prequalification, or credit decision.

## Delivered
- `/financing`: responsive customer inquiry page.
- `POST /api/financing/inquiries`: same-origin JSON endpoint with server-side validation, durable rate limiting, honeypot, explicit contact consent, and no-store responses.
- `supabase/migrations/20261117000100_build01126_financing_inquiries.sql`: private inquiry table with constrained fields, RLS enabled, and all direct browser-role table privileges revoked.
- Provider-neutral workflow: customer may express interest and later be referred to an approved provider's official secure application.

## Data minimization
Collected fields: full name, email, phone, product category, estimated purchase range, preferred contact method, and explicit consent to contact.
Never collect through this form: SSN, DOB, bank account, income, credit score, driver's license, identity document, or credit-card data.

## Security controls
- Same-origin validation.
- Durable IP rate limiting: maximum 5 requests per hour; fail closed when rate-limit configuration is unavailable.
- Server-side allow-list validation for category, budget and contact method.
- Honeypot field for basic automated submission filtering.
- Supabase service-role key used only server-side.
- RLS enabled; direct privileges revoked from public, anon and authenticated roles.
- No sensitive values in application response messages or intentional logs.
- Consent is mandatory and stored with the inquiry.

## Environment requirements
- Existing `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` configured privately for preview and production as appropriate.
- Existing private Upstash rate-limit variables configured for preview and production separately.
- Apply the new Supabase migration to the intended environment before accepting submissions.
- Do not expose service-role or Redis tokens through `NEXT_PUBLIC_*`.

## Acceptance tests / release gates
- [x] Page and API route added.
- [x] Required consent and input validation.
- [x] No credit-sensitive data fields.
- [x] Table uses RLS and denies direct browser-role access.
- [x] API rate-limits and fails closed.
- [ ] Apply migration to preview Supabase and verify schema.
- [ ] Configure and verify private preview environment variables.
- [ ] Test success, invalid payload, origin rejection, rate limit, honeypot, storage outage and duplicate submissions.
- [ ] Confirm inquiry is visible only to authorized MME staff via a separately authorized workflow.
- [ ] Configure lender/provider directory and official application URLs only after merchant agreements and provider approval are verified.
- [ ] Verify privacy notice, retention schedule, contact consent wording and applicable legal review.
- [ ] Run Vercel preview build and mobile/accessibility checks.
- [ ] Explicitly approve production release.

## Release decision
**PREVIEW ONLY — NOT A CREDIT APPLICATION.** No credit bureau pull, lender submission, financing decision, loan offer, approval, or payment is performed. No lender partner is represented as integrated. Production deployment and production database migration are not performed by this build.
