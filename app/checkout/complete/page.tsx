import Link from "next/link";

export default async function CheckoutCompletePage({
  searchParams,
}: {
  searchParams: Promise<{ order_id?: string }>;
}) {
  const { order_id: orderId } = await searchParams;
  const safeOrderReference = typeof orderId === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(orderId)
      ? orderId
      : null;

  return <main className="simple-page catalog-page">
    <header className="header">
      <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
      <nav aria-label="Order navigation"><Link href="/account">My account</Link></nav>
    </header>
    <section className="catalog-intro">
      <div className="eyebrow">Payment response received</div>
      <h1>We’re checking <em>your order.</em></h1>
      <p>A return from the payment provider is not, by itself, proof that an order is paid.</p>
    </section>
    <section className="cart-shell">
      <div className="checkout-status" role="status">
        MME must verify the signed payment-provider event and update the order before it is treated as complete. Please do not submit another payment while the status is being reconciled.
      </div>
      {safeOrderReference && <p className="cart-checkout-note">Order reference: {safeOrderReference}</p>}
      <p>Check your customer account or contact MME support if the order status does not update.</p>
      <Link className="button" href="/account">View my account ↗</Link>
    </section>
    <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/products">Shop all</Link></footer>
  </main>;
}
