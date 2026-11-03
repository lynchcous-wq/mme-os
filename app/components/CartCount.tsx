"use client";
import { useEffect, useState } from "react";
const CART_KEY = "mme-demo-cart-v1";
const EVENT_NAME = "mme-demo-cart-updated";
function countItems() {
  try {
    const parsed: unknown = JSON.parse(window.localStorage.getItem(CART_KEY) ?? "[]");
    return Array.isArray(parsed) ? parsed.reduce<number>((sum, line: unknown) => {
      if (typeof line !== "object" || line === null || !("quantity" in line)) return sum;
      const quantity = line.quantity;
      return typeof quantity === "number" && Number.isInteger(quantity) && quantity > 0
        ? sum + Math.min(quantity, 20) : sum;
    }, 0) : 0;
  } catch { return 0; }
}
export default function CartCount() {
  const [count, setCount] = useState(0);
  useEffect(() => {
    const refresh = () => setCount(countItems());
    refresh();
    window.addEventListener(EVENT_NAME, refresh);
    window.addEventListener("storage", refresh);
    return () => { window.removeEventListener(EVENT_NAME, refresh); window.removeEventListener("storage", refresh); };
  }, []);
  return <span className="count" aria-label={`${count} items in bag`}>{count}</span>;
}
