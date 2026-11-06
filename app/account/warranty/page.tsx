import Link from "next/link";

export const metadata = {
  title: "Warranty Center | Much More Electronics",
  description: "Customer warranty claims and repair support from Much More Electronics.",
};

const steps = [
  { number: "01", title: "Submit your claim", detail: "Share the purchase reference, product details and a description of the issue." },
  { number: "02", title: "Verify coverage", detail: "MME checks the purchase, product identifier and applicable warranty terms." },
  { number: "03", title: "Review evidence", detail: "Securely provide requested receipts, diagnostics or product photos when uploads are enabled." },
  { number: "04", title: "Track the resolution", detail: "Follow review, repair, replacement or refund decisions from your customer account." },
];

export default function CustomerWarrantyPage() {
  return <main className="customer-warranty">
    <header className="cwp-header">
      <Link href="/" className="cwp-brand"><span>MM</span><b>MUCH MORE<br/>ELECTRONICS</b></Link>
      <nav><Link href="/products">Shop</Link><Link href="/account">My account</Link></nav>
    </header>
    <section className="cwp-hero">
      <p className="cwp-eyebrow">MME customer care</p>
      <h1>Warranty care,<br/><em>made simpler.</em></h1>
      <p>Keep your warranty questions, claim progress and repair decisions together in one secure customer experience.</p>
      <div className="cwp-actions"><Link href="/account" className="cwp-primary">Go to my account</Link><Link href="/products" className="cwp-secondary">Explore products</Link></div>
      <div className="cwp-hero-note"><span/> Your warranty information is private and tied to your MME customer account.</div>
    </section>
    <section className="cwp-content">
      <div className="cwp-section-title"><div><p className="cwp-eyebrow">Your warranty center</p><h2>One place for every step.</h2></div><span className="cwp-status">ACCOUNT CONNECTION REQUIRED</span></div>
      <div className="cwp-empty">
        <div className="cwp-icon">⌕</div>
        <div><h3>Your claims will appear here.</h3><p>Sign in to your MME customer account to access purchase-linked coverage and claim history. Live account lookup is not enabled in this release, so no personal claim records are shown here.</p><Link href="/account">Continue to customer account ↗</Link></div>
      </div>
      <div className="cwp-section-title cwp-process-title"><div><p className="cwp-eyebrow">How it works</p><h2>From issue to resolution.</h2></div></div>
      <div className="cwp-steps">{steps.map(step=><article key={step.number}><span>{step.number}</span><h3>{step.title}</h3><p>{step.detail}</p></article>)}</div>
    </section>
    <section className="cwp-privacy"><div><p className="cwp-eyebrow">Privacy & protection</p><h2>Your device details stay protected.</h2></div><p>Serial numbers, IMEIs, receipts and claim evidence must be handled through authenticated, private services. This page does not request or store those details until secure account access and evidence upload are connected.</p></section>
    <footer className="cwp-footer"><span>MUCH MORE ELECTRONICS · CUSTOMER CARE</span><span>Warranty Center · Build 009.77 foundation</span></footer>
  </main>;
}
