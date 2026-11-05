import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105001030_build009_pos_hardware_health_intelligence.sql", import.meta.url), "utf8");

test("device telemetry is bounded, typed, time-windowed and idempotent", () => {
  assert.match(sql, /unique\(device_id,provider_event_id\)/);
  assert.match(sql, /jsonb_object_keys\(p_metrics\).*not between 1 and 12/s);
  assert.match(sql, /p_observed_at<now\(\)-interval '24 hours'/);
  assert.match(sql, /p_observed_at>now\(\)\+interval '60 seconds'/);
  assert.match(sql, /on conflict\(device_id,provider_event_id\) do nothing/);
  assert.match(sql, /Unsupported telemetry metric/);
});

test("health score is evidence-based, explainable and marks missing telemetry as unknown evidence", () => {
  assert.match(sql, /mme_pos_calculate_device_health/);
  assert.match(sql, /factors jsonb not null/);
  assert.match(sql, /No recent optional telemetry/);
  assert.match(sql, /health_band/);
  assert.match(sql, /scoring_version/);
});

test("telemetry thresholds support both higher-is-worse and lower-is-worse metrics", () => {
  assert.match(sql, /threshold_direction text not null check\(threshold_direction in \('higher_is_worse','lower_is_worse'\)\)/);
  assert.match(sql, /threshold_direction='higher_is_worse'/);
  assert.match(sql, /threshold_direction='lower_is_worse'/);
  assert.match(sql, /warning_threshold<critical_threshold/);
  assert.match(sql, /warning_threshold>critical_threshold/);
});

test("health bands and deterministic scoring penalties are bounded", () => {
  for (const band of ["excellent","healthy","attention","degraded","critical","unknown"]) assert.ok(sql.includes("'" + band + "'"));
  assert.match(sql, /v_score:=greatest\(0,least\(100,v_score\)\)/);
  assert.match(sql, /heartbeat_staleness/);
  assert.match(sql, /active_it_incidents/);
});

test("degraded health creates deduplicated alerts and technician-reviewed maintenance tasks", () => {
  assert.match(sql, /mme_pos_device_health_alerts/);
  assert.match(sql, /mme_pos_device_maintenance_tasks/);
  assert.match(sql, /on conflict\(device_id,alert_type\) where status in \('open','acknowledged'\) do nothing/);
  assert.match(sql, /repair or replace only after technician verification/);
});

test("diagnostic results are typed and bounded", () => {
  assert.match(sql, /mme_pos_record_device_diagnostic/);
  assert.match(sql, /p_diagnostic_type not in/);
  assert.match(sql, /p_result not in \('pass','warning','fail','not_supported','unknown'\)/);
  assert.match(sql, /octet_length\(p_details::text\)>4000/);
});

test("health tables have RLS and privileged RPCs are service-role only", () => {
  for (const table of ["mme_pos_device_telemetry","mme_pos_device_health_scores","mme_pos_device_health_alerts","mme_pos_device_diagnostics","mme_pos_device_maintenance_tasks","mme_pos_device_baselines"]) {
    assert.match(sql, new RegExp("alter table public\\." + table + " enable row level security"));
  }
  assert.match(sql, /from public,anon,authenticated/);
  for (const fn of ["mme_pos_ingest_device_telemetry","mme_pos_record_device_diagnostic","mme_pos_calculate_device_health","mme_pos_sweep_device_health"]) {
    assert.ok(sql.includes("revoke all on function public." + fn));
    assert.ok(sql.includes("grant execute on function public." + fn));
  }
});

test("health sweep is bounded and excludes retired hardware", () => {
  assert.match(sql, /p_limit not between 1 and 1000/);
  assert.match(sql, /where status<>'retired'/);
});
