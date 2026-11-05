"use client";

import Link from "next/link";
import { useMemo, useState } from "react";\nimport type { FormEvent } from "react";
import { Elements, PaymentElement, useElements, useStripe } from "@stripe/react-stripe-js";
import { loadStripe } from "@stripe/stripe-js";
import { useCart } from "@/components/cart-provider";
import { getSupabaseBrowserClient } from "@/lib/supabase/browser";

type FulfillmentMethod = "pickup" | "shipping";
type CheckoutIntent = {
  order_id: string;
  payment_intent_id: string;
  client_secret: string;
  amount_cents: number;
  currency: string;
  reservation_expires_at: string;
};

const publishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;
const stripePromise = publishableKey ? loadStripe(publishableKey) : null;

function money(cents: number, currency: string) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
}

function PaymentPanel({ intent, onPaymentState }: {
  intent: CheckoutIntent;
  onPaymentState: (message: string, isError?: boolean) => void;
}) {
  const stripe = useStripe();
  const elements = useElements();
  const [submitting, setSubmitting] = useState(false);

  async function submitPayment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!stripe || !elements || submitting) return;
    setSubmitting(true);
    onPaymentState("");
    try {
      const result = await stripe.confirmPayment({
        elements,
        confirmParams: {
          return_url: `${window.location.origin}/checkout/complete?order_id=${encodeURIComponent(intent.order_id)}`,
        },
        redirect: "if_required",
      });
      if (result.error) {
        onPaymentState(result.error.message || "Your payment could not be confirmed. Please review your payment details.", true);
        return;
      }
      if (result.paymentIntent?.status === "succeeded") {
        onPaymentState("Payment was accepted by Stripe. MME is verifying the payment event and finalizing your order. Do not submit another payment.");
      } else {
        onPaymentState(`Payment status: ${result.paymentIntent?.status ?? "processing"}. Your order is not marked complete until MME verifies the processor event.`);
      }
    } catch {
      onPaymentState("We could not confirm the payment response. Check your order status before trying again.", true);
    } finally {
      setSubmitting(false);
    }
  }

  return <form className="checkout-payment" onSubmit={submitPayment}>
    <PaymentElement />
    <button className="button" type="submit" disabled={!stripe || !elements || submitting}>
      {submitting ? "Confirming payment…" : "Pay securely"}
    </button>
    <p className="cart-checkout-note">Your order is finalized only after MME verifies the Stripe webhook and records the payment.</p>
  </form>;
}

export default function CheckoutPage() {
  const { lines, ready } = useCart();
  const [method, setMethod] = useState<FulfillmentMethod>("pickup");
  const [pickupLocation, setPickupLocation] = useState("");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [address1, setAddress1] = useState("");
  const [address2, setAddress2] = useState("");
  const [city, setCity] = useState("");
  const [region, setRegion] = useState("");
  const [postalCode, setPostalCode] = useState("");
  const [country, setCountry] = useState("US");
  const [intent, setIntent] = useState<CheckoutIntent | null>(null);
  const [error, setError] = useState("");
  const [paymentMessage, setPaymentMessage] = useState("");
  const [paymentMessageIsError, setPaymentMessageIsError] = useState(false);
  const [creating, setCreating] = useState(false);
  const [idempotencyKey, setIdempotencyKey] = useState("");

  const locations = useMemo(() => [...new Map(lines.map((line) => [line.location_id, line.location_name])).entries()], [lines]);

  async function createPaymentIntent(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (creating || !lines.length) return;
    setCreating(true);
    setError("");
    setPaymentMessage("");
    setIntent(null); setIdempotencyKey("");

    try {
      if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
        throw new Error("Secure checkout is not configured. Please contact MME support.");
      }
      const supabase = getSupabaseBrowserClient();
      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      const accessToken = sessionData.session?.access_token;
      if (sessionError || !accessToken) {
        throw new Error("Sign in to your MME customer account before checkout.");
      }

      const key = idempotencyKey || crypto.randomUUID();
      setIdempotencyKey(key);
      const fulfillmentDetails = method === "pickup"
        ? {
            pickup_location_id: pickupLocation || (locations.length === 1 ? locations[0][0] : ""),
            customer_name: name.trim(),
            customer_email: email.trim(),
            customer_phone: phone.trim(),
          }
        : {
            shipping_address: {
              name: name.trim(),
              email: email.trim(),
              phone: phone.trim(),
              line1: address1.trim(),
              line2: address2.trim(),
              city: city.trim(),
              state: region.trim(),
              postal_code: postalCode.trim(),
              country,
            },
          };

      const response = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/create-checkout-payment`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
          Authorization: `Bearer ${accessToken}`,
          "x-idempotency-key": key,
        },
        cache: "no-store",
        body: JSON.stringify({
          items: lines.map(({ product_id, location_id, quantity, serialized_unit_id }) => ({
            product_id,
            location_id,
            quantity,
            ...(serialized_unit_id ? { serialized_unit_id } : {}),
          })),
          fulfillment_method: method,
          fulfillment_details: fulfillmentDetails,
        }),
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(typeof payload.error === "string"
          ? payload.error.replaceAll("_", " ")
          : "Secure checkout could not prepare your order. Please try again.");
      }
      if (typeof payload.order_id !== "string" || typeof payload.client_secret !== "string" ||
          !Number.isSafeInteger(payload.amount_cents) || payload.amount_cents < 1 ||
          typeof payload.currency !== "string") {
        throw new Error("The payment service returned an incomplete order response. Contact MME support before retrying.");
      }
      setIntent(payload as CheckoutIntent);
      setIdempotencyKey(key);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Secure checkout could not be started.");
    } finally {
      setCreating(false);
    }
  }

  function handlePaymentState(message: string, isError = false) {
    setPaymentMessage(message);
    setPaymentMessageIsError(isError);
  }

  if (!ready) return <main className="simple-page catalog-page"><p>Loading your bag…</p></main>;

  return <main className="simple-page catalog-page">
    <header className="header">
      <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
      <nav aria-label="Checkout navigation"><Link href="/cart">Back to bag</Link></nav>
      <div className="actions"><Link href="/account">Account</Link></div>
    </header>

    <section className="catalog-intro">
      <div className="eyebrow">Secure MME checkout</div>
      <h1>Almost <em>yours.</em></h1>
      <p>Sign in, confirm fulfillment, and review the server-calculated total before paying.</p>
    </section>

    {!lines.length ? <section className="cart-shell"><div className="catalog-empty"><h2>Your bag is empty.</h2><Link className="button" href="/products">Explore products ↗</Link></div></section> :
      <section className="cart-shell checkout-shell">
        <div className="checkout-main">
          <form className="checkout-details" onSubmit={createPaymentIntent}>
            <h2>Fulfillment</h2>
            <label>How would you like your order?
              <select value={method} onChange={(event) => { setMethod(event.target.value as FulfillmentMethod); setIntent(null); setIdempotencyKey(""); setIdempotencyKey(""); }}>
                <option value="pickup">Local pickup</option>
                <option value="shipping">Ship to me</option>
              </select>
            </label>
            {method === "pickup" && <label>Pickup location
              <select required value={pickupLocation || (locations.length === 1 ? locations[0][0] : "")} onChange={(event) => { setPickupLocation(event.target.value); setIntent(null); setIdempotencyKey(""); setIdempotencyKey(""); }}>
                <option value="" disabled>Select a pickup location</option>
                {locations.map(([id, label]) => <option key={id} value={id}>{label}</option>)}
              </select>
            </label>}
            <h2>Contact details</h2>
            <label>Full name<input required autoComplete="name" value={name} onChange={(event) => { setName(event.target.value); setIntent(null); setIdempotencyKey(""); }} /></label>
            <label>Email<input required type="email" autoComplete="email" value={email} onChange={(event) => { setEmail(event.target.value); setIntent(null); setIdempotencyKey(""); }} /></label>
            <label>Phone<input required type="tel" autoComplete="tel" value={phone} onChange={(event) => { setPhone(event.target.value); setIntent(null); setIdempotencyKey(""); }} /></label>
            {method === "shipping" && <>
              <h2>Shipping address</h2>
              <label>Address line 1<input required autoComplete="address-line1" value={address1} onChange={(event) => { setAddress1(event.target.value); setIntent(null); setIdempotencyKey(""); }} /></label>
              <label>Address line 2 (optional)<input autoComplete="address-line2" value={address2} onChange={(event) => { setAddress2(event.target.value); setIntent(null); setIdempotencyKey(""); }} /></label>
              <div className="checkout-grid">
                <label>City<input required autoComplete="address-level2" value={city} onChange={(event) => { setCity(event.target.value); setIntent(null); setIdempotencyKey(""); }} /></label>
                <label>State<input required autoComplete="address-level1" value={region} onChange={(event) => { setRegion(event.target.value); setIntent(null); setIdempotencyKey(""); }} /></label>
                <label>ZIP code<input required autoComplete="postal-code" value={postalCode} onChange={(event) => { setPostalCode(event.target.value); setIntent(null); setIdempotencyKey(""); }} /></label>
                <label>Country<select value={country} onChange={(event) => { setCountry(event.target.value); setIntent(null); setIdempotencyKey(""); }}><option value="US">United States</option></select></label>
              </div>
            </>}
            {error && <p className="cart-error" role="alert">{error}</p>}
            {!intent && <button className="button" type="submit" disabled={creating || !lines.length}>{creating ? "Preparing secure order…" : "Review total & continue"}</button>}
            <p className="cart-checkout-note">Prices, tax, discounts, fulfillment charges, customer identity and inventory reservations are revalidated by MME servers. Browser prices are never used to charge your card.</p>
          </form>

          <aside className="checkout-summary">
            <h2>Your order</h2>
            {lines.map((line) => <div className="checkout-line" key={`${line.product_id}:${line.location_id}:${line.serialized_unit_id ?? "stock"}`}><span>{line.title} × {line.quantity}</span><small>{line.location_name}</small></div>)}
            {intent && <div className="cart-subtotal"><span>Server-calculated total</span><b>{money(intent.amount_cents, intent.currency)}</b></div>}
            {!intent && <p>Final total appears after secure server-side pricing.</p>}
            {intent && <p className="cart-checkout-note">Order reference: {intent.order_id}</p>}
          </aside>
        </div>

        {intent && <section className="checkout-payment-section">
          <h2>Payment</h2>
          {!stripePromise ? <p className="cart-error" role="alert">Card payment is not configured. MME must set the Stripe publishable key before accepting payments.</p> :
            <Elements stripe={stripePromise} options={{ clientSecret: intent.client_secret }}>
              <PaymentPanel intent={intent} onPaymentState={handlePaymentState} />
            </Elements>}
          {paymentMessage && <p className={paymentMessageIsError ? "cart-error" : "checkout-status"} role={paymentMessageIsError ? "alert" : "status"}>{paymentMessage}</p>}
        </section>}
      </section>
    }
    <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/products">Shop all</Link></footer>
  </main>;
}
