import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

const root=new URL("../",import.meta.url);
const read=async(path)=>readFile(new URL(path,root),"utf8");
const monitoringRoute=await read("app/api/warranty/security-intelligence/monitoring/route.ts");
const executiveRoute=await read("app/api/warranty/security-intelligence/executive/route.ts");
const monitoringSql=await read("supabase/migrations/20261106002150_build010_cross_system_security_monitoring_snapshots.sql");
const executiveSql=await read("supabase/migrations/20261106002160_build010_executive_security_command_center.sql");
const monitoringTests=await read("tests/build010-cross-system-security-monitoring.test.mjs");
const executiveTests=await read("tests/build010-executive-security-command-center.test.mjs");
const executivePage=await read("app/warranty/security-intelligence/executive/page.tsx");

test("acceptance matrix covers both monitoring and executive command surfaces",()=>{
 assert.match(monitoringTests,/monitoring endpoint authenticates/);
 assert.match(monitoringTests,/snapshot status escalates/);
 assert.match(executiveTests,/API validates session/);
 assert.match(executiveTests,/executive UI presents posture/);
 assert.match(executivePage,/Executive Security Command Center/);
});

test("unauthenticated and unauthorized requests are rejected before privileged database calls",()=>{
 for(const route of [monitoringRoute,executiveRoute]){
  const authIndex=route.indexOf("/auth/v1/user");
  const serviceIndex=route.indexOf("SUPABASE_SERVICE_ROLE_KEY");
  const rpcIndex=route.indexOf("/rest/v1/");
  assert.notEqual(authIndex,-1);
  assert.notEqual(serviceIndex,-1);
  assert.notEqual(rpcIndex,-1);
  assert.ok(authIndex<rpcIndex,"session validation must precede privileged REST calls");
  assert.match(route,/authentication_required/);
  assert.match(route,/access_denied|security_monitoring_access_denied/);
  assert.match(route,/Cache-Control/);
 }
});

test("executive write path is narrower than read access and validates action rationale",()=>{
 assert.match(executiveRoute,/const READ=new Set/);
 assert.match(executiveRoute,/const WRITE=new Set\(\["ceo","cio","it_admin"\]\)/);
 assert.match(executiveRoute,/if\(!WRITE\.has\(c\.role\)\)/);
 assert.match(executiveRoute,/rationale\.length<10/);
 assert.match(executiveRoute,/rationale\.length>2000/);
 assert.match(executiveSql,/p_actor_role not in \('ceo','cio','it_admin'\)/);
});

test("executive alert actions are transactional and leave before/after audit evidence",()=>{
 assert.match(executiveSql,/for update/);
 assert.match(executiveSql,/before_state,after_state/);
 assert.match(executiveSql,/target_alert_id,rationale,before_state,after_state,request_id/);
 assert.match(executiveSql,/revoke all on public\.mme_security_executive_action_audit from public,anon,authenticated/);
});

test("monitoring status cannot conceal critical alert or dead-letter conditions",()=>{
 assert.match(monitoringSql,/open_critical>0 or dead_count>0/);
 assert.match(monitoringSql,/status='offline'/);
 assert.match(monitoringSql,/then 'critical'/);
 assert.match(monitoringSql,/then 'degraded'/);
 assert.match(monitoringSql,/when source_count=0 then 'unknown'/);
});

test("dashboard communicates telemetry limits and avoids automatic adverse actions",()=>{
 assert.match(executivePage,/No source health records available/);
 assert.match(executivePage,/No integration alerts recorded/);
 assert.match(executivePage,/do not automatically suspend accounts, deny claims or restrict customers/);
});
