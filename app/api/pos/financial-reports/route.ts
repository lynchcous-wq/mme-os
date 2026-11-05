import { NextResponse } from "next/server";
import { authenticatePosRequest, isUuid } from "@/lib/pos/authenticated-server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const noStore = { "Cache-Control": "no-store, private" };
const uuid = (value: string | null) => isUuid(value);
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const currencyPattern = /^[A-Z]{3}$/;
const validDate = (value: string) => datePattern.test(value) && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0,10) === value;
const validTimezone = (value: unknown): value is string => {
  if (typeof value !== "string" || value.length > 80) return false;
  try { new Intl.DateTimeFormat("en-US", { timeZone: value }); return true; } catch { return false; }
};

async function authorized(context: { baseUrl: string; serviceKey: string; personId: string }, permission: string, locationId: string) {
  const response = await fetch(`${context.baseUrl}/rest/v1/rpc/mme_pos_authorize_hardware_action`, {
    method: "POST",
    headers: { apikey: context.serviceKey, Authorization: `Bearer ${context.serviceKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_actor_person_id: context.personId, p_permission_key: permission, p_location_id: locationId }),
    cache: "no-store",
  });
  if (!response.ok) return false;
  return (await response.json()) === true;
}

async function readRows(context: { baseUrl: string; serviceKey: string }, path: string) {
  const response = await fetch(`${context.baseUrl}/rest/v1/${path}`, {
    headers: { apikey: context.serviceKey, Authorization: `Bearer ${context.serviceKey}`, Accept: "application/json" },
    cache: "no-store",
  });
  if (!response.ok) throw new Error("Financial reporting data is temporarily unavailable.");
  return response.json() as Promise<Record<string, unknown>[]>;
}

export async function GET(request: Request) {
  const authenticated = await authenticatePosRequest(request);
  if (!authenticated.ok) return authenticated.response;
  const { context } = authenticated;
  const params = new URL(request.url).searchParams;
  const locationId = params.get("location_id");
  const periodStart = params.get("period_start");
  const periodEnd = params.get("period_end");
  const currency = params.get("currency") ?? "USD";
  if (!uuid(locationId) || !periodStart || !periodEnd || !datePattern.test(periodStart) ||
      !validDate(periodStart) || !validDate(periodEnd) || periodEnd < periodStart || !currencyPattern.test(currency)) {
    return NextResponse.json({ error: "Provide a valid store, date range and ISO currency." }, { status: 400, headers: noStore });
  }
  if (!(await authorized(context, "pos.finance.report.view", locationId))) {
    return NextResponse.json({ error: "You do not have permission to view financial reports for this store." }, { status: 403, headers: noStore });
  }
  try {
    const runs = await readRows(context,
      `mme_pos_financial_report_runs?select=id,location_id,period_start,period_end,business_timezone,currency,status,source_fact_count,built_at,source_cutoff_at&location_id=eq.${locationId}&period_start=eq.${periodStart}&period_end=eq.${periodEnd}&currency=eq.${currency}&order=built_at.desc&limit=1`);
    const report = runs[0] ?? null;
    if (!report) return NextResponse.json({ report: null, rows: [], summary: null }, { headers: noStore });
    const reportId = String(report.id);
    const [allRows, summaries] = await Promise.all([
      readRows(context, `mme_pos_financial_report_rows?select=*&report_run_id=eq.${reportId}&order=business_date.asc`),
      readRows(context, `mme_pos_financial_report_summaries?select=*&report_run_id=eq.${reportId}&limit=1`),
    ]);
    const rows = allRows.filter((row) => row.grouping_level !== "employee");
    return NextResponse.json({ report, rows, summary: summaries[0] ?? null }, { headers: noStore });
  } catch {
    return NextResponse.json({ error: "Financial reporting data is temporarily unavailable." }, { status: 503, headers: noStore });
  }
}

export async function POST(request: Request) {
  const authenticated = await authenticatePosRequest(request);
  if (!authenticated.ok) return authenticated.response;
  const { context } = authenticated;
  let body: unknown;
  try { body = await request.json(); } catch {
    return NextResponse.json({ error: "Request body must be valid JSON." }, { status: 400, headers: noStore });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return NextResponse.json({ error: "Invalid report request." }, { status: 400, headers: noStore });
  }
  const input = body as Record<string, unknown>;
  const allowed = ["location_id", "period_start", "period_end", "currency", "business_timezone"];
  if (Object.keys(input).some((key) => !allowed.includes(key)) ||
      !isUuid(input.location_id) || typeof input.period_start !== "string" ||
      typeof input.period_end !== "string" || !validDate(input.period_start) ||
      !validDate(input.period_end) || input.period_end < input.period_start ||
      typeof input.currency !== "string" || !currencyPattern.test(input.currency) ||
      !validTimezone(input.business_timezone)) {
    return NextResponse.json({ error: "Provide a valid store, date range, currency and IANA business timezone." }, { status: 400, headers: noStore });
  }
  if (!(await authorized(context, "pos.finance.report.build", input.location_id))) {
    return NextResponse.json({ error: "You do not have permission to build financial reports for this store." }, { status: 403, headers: noStore });
  }
  try {
    const response = await fetch(`${context.baseUrl}/rest/v1/rpc/mme_pos_build_financial_report`, {
      method: "POST",
      headers: { apikey: context.serviceKey, Authorization: `Bearer ${context.serviceKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        p_location_id: input.location_id, p_actor_person_id: context.personId,
        p_period_start: input.period_start, p_period_end: input.period_end,
        p_currency: input.currency, p_business_timezone: input.business_timezone,
      }),
      cache: "no-store",
    });
    if (!response.ok) {
      const details = await response.text();
      if (response.status === 403 || /permission denied/i.test(details)) {
        return NextResponse.json({ error: "Financial report build permission was denied." }, { status: 403, headers: noStore });
      }
      return NextResponse.json({ error: "The financial report could not be built. Verify that the Build 009.32 migration is applied." }, { status: 503, headers: noStore });
    }
    const reportId = await response.json() as unknown;
    if (!isUuid(reportId)) return NextResponse.json({ error: "The reporting service returned an invalid report reference." }, { status: 502, headers: noStore });
    return NextResponse.json({ report_id: reportId }, { status: 201, headers: noStore });
  } catch {
    return NextResponse.json({ error: "Financial reporting service is temporarily unavailable." }, { status: 503, headers: noStore });
  }
}
