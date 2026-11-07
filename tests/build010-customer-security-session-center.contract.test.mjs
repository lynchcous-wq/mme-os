import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=p=>readFile(new URL("../"+p,import.meta.url),"utf8");
const [sql,api,signIn,page]=await Promise.all([
 read("supabase/migrations/20261106006100_build010_customer_security_session_center.sql"),
 read("app/api/auth/customer/security/sessions/route.ts"),
 read("app/api/auth/sign-in/route.ts"),
 read("app/account/security/page.tsx")
]);
test("security event history is append-only and owner-readable",()=>{assert.match(sql,/enable row level security/i);assert.match(sql,/auth_user_id=auth\.uid\(\)/);assert.match(sql,/before update or delete/i);assert.match(sql,/revoke all.*authenticated/i);});
test("session center requires authentication and supports global revocation",()=>{assert.match(api,/requireBrowserUser/);assert.match(api,/hasSameOrigin/);assert.match(api,/logout\?scope=global/);assert.match(api,/clearSessionCookies/);});
test("session history is queried only for the authenticated subject",()=>{assert.match(api,/auth_user_id=eq\."\+encodeURIComponent\(session\.user\.id\)/);assert.match(api,/limit=25/);});
test("shared customer and employee sign-in records a neutral MME portal event",()=>{assert.match(signIn,/event_source:"mme_portal"/);assert.match(sql,/'mme_portal'/);assert.match(signIn,/catch\(\)=>undefined/);});
test("UI explains session inventory limitation and global sign-out",()=>{assert.match(page,/does not expose a reliable list of every device session/);assert.match(page,/Sign out all devices/);assert.match(page,/Recent security activity/);});
