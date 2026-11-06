"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";

type StoreProduct = {
  id: string;
  sku: string;
  title: string;
  description: string | null;
  brand: string | null;
  category: string;
  condition: string;
  price_cents: number;
  currency: string;
  available_quantity: number;
  availability: Array<{ location_name: string; available_quantity: number }>;
  specifications?: Record<string, unknown>;
  warranty_summary?: string | null;
};

type CatalogResponse = { products?: StoreProduct[]; error?: string };

const money = (cents: number, currency: string) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: currency || "USD" }).format(cents / 100);

export default function ProductsPage() {
  const [products, setProducts] = useState<StoreProduct[]>([]);
  const [query, setQuery] = useState("");
  const [condition, setCondition] = useState("all");
  const [status, setStatus] = useState<"loading" | "ready" | "empty" | "error">("loading");
  const [message, setMessage] = useState("");

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const requestedCondition = params.get("condition")?.toLowerCase();
    if (requestedCondition && ["new", "used", "refurbished", "open-box"].includes(requestedCondition)) {
      setCondition(requestedCondition);
    }

    const controller = new AbortController();
    fetch("/api/catalog", { cache: "no-store", signal: controller.signal })
      .then(async (response) => {
        const payload = (await response.json()) as CatalogResponse;
        if (!response.ok) throw new Error(payload.error || "The live catalog is temporarily unavailable.");
        const rows = Array.isArray(payload.products) ? payload.products : [];
        setProducts(rows);
        setStatus(rows.length ? "ready" : "empty");
      })
      .catch((error: unknown) => {
        if (error instanceof Error && error.name === "AbortError") return;
        setMessage(error instanceof Error ? error.message : "The live catalog could not be loaded.");
        setStatus("error");
      });

    return () => controller.abort();
  }, []);

  const visibleProducts = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    return products.filter((product) => {
      const matchesCondition = condition === "all" || product.condition.toLowerCase().includes(condition.replace("-", " "));
      const searchable = [product.title, product.brand, product.description, product.category, product.sku, product.condition]
        .filter(Boolean).join(" ").toLowerCase();
      return matchesCondition && (!normalized || searchable.includes(normalized));
    });
  }, [products, query, condition]);

  return (
    <main style={{ minHeight: "100vh", background: "#f6f7f8", color: "#172432" }}>
      <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 18, padding: "20px clamp(18px, 5vw, 64px)", background: "#fff", borderBottom: "1px solid #e4e8ec" }}>
        <Link href="/" style={{ color: "#173f58", fontWeight: 800, letterSpacing: 1.2, textDecoration: "none" }}>MUCH MORE<br />ELECTRONICS</Link>
        <nav aria-label="Store navigation" style={{ display: "flex", gap: 18, flexWrap: "wrap" }}>
          <Link href="/products" style={{ color: "#173f58" }}>Shop all</Link>
          <Link href="/account" style={{ color: "#173f58" }}>Account</Link>
          <Link href="/cart" style={{ color: "#173f58" }}>Bag</Link>
        </nav>
      </header>

      <section style={{ maxWidth: 1240, margin: "0 auto", padding: "48px 22px 72px" }}>
        <div style={{ color: "#647789", fontSize: 12, fontWeight: 700, letterSpacing: 2 }}>LIVE MME CATALOG</div>
        <h1 style={{ fontSize: "clamp(34px, 5vw, 56px)", margin: "10px 0", letterSpacing: -1.5 }}>Find your next <span style={{ color: "#1b7181" }}>favorite.</span></h1>
        <p style={{ color: "#5b6874", maxWidth: 680, lineHeight: 1.6 }}>Browse currently published products and available inventory. Prices and availability are loaded from the MME catalog—not sample listings.</p>

        <div style={{ display: "flex", gap: 12, flexWrap: "wrap", margin: "28px 0 22px" }}>
          <label style={{ flex: "1 1 260px" }}>
            <span style={{ display: "block", fontSize: 12, fontWeight: 700, marginBottom: 6 }}>SEARCH PRODUCTS</span>
            <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search by product, brand, category or SKU" style={{ width: "100%", padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, background: "#fff", color: "#172432" }} />
          </label>
          <label>
            <span style={{ display: "block", fontSize: 12, fontWeight: 700, marginBottom: 6 }}>CONDITION</span>
            <select value={condition} onChange={(event) => setCondition(event.target.value)} style={{ minWidth: 180, padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, background: "#fff", color: "#172432" }}>
              <option value="all">All conditions</option>
              <option value="new">New</option>
              <option value="used">Pre-loved / used</option>
              <option value="refurbished">Refurbished</option>
              <option value="open-box">Open box</option>
            </select>
          </label>
        </div>

        {status === "loading" && <p role="status" style={{ padding: 24, background: "#fff", borderRadius: 10 }}>Loading the live MME catalog…</p>}
        {status === "error" && <section role="alert" style={{ padding: 24, background: "#fff", border: "1px solid #e5b6b6", borderRadius: 10 }}><h2>Catalog unavailable</h2><p>{message}</p><p style={{ color: "#647789" }}>No sample products are shown as a substitute for live inventory.</p><button onClick={() => window.location.reload()} style={{ padding: "10px 16px", background: "#173f58", color: "#fff", border: 0, borderRadius: 7, cursor: "pointer" }}>Try again</button></section>}
        {status === "empty" && <p style={{ padding: 24, background: "#fff", borderRadius: 10 }}>No published products are currently available. Please check back soon.</p>}
        {status === "ready" && visibleProducts.length === 0 && <p style={{ padding: 24, background: "#fff", borderRadius: 10 }}>No products match those filters. Try another search or condition.</p>}

        {visibleProducts.length > 0 && (
          <>
            <p style={{ color: "#647789", fontSize: 13 }}>{visibleProducts.length} published {visibleProducts.length === 1 ? "product" : "products"}</p>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(min(100%, 250px), 1fr))", gap: 18 }}>
              {visibleProducts.map((product) => (
                <article key={product.id} style={{ background: "#fff", border: "1px solid #e1e6eb", borderRadius: 12, overflow: "hidden", display: "flex", flexDirection: "column" }}>
                  <div aria-hidden="true" style={{ minHeight: 128, display: "grid", placeItems: "center", background: "linear-gradient(135deg, #e8eef2, #f5f7f8)", color: "#1b526b", fontSize: 42 }}>◇</div>
                  <div style={{ padding: 18, display: "flex", flexDirection: "column", gap: 8, flex: 1 }}>
                    <div style={{ color: "#647789", fontSize: 11, fontWeight: 700, letterSpacing: 1 }}>{product.category}</div>
                    <h2 style={{ fontSize: 19, margin: 0 }}>{product.title}</h2>
                    {product.brand && <div style={{ color: "#647789", fontSize: 13 }}>{product.brand}</div>}
                    {product.description && <p style={{ margin: 0, color: "#5b6874", fontSize: 13, lineHeight: 1.5 }}>{product.description}</p>}
                    <div style={{ fontSize: 13, color: "#475765" }}>{product.condition}</div>
                    <div style={{ fontSize: 23, fontWeight: 800, color: "#173f58" }}>{money(product.price_cents, product.currency)}</div>
                    <div style={{ marginTop: "auto", paddingTop: 8, fontSize: 12, color: product.available_quantity > 0 ? "#24654a" : "#8b4b36" }}>
                      {product.available_quantity > 0 ? `${product.available_quantity} available` : "Currently unavailable"}
                    </div>
                    <div style={{ color: "#647789", fontSize: 11 }}>SKU: {product.sku}</div>
                  </div>
                </article>
              ))}
            </div>
          </>
        )}
      </section>
      <footer style={{ padding: 24, textAlign: "center", color: "#647789", borderTop: "1px solid #e4e8ec", background: "#fff" }}>© {new Date().getFullYear()} Much More Electronics</footer>
    </main>
  );
}
