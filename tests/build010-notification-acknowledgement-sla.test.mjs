import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const root=new URL("../",import.meta.url),read=p=>readFile(new URL(p,root),"utf8");
const sql=await read("supabase/migrations/20261106002200_build010_security_notification_acknowledgement_sla.sql");
const api=await read("app/api/warranty/security-intelligence/notification-routing/route.ts");
const worker=await read("app/api/internal/security/notification-ack-sla/route.ts");
const page=await read("app/warranty/security-intelligence/notification-routing/page.tsx");
test("notification acknowledgement deadlines vary by incident severity",()=>{
 assert.match(sql,/critical' then interval '5 minutes'/);
 assert.match(sql,/warning' then interval '15 minutes'/);
 assert.match(sql,/else interval '60 minutes'/);
 assert.match(sql,/acknowledgement_due_at/);
});
test("acknowledgement is authenticated, idempotent and role bounded",()=>{
 assert.match(sql,/mme_security_notification_acknowledge/);
 assert.match(sql,/acknowledged/);
 assert.match(sql,/notification_ack_forbidden/);
 assert.match(sql,/notification_recipient_role_required/);
 assert.match(api,/auth\/v1\/user/);
 assert.match(api,/mme_security_notification_acknowledge/);
});
test("overdue acknowledgements escalate in bounded batches with row locking",()=>{
 assert.match(sql,/for update skip locked/);
 assert.match(sql,/acknowledgement_escalation_level<5/);
 assert.match(sql,/acknowledgement_escalated_at is null or q\\.acknowledgement_escalated_at<now\\(\\)-interval '5 minutes'/);
 assert.match(sql,/notification_ack_overdue/);
 assert.match(worker,/MME_SECURITY_NOTIFICATION_ACK_WORKER_SECRET/);
 assert.match(worker,/worker_unauthorized/);
});
test("dashboard shows acknowledgement SLA metrics and action",()=>{
 assert.match(page,/Acknowledgement SLA/);
 assert.match(page,/Overdue:/);
 assert.match(page,/Acknowledge/);
 assert.match(page,/acknowledgement_due_at/);
});
