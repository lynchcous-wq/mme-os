"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/browser";

type Order = {
  id: string; status: string; currency: string; subtotal_cents: number;
  tax_cents: number; fulfillment_cents: number; discount_cents: number;
  total_cents: number; fulfillment_method: "shipping" | "pickup";
  created_at: string; updated_at: string;
  fulfillment: null | {
    status: string; carrier: string | null; tracking_number: string | null;
    tracking_url: string | null; pickup_ready_at: string | null;
    pickup_completed_at: string | null; pickup_location_id: string | null;
  };
  items: Array<{ title: string; sku: string; condition: string; quantity: number; unit_price_cents: number; line_total_cents: number }>;
};

const money = (cents: number, currency: string) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
const label = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());

export default function AccountPage() {
  const [email, setEmail] = useState("");
  const [sending, setSending] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [signedIn, setSignedIn] = useState(false);
  const [loading, setLoading] = useState(true);
  const [orders, setOrders] = useState<Order[]>([]);

  const loadOrders = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const supabase = getSupabaseBrowserClient();
      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      if (!sessionData.session) {
        setSignedIn(false);
        setOrders([]);
        return;
      }
      setSignedIn(true);
      const { data, error: historyError } = await supabase.rpc("mme_get_my_order_history");
      if (historyError) throw historyError;
      setOrders(Array.isArray(data) ? data as Order[] : []);
    } catch {
      setError("We couldn't load your order history. Please refresh or contact MME support.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadOrders();
    const supabase = getSupabaseBrowserClient();
    const { data: listener } = supabase.auth.onAuthStateChange(() => { queueMicrotask(() => { void loadOrders(); }); });
    return () => listener.subscription.unsubscribe();
  }, [loadOrders]);

  async function sendSignInLink(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSending(true);
    setError("");
    setMessage("");
    try {
      const supabase = getSupabaseBrowserClient();
      const { error: signInError } = await supabase.auth.signInWithOtp({
        email: email.trim(),
        options: { shouldCreateUser: false, emailRedirectTo: window.location.origin + "/account" },
      });
      if (signInError) throw signInError;
      setMessage("If this email belongs to an active MME customer account, a secure sign-in link has been sent.");
    } catch {
      setError("We couldn't send a sign-in link. Check the email address or contact MME support.");
    } finally {
      setSending(false);
    }
  }

  return <main className="simple-page catalog-page">
    <header className="header">
      <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
      <nav aria-label="Account navigation"><Link href="/products">Shop all</Link></nav>
      <div className="actions"><Link href="/cart">Bag</Link></div>
    </header>
    <section className="catalog-intro">
      <div className="eyebrow">Your MME</div>
      <h1>My <em>orders.</em></h1>
      <p>Track purchases, shipping progress and local pickup from one place.</p>
    </section>
    <section className="cart-shell">
      {loading ? <p role="status">Loading your secure account…</p> : !signedIn ? <>
        <h2>Sign in to your account</h2>
        <p>Enter the email address connected to your MME customer account. We’ll send a secure sign-in link.</p>
        <form className="checkout-details" onSubmit={sendSignInLink}>
          <label>Email address<input type="email" autoComplete="email" required value={email} onChange={(event) => setEmail(event.target.value)} /></label>
          <button className="button" type="submit" disabled={sending}>{sending ? "Sending secure link…" : "Email me a sign-in link"}</button>
        </form>
      </> : <>
        <div className="row" style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:"1rem"}}>
          <h2>Order history</h2>
          <button className="button button-secondary" type="button" onClick={() => void loadOrders()}>Refresh</button>
        </div>
        {orders.length === 0 ? <div className="catalog-empty"><h2>No orders yet.</h2><p>When you make a purchase, your order details and fulfillment updates will appear here.</p><Link className="button" href="/products">Explore products ↗</Link></div> :
          <div className="order-history-list">
            {orders.map((order) => {
              const trackingUrl = order.fulfillment?.tracking_url?.startsWith("https://") ? order.fulfillment.tracking_url : null;
              return <article className="order-history-card" key={order.id}>
                <div className="order-history-heading">
                  <div><div className="eyebrow">Order {order.id.slice(0, 8).toUpperCase()}</div><h3>{label(order.status)}</h3><p>{new Date(order.created_at).toLocaleString()}</p></div>
                  <strong>{money(order.total_cents, order.currency)}</strong>
                </div>
                <div className="order-history-lines">
                  {order.items.map((item, index) => <div className="checkout-line" key={item.sku + ":" + index}><span>{item.title} × {item.quantity}</span><small>{money(item.line_total_cents, order.currency)}</small></div>)}
                </div>
                <div className="order-history-fulfillment">
                  <p><strong>{order.fulfillment_method === "pickup" ? "Local pickup" : "Shipping"}</strong> · {order.fulfillment ? label(order.fulfillment.status) : "Preparing fulfillment"}</p>
                  {order.fulfillment?.tracking_number && <p>Tracking: {order.fulfillment.tracking_number}</p>}
                  {trackingUrl && <a href={trackingUrl} target="_blank" rel="noopener noreferrer">Track shipment ↗</a>}
                  {order.fulfillment?.pickup_ready_at && <p>Ready for pickup: {new Date(order.fulfillment.pickup_ready_at).toLocaleString()}</p>}
                  {order.fulfillment?.pickup_completed_at && <p>Pickup completed: {new Date(order.fulfillment.pickup_completed_at).toLocaleString()}</p>}
                </div>
              </article>;
            })}
          </div>}
      </>}
      {message && <p className="checkout-status" role="status">{message}</p>}
      {error && <p className="cart-error" role="alert">{error}</p>}
    </section>
    <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/">Home</Link></footer>
  </main>;
}
