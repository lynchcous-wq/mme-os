"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { useCart } from "../../../components/cart-provider";

type ProductDetail = {
  id: string;
  sku: string;
  title: string;
  description: string | null;
  brand: string | null;
  manufacturer: string | null;
  model_number: string | null;
  upc_ean: string | null;
  category_key: string | null;
  condition: string;
  inventory_condition_grade: string;
  tracking_mode: string;
  serialized: boolean;
  specifications: Record<string, unknown>;
  warranty_summary: string | null;
  price_cents: number;
  currency: string;
  availability: Array<{
    location_id: string;
    location_code: string;
    location_name: string;
    available_quantity: number;
  }>;
  available_quantity: number;
  media: Array<{
    id: string;
    media_type: string;
    storage_key: string | null;
    external_url: string | null;
    alt_text: string | null;
    is_primary: boolean;
  }>;
};

function money(cents: number, currency: string) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
}

function label(value: string) {
  return value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function displayValue(value: unknown): string {
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") return String(value);
  if (value === null || value === undefined) return "";
  return JSON.stringify(value);
}

export default function ProductDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params.id;
  const [product, setProduct] = useState<ProductDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [selectedLocation, setSelectedLocation] = useState("");
  const [quantity, setQuantity] = useState(1);
  const [added, setAdded] = useState(false);
  const { addLine, count } = useCart();

  useEffect(() => {
    let active = true;
    fetch(`/api/catalog/${encodeURIComponent(id)}`, { cache: "no-store" })
      .then(async (response) => {
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || "Product details are unavailable.");
        return payload as { product: ProductDetail };
      })
      .then((payload) => { if (active) { setProduct(payload.product); setSelectedLocation(payload.product.availability.find((item) => item.available_quantity > 0)?.location_id ?? ""); } })
      .catch((reason: unknown) => {
        if (active) setError(reason instanceof Error ? reason.message : "Product details are unavailable.");
      })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [id]);

  return <main className="simple-page catalog-page">
    <header className="header">
      <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
      <nav aria-label="Shop navigation"><Link href="/products">Shop all</Link></nav>
      <div className="actions"><Link href="/account">Account</Link><Link href="/cart">Bag <span className="count">0</span></Link></div>
    </header>

    <div className="product-detail-back"><Link href="/products">← Back to all products</Link></div>

    {loading && <section className="catalog-empty"><div className="eyebrow">MME catalog</div><h1>Loading product details.</h1><p>Checking current price, specifications and store availability.</p></section>}
    {!loading && error && <section className="catalog-empty"><div className="eyebrow">Product unavailable</div><h1>We couldn’t load this product.</h1><p>{error}</p><Link className="button" href="/products">Browse products ↗</Link></section>}

    {!loading && product && <section className="product-detail">
      <div className="product-detail-media">
        {product.media.filter((item) => item.media_type === "image" && item.external_url).length > 0
          ? product.media.filter((item) => item.media_type === "image" && item.external_url).map((item) =>
            <img key={item.id} src={item.external_url ?? ""} alt={item.alt_text || product.title} />)
          : <div className="product-detail-placeholder"><span>MME</span><b>Product image coming soon</b></div>}
      </div>
      <div className="product-detail-copy">
        <div className="eyebrow">{product.category_key || "Electronics"} · {label(product.condition)}</div>
        <h1>{product.title}</h1>
        {product.brand && <p className="product-detail-brand">{product.brand}{product.model_number ? ` · ${product.model_number}` : ""}</p>}
        <div className="product-detail-price">{money(product.price_cents, product.currency)}</div>
        <p className={product.available_quantity > 0 ? "live-stock" : "live-stock unavailable"}>
          {product.available_quantity > 0 ? `${product.available_quantity} currently available` : "Currently unavailable"}
        </p>
        {product.description && <p className="product-detail-description">{product.description}</p>}
        <div className="product-detail-meta">
          <div><span>Condition</span><b>{label(product.condition)}</b></div>
          <div><span>Inventory grade</span><b>{label(product.inventory_condition_grade)}</b></div>
          <div><span>SKU</span><b>{product.sku}</b></div>
          {product.manufacturer && <div><span>Manufacturer</span><b>{product.manufacturer}</b></div>}
          {product.model_number && <div><span>Model</span><b>{product.model_number}</b></div>}
          {product.upc_ean && <div><span>UPC / EAN</span><b>{product.upc_ean}</b></div>}
        </div>
        {product.warranty_summary && <section className="product-detail-section"><h2>Warranty</h2><p>{product.warranty_summary}</p></section>}
        <section className="product-detail-section"><h2>Store availability</h2>
          {product.availability.length === 0
            ? <p>Store-level availability is not currently listed.</p>
            : <ul className="product-location-list">{product.availability.map((item) => <li key={item.location_id}><span>{item.location_name}</span><b>{item.available_quantity > 0 ? `${item.available_quantity} available` : "Unavailable"}</b></li>)}</ul>}
        </section>
        <section className="product-detail-section"><h2>Specifications</h2>
          {Object.keys(product.specifications).length === 0
            ? <p>Specifications will be added as product details are completed.</p>
            : <dl className="product-specifications">{Object.entries(product.specifications).map(([key, value]) => <div key={key}><dt>{label(key)}</dt><dd>{displayValue(value)}</dd></div>)}</dl>}
        </section>
        {product.available_quantity > 0 && !product.serialized && <section className="product-detail-section cart-add-panel">
          <h2>Add to your bag</h2>
          <label className="cart-select-label">Pickup / fulfillment location
            <select value={selectedLocation} onChange={(event) => { setSelectedLocation(event.target.value); setAdded(false); }}>
              <option value="">Choose an available location</option>
              {product.availability.filter((item) => item.available_quantity > 0).map((item) => <option key={item.location_id} value={item.location_id}>{item.location_name} · {item.available_quantity} available</option>)}
            </select>
          </label>
          <label className="cart-select-label">Quantity
            <input type="number" min="1" max={product.availability.find((item) => item.location_id === selectedLocation)?.available_quantity ?? 1} value={quantity}
              onChange={(event) => { setQuantity(Math.max(1, Math.min(Number(event.target.value) || 1, product.availability.find((item) => item.location_id === selectedLocation)?.available_quantity ?? 1))); setAdded(false); }} />
          </label>
          <button className="button" type="button" disabled={!selectedLocation} onClick={() => {
            const location = product.availability.find((item) => item.location_id === selectedLocation);
            if (!location || location.available_quantity < quantity) return;
            addLine({ product_id: product.id, location_id: location.location_id, quantity, title: product.title, sku: product.sku, price_cents: product.price_cents, currency: product.currency, location_name: location.location_name, available_quantity: location.available_quantity });
            setAdded(true);
          }}>Add to bag</button>
          {added && <p className="cart-added-message" role="status">Added to your bag. <Link href="/cart">View bag ({count})</Link></p>}
        </section>}
        {product.available_quantity === 0 && <button className="catalog-disabled-button" type="button" disabled>Currently unavailable</button>}
        {product.available_quantity > 0 && product.serialized && <section className="product-detail-section"><h2>Individual device verification required</h2><p>This item is tracked by serial number or IMEI. It cannot be added to the standard quantity-based bag until its individual unit record and device checks are verified.</p><button className="catalog-disabled-button" type="button" disabled>Individual device checkout coming soon</button></section>}
        <p className="product-detail-note">Adding to your bag does not reserve inventory or charge you. Current price and availability are rechecked before checkout.</p>
      </div>
    </section>}

    <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/products">Shop all</Link></footer>
  </main>;
}
