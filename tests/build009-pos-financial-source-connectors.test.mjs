import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const migration=await readFile(new URL("../supabase/migrations/20261105001140_build009_pos_financial_source_connectors.sql",import.meta.url),"utf8");
const api=await readFile(new URL("../app/api/pos/financial-connectors/route.ts",import.meta.url),"utf8");
const page=await readFile(new URL("../app/internal/financial-connectors/page.tsx",import.meta.url),"utf8");
const css=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");

test("connector migration creates store-scoped connector, batch, row, quarantine and cursor registries",()=>{
 for(const name of ["mme_pos_financial_connectors","mme_pos_financial_import_batches","mme_pos_financial_import_rows","mme_pos_financial_import_quarantine","mme_pos_financial_import_cursors","mme_pos_financial_connector_events"]) assert.ok(migration.includes(name),name);
});
test("all connector tables enforce RLS and deny direct public and authenticated access",()=>{
 assert.equal((migration.match(/enable row level security/g)||[]).length,6);
 assert.match(migration,/from public,anon,authenticated/);
});
test("connector and import functions require active employee permissions",()=>{
 assert.match(migration,/"pos\.finance\.connector\.view"/);
 assert.match(migration,/"pos\.finance\.connector\.manage"/);
 assert.match(migration,/"pos\.finance\.report\.import"/);
 assert.match(migration,/mme_pos_authorize_hardware_action/);
});
test("connector credentials are external references and secret material is rejected",()=>{
 assert.match(migration,/credential_reference/);
 assert.match(migration,/sk_live_|sk_test_|secret=|password=|bearer /);
 assert.match(migration,/credentials must remain in an external secret vault/);
});
test("batch staging is idempotent and limits each batch to 250 normalized rows",()=>{
 assert.match(migration,/unique\(connector_id,idempotency_key\)/);
 assert.match(migration,/jsonb_array_length\(p_records\)>250/);
 assert.match(migration,/source_line_reference/);
});
test("raw cardholder and customer personal data keys are rejected",()=>{
 assert.match(migration,/card_number\|pan\|cvv\|cvc\|pin\|track_data/);
 assert.match(migration,/access_token\|refresh_token\|email\|phone\|address/);
});
test("per-row import errors are quarantined without discarding other valid rows",()=>{
 assert.match(migration,/exception when others then/);
 assert.match(migration,/mme_pos_financial_import_quarantine/);
 assert.match(migration,/completed_with_quarantine/);
});
test("source cursor may advance only after a terminal completed batch",()=>{
 assert.match(migration,/status not in \('completed','completed_with_quarantine'\)/);
 assert.match(migration,/mme_pos_advance_financial_import_cursor/);
});
test("connector lifecycle activation requires a credential reference and records audit events",()=>{
 assert.match(migration,/mme_pos_set_financial_connector_status/);
 assert.match(migration,/credential_reference is null/);
 assert.match(migration,/connector_activated/);
});
test("API authenticates employee sessions and applies per-store permission checks",()=>{
 assert.match(api,/authenticatePosRequest\(request\)/);
 assert.match(api,/pos\.finance\.connector\.view/);
 assert.match(api,/pos\.finance\.connector\.manage/);
 assert.match(api,/pos\.finance\.report\.import/);
 assert.match(api,/Cache-Control/);
});
test("API exposes connector registration, status, staging and batch processing",()=>{
 for(const action of ["register_connector","set_connector_status","stage_batch","process_batch"])assert.ok(api.includes(action),action);
});
test("connector workspace surfaces sources, batches, quarantine and controlled operations",()=>{
 for(const phrase of ["Register a connector","Stage a financial batch","Connected sources","Recent batches","Open quarantine","Activate","Pause","Process"])assert.ok(page.includes(phrase),phrase);
});
test("workspace does not persist bearer tokens and labels live provider adapters as pending",()=>{
 assert.match(page,/type="password"/);
 assert.doesNotMatch(page,/localStorage|sessionStorage|document\.cookie/);
 assert.match(page,/does not yet include live Stripe webhooks\/API polling/);
});
test("connector workspace is responsive and exposes accessible errors",()=>{
 assert.match(page,/role="alert"/);
 assert.match(page,/role="status"/);
 assert.match(css,/finance-connector-card/);
 assert.match(css,/@media\(max-width:700px\)/);
});
