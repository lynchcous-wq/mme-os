"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

type Product = {
  id: string; title: string; brand: string | null; category: string;
  catalog_condition: string; price_cents: number; currency: string;
  available_quantity: number;
};

const label = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, c => c.toUpperCase());
const price = (cents: number, currency: string) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);

export default function HomeLiveProducts() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let mounted = true;
    fetch("/api/catalog", { cache: "no-store" })
      .then(async response => {
        if (!response.ok) throw new Error("Catalog unavailable");
        return response.json() as Promise<{ products: Product[] }>;
      })
      .then(data => { if (mounted) setProducts((data.products ?? []).filter(p => p.available_quantity > 0).slice(0, 4)); })
      .catch(() => { if (mounted) setFailed(true); })
      .finally(() => { if (mounted) setLoading(false); });
    return () => { mounted = false; };
  }, []);

  return <>
    <p>{loading ? "Connecting to current MME inventory…" : failed ? "Verified inventory is temporarily unavailable." : "Live products, current database prices and available stock."}</p>
    {failed && <p role="status">Please check back shortly.</p>}
    {!loading && !failed && products.length === 0 && <div className="catalog-empty"><h3>Verified inventory is coming soon.</h3><p>Approved products linked to active sale inventory will appear here.</p></div>}
    {products.length > 0 && <div className="products">{products.map((p, i) => <article className="product" key={p.id}>
      <Link className={`product-image ${["peach", "lilac", "mint", "blue"][i % 4]}`} href={`/products/${p.id}`} aria-label={`View ${p.title}`}>
        <span className="badge">IN STOCK</span><span className="product-art" aria-hidden="true">◇</span><span className="image-condition">{label(p.catalog_condition)}</span>
      </Link>
      <div className="product-info"><small>{p.category.toUpperCase()}</small><Link href={`/products/${p.id}`}><b>{p.title}</b></Link>
        {p.brand && <span>{p.brand}</span>}<div className="price"><b>{price(p.price_cents, p.currency)}</b></div>
        <div className="condition">{p.available_quantity} available across active locations</div>
      </div>
    </article>)}</div>}
  </>;
}
