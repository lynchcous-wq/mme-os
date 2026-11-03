"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { demoProducts, formatPrice } from "@/app/catalog";
import CartCount from "@/app/components/CartCount";

const CART_KEY = "mme-demo-cart-v1";
type CartLine = { productId: string; quantity: number };

function readCart(): CartLine[] {
  try {
    const parsed: unknown = JSON.parse(window.localStorage.getItem(CART_KEY) ?? "[]");
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((line): line is CartLine =>
      !!line &&
      typeof line === "object" &&
      typeof line.productId === "string" &&
      Number.isInteger(line.quantity) &&
      line.quantity > 0 &&
      line.quantity <= 20
    );
  } catch {
    return [];
  }
}

export default function CartPage() {
  const [lines, setLines] = useState<CartLine[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setLines(readCart());
    setReady(true);
  }, []);

  useEffect(() => {
    if (ready) {
      window.localStorage.setItem(CART_KEY, JSON.stringify(lines));
      window.dispatchEvent(new Event("mme-demo-cart-updated"));
    }
  }, [lines, ready]);

  const items = useMemo(() => lines.flatMap((line) => {
    const product = demoProducts.find((candidate) => candidate.id === line.productId);
    return product ? [{ product, quantity: line.quantity }] : [];
  }), [lines]);

  const total = items.reduce((sum, item) => sum + item.product.priceCents * item.quantity, 0);

  function changeQuantity(productId: string, quantity: number) {
    setLines((current) => quantity < 1
      ? current.filter((line) => line.productId !== productId)
      : current.map((line) => line.productId === productId ? { ...line, quantity: Math.min(quantity, 20) } : line));
  }

  function clearBag() {
    setLines([]);
  }

  return <main className="simple-page">
    <header className="header">
      <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
      <nav aria-label="Shop navigation"><Link href="/products">Shop all</Link></nav>
      <div className="actions"><Link href="/account">Account</Link><Link href="/cart">Bag <CartCount /></Link></div>
    </header>
    <section className="cart-page">
      <div className="eyebrow">Your selection</div>
      <h1>Your <em>demo bag.</em></h1>
      <p className="cart-disclaimer">This is a local demonstration cart containing sample listings only. It does not reserve inventory, create an order, or accept payment.</p>
      {!ready ? <p>Loading your bag…</p> : items.length === 0 ? <div className="catalog-empty"><h2>Your bag is empty</h2><p>Add a demonstration listing to see how the bag works.</p><Link className="button" href="/products">Browse examples ↗</Link></div> : <>
        <div className="cart-lines">{items.map(({ product, quantity }) => <article className="cart-line" key={product.id}>
          <div className="cart-line-art" aria-hidden="true">▱</div>
          <div className="cart-line-info"><strong>{product.name}</strong><span>{product.condition} · demo listing</span><small>{formatPrice(product.priceCents)} each</small></div>
          <label className="cart-quantity">Qty <input type="number" min="0" max="20" value={quantity} onChange={(event) => changeQuantity(product.id, Number(event.target.value))} /></label>
          <strong>{formatPrice(product.priceCents * quantity)}</strong>
          <button className="cart-remove" type="button" onClick={() => changeQuantity(product.id, 0)}>Remove</button>
        </article>)}</div>
        <div className="cart-summary"><span>Illustrative subtotal</span><strong>{formatPrice(total)}</strong></div>
        <p className="cart-disclaimer">No checkout is available in this build. Displayed prices are not live MME offers.</p>
        <button className="cart-clear" type="button" onClick={clearBag}>Clear demo bag</button>
      </>}
    </section>
    <footer className="simple-footer"><span>© {new Date().getFullYear()} Much More Electronics</span><Link href="/">Home</Link></footer>
  </main>;
}
