"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";

type CartLine = {
  product_id: string;
  location_id: string;
  quantity: number;
  title: string;
  sku: string;
  unit_price_cents: number;
  currency: string;
};

type ValidatedLine = CartLine & {
  line_total_cents: number;
  available_quantity: number;
  location_name: string;
};

const STORAGE_KEY = "mme-shopping-cart-v1";
const money = (cents: number, currency: string) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: currency || "USD" }).format(cents / 100);

function readCart(): CartLine[] {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((line): line is CartLine =>
      !!line && typeof line.product_id === "string" &&
      typeof line.location_id === "string" &&
      Number.isInteger(line.quantity) && line.quantity > 0 &&
      typeof line.title === "string" && typeof line.sku === "string" &&
      Number.isInteger(line.unit_price_cents) && typeof line.currency === "string"
    );
  } catch {
    return [];
  }
}

export default function CartPage() {
  const [items, setItems] = useState<CartLine[]>([]);
  const [validated, setValidated] = useState<ValidatedLine[]>([]);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [checked, setChecked] = useState(false);

  useEffect(() => setItems(readCart()), []);

  function persist(next: CartLine[]) {
    setItems(next);
    setValidated([]);
    setChecked(false);
    setMessage("");
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
    } catch {
      setMessage("Your browser could not save cart changes. Check available device storage.");
    }
  }

  function changeQuantity(index: number, quantity: number) {
    if (!Number.isInteger(quantity) || quantity < 1) return;
    persist(items.map((item, i) => i === index ? { ...item, quantity: Math.min(100, quantity) } : item));
  }

  function remove(index: number) {
    persist(items.filter((_, i) => i !== index));
  }

  async function validateCart() {
    if (!items.length || busy) return;
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch("/api/cart/validate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        body: JSON.stringify({ items: items.map(({ product_id, location_id, quantity }) => ({ product_id, location_id, quantity })) }),
      });
      const result = await response.json() as { items?: ValidatedLine[]; error?: string };
      if (!response.ok || !Array.isArray(result.items)) throw new Error(result.error || "We could not verify your cart.");
      setValidated(result.items);
      setChecked(true);
      setMessage("Prices and inventory were checked against the live MME catalog. Inventory is not reserved yet.");
    } catch (error) {
      setValidated([]);
      setChecked(false);
      setMessage(error instanceof Error ? error.message : "Cart validation is temporarily unavailable.");
    } finally {
      setBusy(false);
    }
  }

  const subtotal = useMemo(
    () => (checked ? validated : items).reduce((sum, item) => sum + (checked && "line_total_cents" in item ? item.line_total_cents : item.unit_price_cents * item.quantity), 0),
    [checked, items, validated],
  );
  const currency = checked ? validated[0]?.currency ?? "USD" : items[0]?.currency ?? "USD";
  const currencyMismatch = new Set(items.map(item => item.currency)).size > 1;

  return (
    <main style={{ minHeight: "100vh", background: "#f6f7f8", color: "#172432" }}>
      <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 18, padding: "20px clamp(18px, 5vw, 64px)", background: "#fff", borderBottom: "1px solid #e4e8ec" }}>
        <Link href="/" style={{ color: "#173f58", fontWeight: 800, letterSpacing: 1.2, textDecoration: "none" }}>MUCH MORE<br />ELECTRONICS</Link>
        <nav aria-label="Store navigation" style={{ display: "flex", gap: 18, flexWrap: "wrap" }}>
          <Link href="/products" style={{ color: "#173f58" }}>Continue shopping</Link>
          <Link href="/account" style={{ color: "#173f58" }}>Account</Link>
        </nav>
      </header>
      <section style={{ maxWidth: 1040, margin: "0 auto", padding: "42px 22px 72px" }}>
        <p style={{ color: "#647789", fontSize: 12, fontWeight: 800, letterSpacing: 2 }}>YOUR MME BAG</p>
        <h1 style={{ fontSize: "clamp(32px, 5vw, 48px)", margin: "8px 0 28px" }}>Shopping cart</h1>
        {message && <p role="status" aria-live="polite" style={{ padding: 14, background: "#fff", border: "1px solid #dfe6eb", borderRadius: 9, lineHeight: 1.5 }}>{message}</p>}
        {!items.length ? (
          <section style={{ background: "#fff", border: "1px solid #e1e6eb", borderRadius: 12, padding: 28 }}>
            <h2>Your cart is empty.</h2>
            <p style={{ color: "#647789" }}>Browse the live catalog and add products to your cart.</p>
            <Link href="/products" style={{ display: "inline-block", padding: "12px 18px", background: "#173f58", color: "#fff", borderRadius: 8, textDecoration: "none", fontWeight: 700 }}>Shop products</Link>
          </section>
        ) : (
          <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(260px, 320px)", gap: 20, alignItems: "start" }}>
            <section style={{ display: "grid", gap: 12 }}>
              {items.map((item, index) => {
                const verified = checked ? validated.find(line => line.product_id === item.product_id && line.location_id === item.location_id) : undefined;
                return (
                  <article key={item.product_id + ":" + item.location_id} style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) auto", gap: 14, padding: 18, background: "#fff", border: "1px solid #e1e6eb", borderRadius: 12 }}>
                    <div>
                      <h2 style={{ margin: "0 0 6px", fontSize: 18 }}>{item.title}</h2>
                      <p style={{ margin: 0, color: "#647789", fontSize: 12 }}>SKU: {item.sku}</p>
                      <p style={{ margin: "8px 0", color: "#173f58", fontWeight: 800 }}>{money(verified?.unit_price_cents ?? item.unit_price_cents, item.currency)} each</p>
                      {verified && <p style={{ margin: 0, color: "#24654a", fontSize: 12 }}>{verified.available_quantity} available · {verified.location_name}</p>}
                      <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 12 }}>
                        <label style={{ fontSize: 13, color: "#475765" }}>Quantity
                          <input aria-label={"Quantity for " + item.title} type="number" min={1} max={100} value={item.quantity} onChange={event => changeQuantity(index, Number(event.target.value))} style={{ display: "block", width: 84, marginTop: 4, padding: 8, border: "1px solid #cbd4dc", borderRadius: 7 }} />
                        </label>
                        <button type="button" onClick={() => remove(index)} style={{ border: 0, background: "transparent", color: "#9b3d35", cursor: "pointer", padding: 8 }}>Remove</button>
                      </div>
                    </div>
                    <strong style={{ whiteSpace: "nowrap" }}>{money((verified?.unit_price_cents ?? item.unit_price_cents) * item.quantity, item.currency)}</strong>
                  </article>
                );
              })}
            </section>
            <aside style={{ padding: 20, background: "#fff", border: "1px solid #e1e6eb", borderRadius: 12 }}>
              <h2 style={{ marginTop: 0 }}>Order summary</h2>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 12, padding: "14px 0", borderBottom: "1px solid #e8ecef" }}><span>Subtotal</span><strong>{money(subtotal, currency)}</strong></div>
              <p style={{ color: "#647789", fontSize: 12, lineHeight: 1.5 }}>Taxes and shipping are calculated after checkout details are available. Final pricing and inventory must be revalidated before payment.</p>
              {currencyMismatch && <p role="alert" style={{ color: "#9b3d35", fontSize: 13 }}>Cart items must use one currency. Remove items in other currencies before validation.</p>}
              <button type="button" disabled={busy || currencyMismatch || !items.length} onClick={validateCart} style={{ width: "100%", padding: 13, background: "#173f58", color: "#fff", border: 0, borderRadius: 8, fontWeight: 700, cursor: busy ? "wait" : "pointer", opacity: busy || currencyMismatch ? .6 : 1 }}>{busy ? "Checking inventory…" : checked ? "Refresh price & availability" : "Verify cart"}</button>
              <button type="button" disabled style={{ width: "100%", marginTop: 10, padding: 13, background: "#e8ecef", color: "#647789", border: 0, borderRadius: 8, fontWeight: 700 }}>Checkout coming after payment integration</button>
              <p style={{ margin: "12px 0 0", fontSize: 11, color: "#647789", lineHeight: 1.5 }}>No payment is collected and no inventory is reserved from this cart yet.</p>
            </aside>
          </div>
        )}
      </section>
    </main>
  );
}
