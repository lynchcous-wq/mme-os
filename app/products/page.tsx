import Link from "next/link";

const categories = [
  ["Televisions", "TVs and home entertainment"],
  ["Computers", "Laptops and everyday computing"],
  ["Phones & tablets", "Stay connected"],
  ["Wearables", "Smart watches and accessories"],
  ["Accessories", "Everyday technology essentials"],
];

export const metadata = {
  title: "Explore Electronics",
  description:
    "Explore electronics categories at Much More Electronics. New, pre-loved and refurbished product listings are coming soon.",
  alternates: { canonical: "/products" },
};

export default function ProductsPage() {
  return (
    <main className="simple-page">
      <header className="header">
        <Link className="brand" href="/" aria-label="Much More Electronics home">
          <span className="brand-mark">MM</span>
          <span>MUCH MORE<br /><b>ELECTRONICS</b></span>
        </Link>
        <nav aria-label="Main navigation">
          <Link href="/">Home</Link>
          <Link href="/products" aria-current="page">Explore</Link>
          <Link href="/#why">Why MME</Link>
        </nav>
        <div className="actions">
          <Link href="/account">Account</Link>
          <Link href="/employee-sign-in">Employee sign-in</Link>
        </div>
      </header>

      <section className="simple-content">
        <div className="eyebrow">Explore Much More Electronics</div>
        <h1>Find your next <em>favorite.</em></h1>
        <p>
          Explore the kinds of technology you will find at MME. Our product
          catalog is being prepared, and listings will appear here when
          availability, pricing and product details are ready to publish.
        </p>
        <div className="catalog-category-list" aria-label="Product categories">
          {categories.map(([name, description]) => (
            <div className="catalog-category" key={name}>
              <strong>{name}</strong>
              <span>{description}</span>
            </div>
          ))}
        </div>
        <p className="catalog-status">
          <strong>Catalog update:</strong> Product listings are not yet available.
          No items are currently offered for online purchase from this page.
        </p>
        <Link className="button" href="/">Return to MME home ↗</Link>
      </section>

      <footer className="simple-footer">
        <span>© {new Date().getFullYear()} Much More Electronics</span>
        <Link href="/">Home</Link>
        <Link href="/account">Customer account</Link>
      </footer>
    </main>
  );
}
