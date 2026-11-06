import test from 'node:test'; import assert from 'node:assert/strict'; import {readFile} from 'node:fs/promises';
const sql=await readFile(new URL('../supabase/migrations/20261105001600_build009_warranty_retention_alerts.sql',import.meta.url),'utf8');
test('alerts model severity, lifecycle and operational categories',()=>{for(const v of ['upcoming_expiration','overdue_evidence','approval_pending','deletion_failed','legal_hold','exception_expiring','worker_stalled','critical','acknowledged','resolved'])assert.ok(sql.includes("'"+v+"'"));});
test('notification outbox supports retry, leases and idempotency',()=>{assert.match(sql,/status text not null default 'queued'/);assert.match(sql,/lease_token uuid/);assert.match(sql,/idempotency_key text not null unique/);assert.match(sql,/max_attempts integer/);});
test('escalation rules support manager and executive targets',()=>{for(const role of ['warranty_specialist','manager','privacy_officer','ceo'])assert.ok(sql.includes("'"+role+"'"));});
test('alert events are append-only',()=>{assert.match(sql,/revoke update,delete,truncate on public\.mme_warranty_retention_alert_events/);});
test('all alert tables enable RLS and deny browser roles',()=>{assert.equal((sql.match(/enable row level security/g)||[]).length,4);assert.match(sql,/from public,anon,authenticated/);});
test('acknowledgement RPC records an auditable event',()=>{assert.match(sql,/mme_warranty_retention_acknowledge_alert/);assert.match(sql,/'acknowledged',p_actor,'recorded','staff_acknowledgement'/);});
test('migration does not pretend to send notifications or schedule scans',()=>{assert.doesNotMatch(sql,/cron\.schedule|net\.http_post|send_email|twilio/i);});
