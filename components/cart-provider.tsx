"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";

export type CartLine = {
  product_id: string;
  location_id: string;
  quantity: number;
  title: string;
  sku: string;
  price_cents: number;
  currency: string;
  location_name: string;
  available_quantity: number;
};

type CartContextValue = {
  lines: CartLine[];
  ready: boolean;
  count: number;
  addLine: (line: CartLine) => void;
  updateQuantity: (productId: string, locationId: string, quantity: number) => void;
  removeLine: (productId: string, locationId: string) => void;
  clear: () => void;
};

const STORAGE_KEY = "mme-cart-v1";
const CartContext = createContext<CartContextValue | null>(null);

export function CartProvider({ children }: { children: React.ReactNode }) {
  const [lines, setLines] = useState<CartLine[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    try {
      const saved = window.localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const parsed = JSON.parse(saved) as CartLine[];
        if (Array.isArray(parsed)) setLines(parsed.filter((line) =>
          typeof line.product_id === "string" &&
          typeof line.location_id === "string" &&
          Number.isInteger(line.quantity) && line.quantity > 0
        ));
      }
    } catch {
      window.localStorage.removeItem(STORAGE_KEY);
    }
    setReady(true);
  }, []);

  useEffect(() => {
    if (ready) window.localStorage.setItem(STORAGE_KEY, JSON.stringify(lines));
  }, [lines, ready]);

  const addLine = useCallback((line: CartLine) => {
    setLines((current) => {
      const existing = current.find((item) => item.product_id === line.product_id && item.location_id === line.location_id);
      if (!existing) return [...current, line];
      return current.map((item) => item === existing
        ? { ...item, quantity: Math.min(item.available_quantity, item.quantity + line.quantity) }
        : item);
    });
  }, []);

  const updateQuantity = useCallback((productId: string, locationId: string, quantity: number) => {
    setLines((current) => current.map((line) =>
      line.product_id === productId && line.location_id === locationId
        ? { ...line, quantity: Math.max(1, Math.min(line.available_quantity, Math.floor(quantity) || 1)) }
        : line
    ));
  }, []);

  const removeLine = useCallback((productId: string, locationId: string) => {
    setLines((current) => current.filter((line) => !(line.product_id === productId && line.location_id === locationId)));
  }, []);

  const clear = useCallback(() => setLines([]), []);
  const count = lines.reduce((total, line) => total + line.quantity, 0);
  const value = useMemo(() => ({ lines, ready, count, addLine, updateQuantity, removeLine, clear }), [lines, ready, count, addLine, updateQuantity, removeLine, clear]);

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export function useCart() {
  const value = useContext(CartContext);
  if (!value) throw new Error("useCart must be used inside CartProvider");
  return value;
}
