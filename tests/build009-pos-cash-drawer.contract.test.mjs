import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105000960_build009_pos_cash_drawer_accountability.sql", import.meta.url), "utf8");
const linkage = await readFile(new URL("../supabase/migrations/20261105000961_build009_pos_cash_tender_linkage.sql", import.meta.url), "utf8");

test("Cash drawer sessions enforce one open register and one associate till", () => {
  assert.ok(sql.includes("mme_pos_one_open_drawer_per_register"));
  assert.ok(sql.includes("mme_pos_one_open_drawer_per_associate"));
  assert.ok(sql.includes("assigned_person_id"));
  assert.ok(sql.includes("opening_float_minor"));
});

test("Cash drawer actions require active person-keyed, location-scoped permissions", () => {
  assert.ok(sql.includes("mme_pos_authorize_drawer_action"));
  assert.ok(sql.includes("lifecycle_status"));
  assert.ok(sql.includes("employee_access_frozen"));
  assert.ok(sql.includes("g.scope->>'location_id'=p_location_id::text"));
  for (const permission of ["pos.drawer.open","pos.drawer.close","pos.drawer.cash_in","pos.drawer.cash_out","pos.drawer.adjust.request","pos.drawer.adjust.approve"]) assert.ok(sql.includes(permission));
});

test("Cash-in and cash-out entries are reason-coded, idempotent and session-bound", () => {
  assert.ok(sql.includes("mme_pos_record_drawer_cash_movement"));
  assert.ok(sql.includes("unique(drawer_session_id,idempotency_key)"));
  assert.ok(sql.includes("Only assigned associate can move till cash"));
  assert.ok(sql.includes("expected_cash_minor=expected_cash_minor+case"));
});

test("Cash adjustments require a second person and produce an auditable ledger movement", () => {
  assert.ok(sql.includes("mme_pos_request_cash_adjustment"));
  assert.ok(sql.includes("mme_pos_decide_cash_adjustment"));
  assert.ok(sql.includes("Requester cannot approve own cash adjustment"));
  assert.ok(sql.includes("'adjustment:'||v_request.id::text"));
});

test("Closeout computes over-short variance and blocks unresolved adjustment requests", () => {
  assert.ok(sql.includes("v_variance:=p_counted_cash_minor-v_session.expected_cash_minor"));
  assert.ok(sql.includes("status='review_required'"));
  assert.ok(sql.includes("Pending cash adjustment decisions must be resolved before closeout"));
});

test("Cash sales and refunds are tied to completed cash ledger outcomes exactly once", () => {
  assert.ok(linkage.includes("mme_pos_record_drawer_cash_sale"));
  assert.ok(linkage.includes("v_attempt.method<>'cash' or v_attempt.status<>'captured'"));
  assert.ok(linkage.includes("mme_pos_record_drawer_cash_refund"));
  assert.ok(linkage.includes("v_request.status<>'completed'"));
  assert.ok(linkage.includes("mme_pos_drawer_tender_sale_once"));
  assert.ok(linkage.includes("mme_pos_drawer_refund_once"));
});

test("Cash drawer data and RPCs are not directly exposed to authenticated clients", () => {
  for (const table of ["mme_pos_cash_drawer_sessions","mme_pos_cash_drawer_movements","mme_pos_cash_adjustment_requests"]) {
    assert.ok(sql.includes("alter table public." + table + " enable row level security"));
    assert.ok(sql.includes("public." + table + " to service_role"));
  }
  for (const fn of ["mme_pos_open_cash_drawer","mme_pos_record_drawer_cash_movement","mme_pos_request_cash_adjustment","mme_pos_decide_cash_adjustment","mme_pos_close_cash_drawer"]) {
    assert.ok(sql.includes("revoke all on function public." + fn));
    assert.ok(sql.includes("grant execute on function public." + fn));
  }
  for (const fn of ["mme_pos_record_drawer_cash_sale","mme_pos_record_drawer_cash_refund"]) {
    assert.ok(linkage.includes("revoke all on function public." + fn));
    assert.ok(linkage.includes("grant execute on function public." + fn));
  }
});
