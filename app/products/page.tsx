import Link from "next/link";
import { categoryLabels, conditionLabels, demoProducts, formatPrice, type ProductCategory, type ProductCondition } from "@/app/catalog";

type SearchParams = Promise<{ q?: string; condition?: string; category?: string }>;
const conditions = Object.keys(conditionLabels) as ProductCondition[];
const categories = Object.keys(categoryLabels) as ProductCategory[];
function isCondition(value?: string): value is ProductCondition { return !!value && conditions.includes(value as ProductCondition); }
function isCategory(value?: string): value is ProductCategory { return !!value && categories.includes(value as ProductCategory); }

export default async function ProductsPage({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  const query = (params.q ?? "").trim().slice(0, 80);
  const condition = isCondition(params.condition) ? params.condition : undefined;
  const category = isCategory(params.category) ? params.category : undefined;
  const needle = query.toLocaleLowerCase();
  const products = demoProducts.filter((product) => {
    const matchesQuery = !needle || [product.name, product.description, ...product.specs].join(" ").toLocaleLowerCase().includes(needle);
    return matchesQuery && (!condition || product.condition === condition) && (!category || product.category === category);
  });
  const hasFilters = Boolean(query || condition || category);

  return <main className="simple-page">
    <header className="header">
      <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
      <nav aria-label="Shop navigation"><Link href="/products">Shop all</Link><Link href="/#deals">Deals</Link></nav>
      <div className="actions"><Link href="/account">Account</Link><Link href="/cart">Bag <span className="count">0</span></Link></div>
    </header>
    <section className="catalog-page">
      <div className="eyebrow">Explore MME</div>
      <h1>Find your next <em>favorite.</em></h1>
      <p className="catalog-intro">Explore new, pre-owned and refurbished electronics. Product examples below are demonstration listings—not live stock or available offers.</p>
      <form className="catalog-filters" action="/products" method="get">
        <label className="catalog-search"><span>Search products</span><input type="search" name="q" maxLength={80} placeholder="Search name or specs" defaultValue={query} /></label>
        <label><span>Condition</span><select name="condition" defaultValue={condition ?? ""}><option value="">All conditions</option>{conditions.map((value) => <option key={value} value={value}>{conditionLabels[value]}</option>)}</select></label>
        <label><span>Category</span><select name="category" defaultValue={category ?? ""}><option value="">All categories</option>{categories.map((value) => <option key={value} value={value}>{categoryLabels[value]}</option>)}</select></label>
        <button type="submit">Apply filters</button>
        {hasFilters && <Link className="catalog-reset" href="/products">Clear</Link>}
      </form>
      <div className="catalog-results-heading"><h2>{hasFilters ? "Matching examples" : "Browse product examples"}</h2><span>{products.length} {products.length === 1 ? "listing" : "listings"}</span></div>
      {products.length ? <div className="catalog-grid">
        {products.map((product, index) => <article className="catalog-card" key={product.id}>
          <div className={`catalog-art catalog-art-${index % 4}`} aria-hidden="true"><span>{product.category === "televisions" ? "▱" : product.category === "computers" ? "▰" : product.category === "wearables" ? "◉" : "▯"}</span><small>DEMO LISTING</small></div>
          <div className="catalog-card-body">
            <div className="catalog-card-meta"><span>{categoryLabels[product.category]}</span><span>{conditionLabels[product.condition]}</span></div>
            <h3>{product.name}</h3><p>{product.description}</p>
            <ul>{product.specs.map((spec) => <li key={spec}>{spec}</li>)}</ul>
            <div className="catalog-price"><strong>{formatPrice(product.priceCents)}</strong>{product.compareAtPriceCents && <del>{formatPrice(product.compareAtPriceCents)}</del>}</div>
            <span className="demo-notice">Illustrative price · Not for purchase</span>
          </div>
        </article>)}
      </div> : <div className="catalog-empty"><h2>No matching examples</h2><p>Try another search or clear one of the filters.</p><Link className="button" href="/products">View all examples ↗</Link></div>}
    </section>
    <footer className="simple-footer"><span>© {new Date().getFullYear()} Much More Electronics</span><Link href="/">Home</Link></footer>
  </main>;
}
