"use client";

import { useState } from "react";
import type { CatalogProduct } from "@/app/catalog";

const CART_KEY = "mme-demo-cart-v1";
const EVENT_NAME = "mme-demo-cart-updated";

type CartLine = { productId: string; quantity: number };

export default function AddToCartButton({ product }: { product: CatalogProduct }) {
  const [added, setAdded] = useState(false);

  function addToBag() {
    try {
      const raw = window.localStorage.getItem(CART_KEY);
      const parsed: unknown = raw ? JSON.parse(raw) : [];
      const lines: CartLine[] = Array.isArray(parsed)
        ? parsed.filter((line): line is CartLine =>
            !!line &&
            typeof line === "object" &&
            typeof line.productId === "string" &&
            Number.isInteger(line.quantity) &&
            line.quantity > 0
          )
        : [];
      const existing = lines.find((line) => line.productId === product.id);
      if (existing) existing.quantity = Math.min(existing.quantity + 1, 20);
      else lines.push({ productId: product.id, quantity: 1 });
      window.localStorage.setItem(CART_KEY, JSON.stringify(lines));
      window.dispatchEvent(new Event(EVENT_NAME));
      setAdded(true);
      window.setTimeout(() => setAdded(false), 1600);
    } catch {
      setAdded(false);
    }
  }

  return <button className="catalog-add-button" type="button" onClick={addToBag}>
    {added ? "Added to demo bag" : "Add to demo bag"}
  </button>;
}
