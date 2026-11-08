"use client";

import Link from "next/link";
import { useCallback, useState } from "react";
import { useCart } from "../../components/cart-provider";

type ValidatedLine = {
  product_id: string;
  location_id: string;
  quantity: number;
  title: string;
  sku: string;
  unit_price_cents: number;
  currency: string;
  location_name: string;
  line_total_cents: number;
  available_quantity: number;
  serialized_unit_id?: string;
};

function money(cents: number, currency: string) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
}

export default function CartPage() {
  const { lines, ready, count, updateQuantity, removeLine, clear } = useCart();
  const [validated, setValidated] = useState<ValidatedLine[] | null>(null);
  const [currency, setCurrency] = useState("USD");
  const [subtotal, setSubtotal] = useState(0);
  const [error, setError] = useState("");
  const [checking, setChecking] = useState(false);

  const validate = useCallback(async () => {
    if (!lines.length) return;
    setChecking(true);
    setError("");
    setValidated(null);
    try {
      const response = await fetch("/api/cart/validate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        cache: "no-store",
        body: JSON.stringify({
          items: lines.map(({ product_id, location_id, quantity, serialized_unit_id }) => ({ product_id, location_id, quantity, ...(serialized_unit_id ? { serialized_unit_id } : {}) })),
        }),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Cart validation failed.");
      setValidated(payload.items as ValidatedLine[]);
      setCurrency(payload.currency || "USD");
      setSubtotal(Number(payload.subtotal_cents || 0));
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Cart validation failed.");
    } finally {
      setChecking(false);
    }
  }, [lines]);

  const validatedByKey = new Map((validated ?? []).map((item) => [`${item.product_id}:${item.location_id}:${item.serialized_unit_id ?? "aggregate"}`, item]));

  return <main className="simple-page catalog-page">
    <header className="header">
      <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
      <nav aria-label="Shop navigation"><Link href="/products">Continue shopping</Link></nav>
      <div className="actions"><Link href="/account">Account</Link><span>Bag <span className="count">{ready ? count : 0}</span></span></div>
    </header>

    <section className="catalog-intro">
      <div className="eyebrow">Your MME bag</div>
      <h1>Good choices. <em>All together.</em></h1>
      <p>Review your selected products and pickup locations before checkout.</p>
    </section>

    <section className="cart-shell">
      {!ready && <p>Loading your saved bag…</p>}
      {ready && lines.length === 0 && <div className="catalog-empty"><div className="eyebrow">Nothing in your bag yet</div><h2>Your next great find is waiting.</h2><p>Browse the live MME catalog and add products when they are available.</p><Link className="button" href="/products">Explore products ↗</Link></div>}

      {ready && lines.length > 0 && <>
        <div className="cart-lines">
          {lines.map((line) => {
            const current = validatedByKey.get(`${line.product_id}:${line.location_id}:${line.serialized_unit_id ?? "aggregate"}`);
            return <article className="cart-line" key={`${line.product_id}:${line.location_id}`}>
              <div className="cart-line-mark">MME</div>
              <div className="cart-line-details">
                <h2>{current?.title ?? line.title}</h2>
                <p>SKU {current?.sku ?? line.sku}</p>
                <p>Location: {current?.location_name ?? line.location_name}</p>
                {line.serialized_unit_id && <p>Individual device: {line.serialized_unit_id}</p>}
                <p>{current ? money(current.unit_price_cents, current.currency) : "Price will be rechecked"}</p>
                <div className="cart-quantity">
                  <label>Quantity
                    <input type="number" min="1" max={line.serialized_unit_id ? 1 : line.available_quantity} disabled={Boolean(line.serialized_unit_id)} value={line.quantity}
                      onChange={(event) => updateQuantity(line.product_id, line.location_id, Number(event.target.value), line.serialized_unit_id)} />
                  </label>
                  <button type="button" onClick={() => removeLine(line.product_id, line.location_id, line.serialized_unit_id)}>Remove</button>
                </div>
              </div>
              <div className="cart-line-total">{current ? money(current.line_total_cents, current.currency) : "—"}</div>
            </article>;
          })}
        </div>
        <div className="cart-summary">
          <button className="text-link" type="button" onClick={clear}>Clear bag</button>
          <div className="cart-subtotal"><span>Verified subtotal</span><b>{validated ? money(subtotal, currency) : "Not yet verified"}</b></div>
          <p>Taxes, shipping and discounts are not included. Final totals are calculated during secure checkout.</p>
          {error && <p className="cart-error" role="alert">{error}</p>}
          <button className="button" type="button" disabled={checking} onClick={validate}>{checking ? "Checking current prices…" : "Verify prices & availability"}</button>
          {validated && <Link className="button" href="/checkout">Continue to secure checkout ↗</Link>}
          <p className="cart-checkout-note">Verification does not reserve inventory or charge you. Final pricing, tax, discounts and fulfillment are recalculated by MME during checkout.</p>
        </div>
      </>}
    </section>
    <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/products">Shop all</Link></footer>
  </main>;
}
