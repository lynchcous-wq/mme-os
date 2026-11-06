import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration=await readFile(new URL("../supabase/migrations/20261106005000_build010_customer_identity_review_dashboard.sql",import.meta.url),"utf8");
const helper=await readFile(new URL("../lib/auth/customer-identity-review.ts",import.meta.url),"utf8");
const route=await readFile(new URL("../app/api/employee/customer-identity-requests/route.ts",import.meta.url),"utf8");
const page=await readFile(new URL("../app/employee/customer-identity-review/page.tsx",import.meta.url),"utf8");
const portal=await readFile(new URL("../supabase/migrations/20261105001320_build009_customer_order_self_service_portal.sql",import.meta.url),"utf8");

test("review authorization requires active employment, unfrozen access, and CEO or explicit permission",()=>{
 assert.match(migration,/employee_access_frozen is distinct from false/);
 assert.match(migration,/employment_status.*'active'/s);
 assert.match(migration,/customer\.identity\.review/);
 assert.match(migration,/ceo_user_id/);
});
test("approval validates active person and verified Auth email, blocks conflicting mappings, and provisions portal link",()=>{
 assert.match(migration,/lifecycle_status='active'/);
 assert.match(migration,/email_confirmed_at/);
 assert.match(migration,/v_existing_person<>p_person_id/);
 assert.match(migration,/mme_customer_portal_provision_account_link/);
 assert.match(migration,/mme_login_identities/);
});
test("approval and review decisions use one transaction and service-role-only RPC",()=>{
 assert.match(migration,/revoke all on function public\.mme_customer_identity_review_decide/);
 assert.match(migration,/grant execute on function public\.mme_customer_identity_review_decide.*to service_role/s);
});
test("API derives actor from validated employee session and restricts queue access",()=>{
 assert.match(helper,/requireBrowserUser/);
 assert.match(helper,/mme_employee_authorize_customer_identity_review/);
 assert.match(route,/requireCustomerIdentityReviewer/);
 assert.match(route,/mme_customer_identity_review_decide/);
 assert.match(route,/hasSameOrigin|headers\.get\("origin"\)/);
});
test("dashboard offers review, approval and rejection with active person UUID input",()=>{
 assert.match(page,/Mark reviewing/);
 assert.match(page,/Approve & activate/);
 assert.match(page,/Reject request/);
 assert.match(page,/Verified active MME person ID/);
});
test("customer portal provisioning remains service-role-only",()=>{
 assert.match(portal,/revoke all on function public\.mme_customer_portal_provision_account_link.*authenticated/s);
 assert.match(portal,/grant execute on function public\.mme_customer_portal_provision_account_link.*service_role/s);
});
