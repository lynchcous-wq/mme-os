"use client";

import { FormEvent, useMemo, useState } from "react";

type ReportRow = {
  id: string; business_date: string; grouping_level: string; grouping_reference: string | null;
  currency: string; gross_sales_minor: number; discounts_minor: number; refunds_minor: number;
  subscription_revenue_minor: number; net_sales_minor: number; sales_tax_minor: number;
  cost_of_goods_sold_minor: number; processor_fees_minor: number; chargebacks_minor: number;
  cash_over_short_minor: number; inventory_adjustments_minor: number; gross_profit_minor: number;
  contribution_profit_minor: number; source_fact_count: number;
};
type Report = { id: string; status: string; currency: string; period_start: string; period_end: string;
  business_timezone: string; source_fact_count: number; built_at: string; source_cutoff_at: string };
type Summary = { settlement_net_minor: number; settlement_fee_minor: number; matched_bank_deposit_minor: number;
  cash_expected_minor: number; cash_counted_minor: number; cash_variance_minor: number;
  open_settlement_exception_count: number; unreconciled_batch_count: number };
type Payload = { report: Report | null; rows: ReportRow[]; summary: Summary | null; error?: string };

const isoDate = (d: Date) => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
const dollars = (minor: number | null | undefined, currency: string) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency, maximumFractionDigits: 2 }).format((Number(minor) || 0) / 100);
const integer = (n: number | null | undefined) => new Intl.NumberFormat("en-US").format(Number(n) || 0);

export default function FinancialReportsPage() {
  const today = useMemo(() => new Date(), []);
  const [token,setToken] = useState("");
  const [locationId,setLocationId] = useState("");
  const [start,setStart] = useState(isoDate(new Date(today.getFullYear(),today.getMonth(),1)));
  const [end,setEnd] = useState(isoDate(today));
  const [currency,setCurrency] = useState("USD");
  const [timezone,setTimezone] = useState("America/New_York");
  const [payload,setPayload] = useState<Payload | null>(null);
  const [busy,setBusy] = useState(false);
  const [error,setError] = useState("");
  const [notice,setNotice] = useState("");

  async function requestReport(method: "GET" | "POST") {
    setError(""); setNotice(""); setBusy(true);
    try {
      const headers: Record<string,string> = { Authorization: `Bearer ${token.trim()}` };
      let url = "/api/pos/financial-reports";
      let body: string | undefined;
      if (method === "GET") {
        const query = new URLSearchParams({ location_id: locationId.trim(), period_start: start, period_end: end, currency });
        url += `?${query.toString()}`;
      } else {
        headers["Content-Type"] = "application/json";
        body = JSON.stringify({ location_id: locationId.trim(), period_start: start, period_end: end, currency, business_timezone: timezone });
      }
      const response = await fetch(url,{method,headers,body,cache:"no-store"});
      const data = await response.json() as Payload & { report_id?: string };
      if (!response.ok) throw new Error(data.error || "Financial report request failed.");
      if (method === "POST") {
        setNotice("Report snapshot created. Loading its results…");
        const query = new URLSearchParams({ location_id: locationId.trim(), period_start: start, period_end: end, currency });
        const read = await fetch(`/api/pos/financial-reports?${query.toString()}`,{headers:{Authorization:`Bearer ${token.trim()}`},cache:"no-store"});
        const result = await read.json() as Payload;
        if (!read.ok) throw new Error(result.error || "Report created, but results could not be loaded.");
        setPayload(result);
      } else {
        setPayload(data);
        if (!data.report) setNotice("No report snapshot exists for this store and period yet. Build one if you have report-build permission.");
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unable to load financial report.");
    } finally { setBusy(false); }
  }

  function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!token.trim() || !locationId.trim() || !start || !end || end < start) {
      setError("Enter an employee session access token, store ID and valid date range."); return;
    }
    void requestReport("GET");
  }

  const storeRows = (payload?.rows ?? []).filter(r => r.grouping_level === "store");
  const categoryRows = (payload?.rows ?? []).filter(r => r.grouping_level === "product_category");
  const registerRows = (payload?.rows ?? []).filter(r => r.grouping_level === "register");
  const employeeRows: ReportRow[] = []; // Employee-level reporting is withheld until a distinct employee-finance permission is deployed.
  const totals = storeRows.reduce((a,r) => ({
    gross:a.gross+r.gross_sales_minor,discounts:a.discounts+r.discounts_minor,refunds:a.refunds+r.refunds_minor,
    net:a.net+r.net_sales_minor,tax:a.tax+r.sales_tax_minor,cogs:a.cogs+r.cost_of_goods_sold_minor,
    grossProfit:a.grossProfit+r.gross_profit_minor,fees:a.fees+r.processor_fees_minor,
    chargebacks:a.chargebacks+r.chargebacks_minor,contribution:a.contribution+r.contribution_profit_minor
  }),{gross:0,discounts:0,refunds:0,net:0,tax:0,cogs:0,grossProfit:0,fees:0,chargebacks:0,contribution:0});
  const fmt = (v:number) => dollars(v,payload?.report?.currency ?? currency);
  const percent = totals.net ? (totals.grossProfit/totals.net*100).toFixed(1)+"%" : "—";
  const maxDailySales = Math.max(1, ...storeRows.map(r => Math.max(0,r.net_sales_minor)));
  function downloadCsv() {
    if (!payload?.report) return;
    const columns = ["business_date","gross_sales_minor","discounts_minor","refunds_minor","net_sales_minor","sales_tax_minor","cost_of_goods_sold_minor","gross_profit_minor","processor_fees_minor","chargebacks_minor","contribution_profit_minor"] as const;
    const lines = [columns.join(","), ...storeRows.map(row => columns.map(key => String(row[key] ?? "")).join(","))];
    const blob = new Blob([lines.join("\r\n")], {type:"text/csv;charset=utf-8"});
    const url = URL.createObjectURL(blob); const anchor = document.createElement("a");
    anchor.href = url; anchor.download = `mme-financial-report-${payload.report.period_start}-${payload.report.period_end}.csv`;
    document.body.appendChild(anchor); anchor.click(); anchor.remove(); URL.revokeObjectURL(url);
  }

  return <main className="finance-page">
    <header className="finance-header"><a className="brand" href="/"><span className="brand-mark">MM</span><span>MUCH MORE<br/><b>ELECTRONICS</b></span></a><div><span className="finance-kicker">MME OS · BUILD 009.33</span><h1>Financial intelligence</h1></div><a className="finance-back" href="/">Storefront ↗</a></header>
    <section className="finance-intro"><div><span className="finance-eyebrow">CEO · FINANCE · STORE OPERATIONS</span><h2>See the whole <em>picture.</em></h2><p>Sales, profitability, processor settlement and cash controls in one auditable reporting workspace.</p></div><div className="finance-lock">⌑ &nbsp; Protected employee access</div></section>
    <form className="finance-filters" onSubmit={submit}>
      <label className="finance-wide">Employee session access token<input type="password" autoComplete="off" value={token} onChange={e=>setToken(e.target.value)} placeholder="Paste your current Supabase employee access token" required/><small>Held in page memory only; never saved to local storage. Sign-in integration is pending.</small></label>
      <label>Store / location ID<input value={locationId} onChange={e=>setLocationId(e.target.value)} placeholder="Store UUID" required/></label>
      <label>From<input type="date" value={start} onChange={e=>setStart(e.target.value)} required/></label>
      <label>Through<input type="date" value={end} onChange={e=>setEnd(e.target.value)} min={start} required/></label>
      <label>Currency<select value={currency} onChange={e=>setCurrency(e.target.value)}><option>USD</option><option>CAD</option><option>GBP</option><option>EUR</option></select></label>
      <label>Business timezone<input value={timezone} onChange={e=>setTimezone(e.target.value)} placeholder="America/New_York" required/></label>
      <div className="finance-actions"><button type="submit" disabled={busy}>{busy?"Loading…":"Load report"}</button><button type="button" className="finance-secondary" disabled={busy||!token.trim()||!locationId.trim()} onClick={()=>void requestReport("POST")}>Build new snapshot</button></div>
    </form>
    {error && <div className="finance-alert" role="alert">{error}</div>}
    {notice && <div className="finance-notice" role="status">{notice}</div>}
    {!payload?.report ? <section className="finance-empty"><div>▤</div><h3>Your financial command center</h3><p>Enter your employee session and authorized store details to load a saved report or create a new snapshot.</p><small>Reports only appear when Build 009.32 is migrated and trusted financial facts have been imported.</small></section> : <>
      <section className="finance-report-meta"><div><span className="finance-eyebrow">REPORT SNAPSHOT</span><h3>{payload.report.period_start} — {payload.report.period_end}</h3><p>{payload.report.status.replaceAll("_"," ")} · {payload.report.currency} · {payload.report.business_timezone}</p></div><div><span>Source facts</span><b>{integer(payload.report.source_fact_count)}</b></div><div><span>Generated</span><b>{new Date(payload.report.built_at).toLocaleString()}</b></div><div><span>Source cutoff</span><b>{new Date(payload.report.source_cutoff_at).toLocaleString()}</b></div></section>
      <section className="finance-kpis">
        <article><span>Net sales</span><b>{fmt(totals.net)}</b><small>Gross sales less discounts and refunds, plus subscriptions</small></article>
        <article><span>Gross profit</span><b>{fmt(totals.grossProfit)}</b><small>{percent} gross margin</small></article>
        <article><span>Contribution profit</span><b>{fmt(totals.contribution)}</b><small>After recorded fees, chargebacks and cash variance</small></article>
        <article><span>Cost of goods sold</span><b>{fmt(totals.cogs)}</b><small>Source-attributed inventory cost</small></article>
      </section>
      <section className="finance-two-col"><article className="finance-panel"><div className="finance-panel-head"><div><span className="finance-eyebrow">PERIOD PERFORMANCE</span><h3>Sales breakdown</h3></div></div><div className="finance-metric"><span>Gross sales</span><b>{fmt(totals.gross)}</b></div><div className="finance-metric"><span>Discounts</span><b>{fmt(totals.discounts)}</b></div><div className="finance-metric"><span>Refunds</span><b>{fmt(totals.refunds)}</b></div><div className="finance-metric"><span>Net sales</span><b>{fmt(totals.net)}</b></div><div className="finance-metric"><span>Sales tax (separate)</span><b>{fmt(totals.tax)}</b></div></article>
      <article className="finance-panel"><div className="finance-panel-head"><div><span className="finance-eyebrow">PROCESSOR & CASH CONTROL</span><h3>Reconciliation overview</h3></div></div>{payload.summary ? <><div className="finance-metric"><span>Processor net settlement</span><b>{fmt(payload.summary.settlement_net_minor)}</b></div><div className="finance-metric"><span>Processor fees</span><b>{fmt(payload.summary.settlement_fee_minor)}</b></div><div className="finance-metric"><span>Matched bank deposits</span><b>{fmt(payload.summary.matched_bank_deposit_minor)}</b></div><div className="finance-metric"><span>Cash variance</span><b>{fmt(payload.summary.cash_variance_minor)}</b></div><div className="finance-metric"><span>Open settlement exceptions</span><b>{integer(payload.summary.open_settlement_exception_count)}</b></div><div className="finance-metric"><span>Unreconciled batches</span><b>{integer(payload.summary.unreconciled_batch_count)}</b></div></> : <p className="finance-muted">Settlement summary unavailable.</p>}<small className="finance-footnote">Settlement and bank deposits are collections of recorded sales, not additional revenue.</small></article></section>
      <section className="finance-panel finance-table-panel"><div className="finance-panel-head"><div><span className="finance-eyebrow">TREND</span><h3>Daily financial performance</h3></div><div className="finance-export"><span>{storeRows.length} days</span><button type="button" onClick={downloadCsv}>Export CSV ↓</button></div></div><div className="finance-chart" aria-label="Daily net sales bar chart">{storeRows.map(r=><div className="finance-chart-column" key={r.id} title={`${r.business_date}: ${fmt(r.net_sales_minor)}`}><span className="finance-chart-value">{fmt(r.net_sales_minor)}</span><div className="finance-chart-track"><div className="finance-chart-bar" style={{height:`${Math.max(2,Math.max(0,r.net_sales_minor)/maxDailySales*100)}%`}}/></div><small>{r.business_date.slice(5)}</small></div>)}</div><div className="finance-table-wrap"><table><thead><tr><th>Date</th><th>Gross sales</th><th>Discounts</th><th>Refunds</th><th>Net sales</th><th>COGS</th><th>Gross profit</th><th>Contribution</th></tr></thead><tbody>{storeRows.map(r=><tr key={r.id}><td>{r.business_date}</td><td>{fmt(r.gross_sales_minor)}</td><td>{fmt(r.discounts_minor)}</td><td>{fmt(r.refunds_minor)}</td><td>{fmt(r.net_sales_minor)}</td><td>{fmt(r.cost_of_goods_sold_minor)}</td><td>{fmt(r.gross_profit_minor)}</td><td>{fmt(r.contribution_profit_minor)}</td></tr>)}</tbody></table></div></section>
      {categoryRows.length>0 && <section className="finance-panel finance-table-panel"><div className="finance-panel-head"><div><span className="finance-eyebrow">MERCHANDISING</span><h3>Category profitability</h3></div></div><div className="finance-table-wrap"><table><thead><tr><th>Category</th><th>Net sales</th><th>COGS</th><th>Gross profit</th><th>Contribution</th></tr></thead><tbody>{categoryRows.map(r=><tr key={r.id}><td>{r.grouping_reference||"Uncategorized"}</td><td>{fmt(r.net_sales_minor)}</td><td>{fmt(r.cost_of_goods_sold_minor)}</td><td>{fmt(r.gross_profit_minor)}</td><td>{fmt(r.contribution_profit_minor)}</td></tr>)}</tbody></table></div></section>}
      {registerRows.length>0 && <section className="finance-panel finance-table-panel"><div className="finance-panel-head"><div><span className="finance-eyebrow">REGISTER PERFORMANCE</span><h3>Register comparison</h3></div></div><div className="finance-table-wrap"><table><thead><tr><th>Register</th><th>Net sales</th><th>Gross profit</th><th>Contribution</th></tr></thead><tbody>{registerRows.map(r=><tr key={r.id}><td>{r.grouping_reference||"Unassigned"}</td><td>{fmt(r.net_sales_minor)}</td><td>{fmt(r.gross_profit_minor)}</td><td>{fmt(r.contribution_profit_minor)}</td></tr>)}</tbody></table></div></section>}
      {employeeRows.length>0 && <section className="finance-panel finance-table-panel"><div className="finance-panel-head"><div><span className="finance-eyebrow">TEAM PERFORMANCE</span><h3>Employee sales comparison</h3></div></div><p className="finance-muted">Visible only to roles granted employee-level financial reporting access.</p><div className="finance-table-wrap"><table><thead><tr><th>Employee reference</th><th>Net sales</th><th>Gross profit</th><th>Contribution</th></tr></thead><tbody>{employeeRows.map(r=><tr key={r.id}><td>{r.grouping_reference||"Unassigned"}</td><td>{fmt(r.net_sales_minor)}</td><td>{fmt(r.gross_profit_minor)}</td><td>{fmt(r.contribution_profit_minor)}</td></tr>)}</tbody></table></div></section>}
      <p className="finance-disclaimer">Management reporting only. Employee-level financial comparisons remain hidden until a separate employee-finance permission is implemented. Confirm source completeness and accounting treatment with Finance. Forecasts are illustrative and actual results depend on verified imported source facts.</p>
    </>}
    <footer className="finance-footer">Much More Electronics · MME OS · Build 009.33 · Financial data is access-controlled and not cached.</footer>
  </main>;
}
