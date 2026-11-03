import Link from "next/link";

export default function AccountPage() {
  return <main className="simple-page"><header className="header"><Link className="brand" href="/"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link><nav><Link href="/products">Shop all</Link></nav><div className="actions"><Link href="/cart">Bag <span className="count">0</span></Link></div></header><section className="simple-content"><div className="eyebrow">Your MME</div><h1>Coming <em>soon.</em></h1><p>Customer accounts are part of the next build phase. Explore the storefront while we prepare your MME account experience.</p><Link className="button" href="/products">Explore the shop ↗</Link></section><footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/">Home</Link></footer></main>;
}
