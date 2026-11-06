import Link from "next/link";

const metrics = [
  ["Warranty revenue", "Actuals pending", "Approved sales ledger required"],
  ["Warranty expense", "Actuals pending", "Repair, parts and labor entries"],
  ["Net warranty margin", "Not calculated", "Requires verified revenue and costs"],
  ["Claims-to-sales", "Not calculated", "Sales denominator feed required"],
  ["Provider recovery", "Not reconciled", "Matched settlement evidence required"],
  ["Average turnaround", "Not calculated", "Repair case timestamps required"],
];

const panels = [
  { title: "Financial performance", detail: "Revenue, repair costs, refunds and provider recoveries, separated by realization and currency." },
  { title: "Claims & service", detail: "Approval trends, repair-versus-replacement outcomes, open cases and turnaround time." },
  { title: "Provider scorecards", detail: "Response SLA, late responses, availability and reimbursement match rate with sample sizes." },
  { title: "Risk & exceptions", detail: "Review queues and exception trends. Internal risk signals remain access-restricted and are not customer-facing." },
  { title: "Expiration outlook", detail: "Upcoming coverage expirations and renewal opportunities based on verified coverage dates." },
  { title: "Category analysis", detail: "Warranty cost and performance by product category, provider and reporting period." },
];

export const metadata = { title: "Warranty Command | MME OS", description: "Executive warranty intelligence and analytics." };

export default function WarrantyCommandPage() {
  return <main className="warranty-command">
    <header className="wc-header">
      <Link href="/" className="wc-brand"><span>MM</span><b>MUCH MORE ELECTRONICS<br/>OPERATING SYSTEM</b></Link>
      <nav><Link href="/ops">Operations</Link><Link href="/account">Customer portal</Link><span>Executive workspace</span></nav>
    </header>
    <section className="wc-hero">
      <div><p className="wc-eyebrow">Build 009.72 · Executive intelligence</p><h1>Warranty <em>command.</em></h1><p className="wc-intro">A consolidated view of warranty financial performance, claims, provider service levels and coverage outlook.</p></div>
      <div className="wc-status"><span className="wc-dot"/> DATA CONNECTION STATUS<strong>Awaiting verified source feeds</strong><small>This workspace does not display sample figures as business actuals.</small></div>
    </section>
    <section className="wc-toolbar" aria-label="Report controls">
      <div><small>REPORTING PERIOD</small><strong>Monthly · Select period when data feed is connected</strong></div>
      <div><small>REALIZATION</small><strong><span className="wc-chip actual">Actual</span><span className="wc-chip projected">Projection</span> Displayed separately</strong></div>
      <button type="button" disabled title="Available when analytics data is connected">Export report ↗</button>
    </section>
    <section className="wc-section">
      <div className="wc-section-heading"><div><p className="wc-eyebrow">Executive overview</p><h2>Performance at a glance</h2></div><span className="wc-muted">No live figures loaded</span></div>
      <div className="wc-metrics">{metrics.map(([name,value,detail])=><article className="wc-metric" key={name}><small>{name}</small><strong>{value}</strong><p>{detail}</p><span>—</span></article>)}</div>
    </section>
    <section className="wc-section">
      <div className="wc-section-heading"><div><p className="wc-eyebrow">Intelligence modules</p><h2>Explore warranty operations</h2></div></div>
      <div className="wc-panels">{panels.map((p,i)=><article className="wc-panel" key={p.title}><span>0{i+1}</span><h3>{p.title}</h3><p>{p.detail}</p><small>DATA SOURCE REQUIRED</small></article>)}</div>
    </section>
    <section className="wc-governance"><div><p className="wc-eyebrow">Financial integrity</p><h2>Actuals stay actual.</h2></div><ul><li>Actual and projected results are never blended.</li><li>Provider claim approval is not recognized as cash reimbursement.</li><li>Missing denominators display as unavailable, not zero.</li><li>Currency, reporting period and source provenance remain visible.</li><li>Executive views use aggregated data and role-restricted access.</li></ul></section>
    <footer className="wc-footer"><span>MME OS · Warranty Intelligence</span><span>Build 009.72 · Dashboard foundation</span></footer>
  </main>;
}
