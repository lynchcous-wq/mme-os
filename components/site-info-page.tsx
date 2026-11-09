import Link from "next/link";

type SiteInfoPageProps = {
  eyebrow: string;
  title: string;
  description: string;
  details: string[];
  primaryHref?: string;
  primaryLabel?: string;
};

export default function SiteInfoPage({
  eyebrow, title, description, details, primaryHref = "/products", primaryLabel = "Explore the shop",
}: SiteInfoPageProps) {
  return (
    <main className="simple-page">
      <header className="header">
        <Link className="brand" href="/" aria-label="Much More Electronics home">
          <span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span>
        </Link>
        <nav aria-label="Page navigation"><Link href="/products">Shop all</Link><Link href="/#deals">Deals</Link></nav>
        <div className="actions"><Link href="/account">Account</Link><Link href="/cart">Bag</Link></div>
      </header>
      <section className="simple-content" style={{ maxWidth: 760 }}>
        <div className="eyebrow">{eyebrow}</div>
        <h1>{title}</h1>
        <p>{description}</p>
        <div style={{ margin: "28px 0", display: "grid", gap: 14 }}>
          {details.map((detail) => <p key={detail} style={{ margin: 0, padding: 16, border: "1px solid #dce4e9", borderRadius: 10, lineHeight: 1.55 }}>{detail}</p>)}
        </div>
        <Link className="button" href={primaryHref}>{primaryLabel} ↗</Link>
      </section>
      <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/">Home</Link></footer>
    </main>
  );
}
