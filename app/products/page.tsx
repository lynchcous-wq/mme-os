"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";

type Availability = {
  location_id: string;
  location_code: string;
  location_name: string;
  available_quantity: number;
};

type Product = {
  id: string;
  sku: string;
  title: string;
  description: string | null;
  brand: string | null;
  category: string;
  condition: string;
  catalog_condition: string;
  price_cents: number;
  currency: string;
  serialized: boolean;
  specifications: Record<string, unknown>;
  warranty_summary: string | null;
  availability: Availability[];
  available_quantity: number;
};

function money(cents: number, currency: string) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
}

function conditionLabel(value: string) {
  return value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export default function ProductsPage() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [condition, setCondition] = useState("all");
  const [category, setCategory] = useState("all");

  useEffect(() => {
    let active = true;
    fetch("/api/catalog", { cache: "no-store" })
      .then(async (response) => {
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || "The live catalog is unavailable.");
        return payload as { products: Product[] };
      })
      .then((payload) => {
        if (active) setProducts(payload.products ?? []);
      })
      .catch((reason: unknown) => {
        if (active) setError(reason instanceof Error ? reason.message : "The live catalog is unavailable.");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => { active = false; };
  }, []);

  const categories = useMemo(
    () => Array.from(new Set(products.map((product) => product.category))).sort(),
    [products],
  );

  const visibleProducts = useMemo(() => products.filter((product) => {
    const searchable = [product.title, product.brand, product.sku, product.category].filter(Boolean).join(" ").toLowerCase();
    return (condition === "all" || product.catalog_condition === condition)
      && (category === "all" || product.category === category)
      && searchable.includes(search.toLowerCase());
  }), [products, condition, category, search]);

  return <main className="simple-page catalog-page">
    <header className="header">
      <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
      <nav aria-label="Shop navigation"><Link href="/products">Shop all</Link><Link href="/#deals">Deals</Link></nav>
      <div className="actions"><Link href="/account">Account</Link><Link href="/cart">Bag <span className="count">0</span></Link></div>
    </header>

    <section className="catalog-intro">
      <div className="eyebrow">The MME collection</div>
      <h1>Find your next <em>favorite.</em></h1>
      <p>Explore new, pre-loved and refurbished electronics, with pricing and availability from our live inventory.</p>
      <div className="catalog-status" role="status">{loading ? "Connecting to live inventory…" : error ? "Live catalog currently unavailable" : `${products.length} products in the live catalog`}</div>
    </section>

    <section className="catalog-shell" aria-label="Product catalog">
      <div className="catalog-toolbar">
        <label className="catalog-search"> <span className="sr-only">Search products</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search products, brands or SKU" /></label>
        <label className="catalog-filter">Condition
          <select value={condition} onChange={(event) => setCondition(event.target.value)}>
            <option value="all">All conditions</option>
            <option value="new">New</option>
            <option value="open_box">Open box</option>
            <option value="like_new">Like new</option>
            <option value="refurbished">Refurbished</option>
            <option value="used_excellent">Pre-owned · Excellent</option>
            <option value="used_good">Pre-owned · Good</option>
            <option value="used_fair">Pre-owned · Fair</option>
          </select>
        </label>
        <label className="catalog-filter">Category
          <select value={category} onChange={(event) => setCategory(event.target.value)}>
            <option value="all">All categories</option>
            {categories.map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
        </label>
      </div>

      {loading && <div className="catalog-empty"><div className="eyebrow">One moment</div><h2>Loading live inventory.</h2><p>We’re checking current products and store availability.</p></div>}
      {!loading && error && <div className="catalog-empty"><div className="eyebrow">Not connected yet</div><h2>Live inventory is not available.</h2><p>{error} Product previews are not offered for purchase. Please check back soon.</p><Link className="button" href="/">Back to home ↗</Link></div>}
      {!loading && !error && visibleProducts.length === 0 && <div className="catalog-empty"><div className="eyebrow">Your search</div><h2>{products.length ? "No matching products." : "The catalog is being stocked."}</h2><p>{products.length ? "Try another search or adjust your filters." : "Verified products will appear here as MME inventory is published and linked for sale."}</p></div>}

      {!loading && !error && visibleProducts.length > 0 && <div className="live-products">
        {visibleProducts.map((product) => <article className="live-product" key={product.id}>
          <div className="live-product-art"><span className="live-product-mark">MME</span><span className="live-product-symbol">◇</span></div>
          <div className="live-product-info">
            <small>{product.category} · {conditionLabel(product.catalog_condition)}</small>
            <h2><Link href={`/products/${product.id}`}>{product.title}</Link></h2>
            {product.brand && <span className="live-brand">{product.brand}</span>}
            {product.description && <p>{product.description}</p>}
            <div className="live-price">{money(product.price_cents, product.currency)}</div>
            <div className={product.available_quantity > 0 ? "live-stock" : "live-stock unavailable"}>
              {product.available_quantity > 0 ? `${product.available_quantity} available across active locations` : "Currently unavailable"}
            </div>
            {product.availability.length > 0 && <details className="location-details">
              <summary>Check store availability</summary>
              <ul>{product.availability.map((item) => <li key={item.location_id}><span>{item.location_name}</span><b>{item.available_quantity > 0 ? `${item.available_quantity} available` : "Unavailable"}</b></li>)}</ul>
            </details>}
            <button className="catalog-disabled-button" type="button" disabled title="Checkout will be enabled after customer identity, tax, fulfillment and payment validation.">Purchasing coming soon</button>
          </div>
        </article>)}
      </div>}
    </section>

    <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/">Home</Link></footer>
  </main>;
}
