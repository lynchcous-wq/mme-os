"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

type Provider = {
  providerKey: string; name: string; model: string; products: string[];
  merchantUrl: string; requirements: string[]; approval: string; fees: string;
  integrations: string[]; eligibility: string; readinessNote: string;
  status: string; merchantId: string | null; approvedProducts: string[];
  agreementReference: string | null; termsVerifiedAt: string | null;
};

export default function FinancingProvidersPage() {
  const [providers, setProviders] = useState<Provider[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    fetch("/api/financing/providers", { credentials: "same-origin", cache: "no-store" })
      .then(async response => {
        const body = await response.json();
        if (!response.ok) throw new Error(body.error || "Provider register unavailable.");
        if (active) setProviders(body.providers as Provider[]);
      })
      .catch(reason => { if (active) setError(reason instanceof Error ? reason.message : "Provider register unavailable."); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, []);

  return (
    <main className="simple-page">
      <header className="header">
        <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
        <nav aria-label="Employee navigation"><Link href="/employee-sign-in">Employee access</Link><Link href="/financing">Customer inquiries</Link></nav>
        <div className="actions"><Link href="/">Storefront</Link></div>
      </header>
      <section className="simple-content" style={{ width: "min(100%, 1100px)", margin: "0 auto" }}>
        <div className="eyebrow">MME internal · Financing Center</div>
        <h1>Provider <em>partnerships.</em></h1>
        <p>Compare financing models, merchant onboarding, consumer decision ownership, fee structures and integration pathways. This register is internal research—not proof that MME is approved or partnered with any provider.</p>
        <aside style={{ padding: 18, margin: "22px 0", border: "1px solid #d9cda9", background: "#fbf8ef", borderRadius: 5 }}>
          <strong>No provider is currently represented as active.</strong>
          <p style={{ margin: "8px 0 0", fontSize: 13, lineHeight: 1.65 }}>Links are for merchant partnership information only. Customer credit applications may be linked only after written merchant approval, integration testing and disclosure review.</p>
        </aside>
        {loading && <p role="status">Loading provider register…</p>}
        {error && <p role="alert" style={{ padding: 16, background: "#f8eeee", borderRadius: 5 }}>{error} <Link href="/employee-sign-in">Employee sign-in</Link></p>}
        {!loading && !error && <div style={{ display: "grid", gap: 18 }}>
          {providers.map(provider => (
            <article key={provider.providerKey} style={{ padding: 22, border: "1px solid #e5e2da", borderRadius: 7, background: "white" }}>
              <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "space-between", gap: 12, alignItems: "center" }}>
                <div><div className="eyebrow">{provider.model}</div><h2 style={{ margin: "6px 0", fontSize: 24 }}>{provider.name}</h2></div>
                <span style={{ padding: "6px 10px", borderRadius: 20, background: "#f1eee7", fontSize: 11, textTransform: "uppercase", letterSpacing: ".06em" }}>{provider.status.replaceAll("_", " ")}</span>
              </div>
              <p style={{ margin: "8px 0 14px", lineHeight: 1.6 }}>{provider.readinessNote}</p>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(230px,1fr))", gap: 16 }}>
                <div><strong>Financing products</strong><ul>{provider.products.map(x => <li key={x}>{x}</li>)}</ul></div>
                <div><strong>Merchant requirements</strong><ul>{provider.requirements.map(x => <li key={x}>{x}</li>)}</ul></div>
                <div><strong>Consumer approval</strong><p>{provider.approval}</p></div>
                <div><strong>Merchant fees</strong><p>{provider.fees}</p></div>
                <div><strong>Integration routes</strong><ul>{provider.integrations.map(x => <li key={x}>{x}</li>)}</ul></div>
                <div><strong>MME activation record</strong><p>Merchant ID: {provider.merchantId || "Not recorded"}<br />Approved products: {provider.approvedProducts.length ? provider.approvedProducts.join(", ") : "None recorded"}<br />Terms verified: {provider.termsVerifiedAt || "Not verified"}</p></div>
              </div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 16, alignItems: "center", marginTop: 14 }}>
                <a className="button" href={provider.merchantUrl} target="_blank" rel="noopener noreferrer">Merchant partnership information ↗</a>
                <span style={{ fontSize: 12, color: "#666" }}>Customer application link: unavailable until approval</span>
              </div>
            </article>
          ))}
        </div>}
        <p style={{ fontSize: 12, color: "#666", lineHeight: 1.6, marginTop: 24 }}>Fees and requirements are subject to provider underwriting and written agreements. Confirm used/refurbished inventory, returns, warranty, delivery, local pickup, cancellation, settlement, recourse and consumer disclosure terms before launch. Lease-to-own is distinct from a loan and may cost more than the cash price.</p>
      </section>
      <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/">Home</Link></footer>
    </main>
  );
}
