import Link from "next/link";

export const metadata = {
  title: "Shopping Bag",
  description: "View your Much More Electronics shopping bag.",
  alternates: { canonical: "/cart" },
  robots: { index: false, follow: true },
};

export default function CartPage() {
  return (
    <main className="simple-page">
      <header className="header">
        <Link className="brand" href="/" aria-label="Much More Electronics home">
          <span className="brand-mark">MM</span>
          <span>MUCH MORE<br /><b>ELECTRONICS</b></span>
        </Link>
        <nav aria-label="Main navigation">
          <Link href="/">Home</Link>
          <Link href="/products">Shop all</Link>
          <Link href="/account">Account</Link>
        </nav>
        <div className="actions"><Link href="/account">Customer account</Link></div>
      </header>
      <section className="simple-content" style={{ width: "min(100%, 760px)", margin: "0 auto" }}>
        <div className="eyebrow">Your MME shopping bag</div>
        <h1>Your bag is <em>waiting.</em></h1>
        <p>
          Online cart and checkout are not yet available. We are preparing
          secure shopping, inventory reservation, taxes, shipping and payment
          confirmation before accepting online orders.
        </p>
        <div style={{ margin: "28px 0", padding: 22, border: "1px solid #e8e5de", background: "#fff" }}>
          <strong>Online checkout is not open yet.</strong>
          <p style={{ marginBottom: 0 }}>
            No order has been created and no payment will be collected from this page.
          </p>
        </div>
        <Link className="button" href="/products">Explore MME categories ↗</Link>
      </section>
      <footer className="simple-footer">
        <span>© {new Date().getFullYear()} Much More Electronics</span>
        <Link href="/">Home</Link>
        <Link href="/account">Customer account</Link>
      </footer>
    </main>
  );
}
