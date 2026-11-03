import Link from "next/link";

export default function ProductsPage() {
  return <main className="simple-page"><header className="header"><Link className="brand" href="/"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link><nav><Link href="/products">Shop all</Link><Link href="/#deals">Deals</Link></nav><div className="actions"><Link href="/account">Account</Link><Link href="/cart">Bag <span className="count">0</span></Link></div></header><section className="simple-content"><div className="eyebrow">Explore MME</div><h1>All the good <em>tech.</em></h1><p>The catalog is being prepared. Check back soon for new, pre-loved and refurbished electronics.</p><Link className="button" href="/">Back to home ↗</Link></section><footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/">Home</Link></footer></main>;
}
