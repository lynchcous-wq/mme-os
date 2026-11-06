import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const root=new URL("../",import.meta.url);
const read=p=>readFile(new URL(p,root),"utf8");
const schema=await read("supabase/migrations/20261106002170_build010_security_incident_response_automation.sql");
const workerSql=await read("supabase/migrations/20261106002180_build010_security_incident_sla_escalation_worker.sql");
const api=await read("app/api/warranty/security-intelligence/incident-response/route.ts");
const worker=await read("app/api/internal/security/incident-sla-escalation/route.ts");
const page=await read("app/warranty/security-intelligence/incident-response/page.tsx");
test("incident cases link to security alerts and enforce severity SLAs",()=>{
 assert.match(schema,/references public\.mme_security_integration_alerts/);
 assert.match(schema,/critical' then interval '15 minutes'/);
 assert.match(schema,/warning' then interval '1 hour'/);
 assert.match(schema,/else interval '4 hours'/);
});
test("response actions require authorized roles and auditable rationale",()=>{
 assert.match(schema,/incident_response_forbidden/);
 assert.match(schema,/length\(trim\(p_rationale\)\),0\)<10/);
 assert.match(schema,/mme_security_incident_response_events/);
 assert.match(schema,/for update/);
});
test("recovery evidence and independent closure approval are mandatory",()=>{
 assert.match(schema,/recovery_verification_required/);
 assert.match(schema,/separation_of_duties_required/);
 assert.match(schema,/closure_approved_by/);
 assert.match(schema,/check\(status<>'closed' or/);
});
test("API validates session and action payload before privileged RPC",()=>{
 assert.match(api,/auth\/v1\/user/);
 assert.match(api,/SUPABASE_SERVICE_ROLE_KEY/);
 assert.match(api,/invalid_action_request/);
 assert.match(api,/mme_security_incident_response_action/);
});
test("overdue SLA worker is secret-protected and escalation is bounded",()=>{
 assert.match(worker,/MME_SECURITY_INCIDENT_WORKER_SECRET/);
 assert.match(worker,/worker_unauthorized/);
 assert.match(workerSql,/for update skip locked/);
 assert.match(workerSql,/escalation_level<5/);
 assert.match(workerSql,/sla_overdue/);
});
test("workspace exposes case queue, ownership, escalation, recovery and audit",()=>{
 assert.match(page,/Incident queue/);
 assert.match(page,/Assign owner/);
 assert.match(page,/Escalate incident/);
 assert.match(page,/Verify recovery/);
 assert.match(page,/Approve closure/);
 assert.match(page,/Incident activity and audit history/);
});
