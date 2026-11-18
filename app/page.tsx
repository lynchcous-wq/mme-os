const categories = [
  { name: "Televisions", detail: "Big-screen entertainment" },
  { name: "Computers", detail: "Laptops and everyday computing" },
  { name: "Phones & tablets", detail: "Stay connected" },
  { name: "Wearables", detail: "Smart watches and more" },
  { name: "Accessories", detail: "Everyday essentials" },
  { name: "Services", detail: "Support for your technology" },
];

export default function HomePage() {
  return (
    <main>
      <div className="announcement">More tech. More value.<span>Explore electronics for every day and every budget</span></div>
      <header className="header">
        <a className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></a>
        <nav aria-label="Main navigation">
          <a href="/products?condition=new">New</a><a href="/products?condition=used">Pre-loved</a><a href="/products?condition=refurbished">Refurbished</a><a href="/products">Shop all</a><a href="/financing">Financing options</a><a href="#why">Why MME</a>
        </nav>
        <div className="actions"><a href="/account">Account</a><a href="/employee-sign-in">Employee sign-in</a></div>
      </header>

      <section className="hero">
        <div className="hero-copy">
          <div className="eyebrow">A smarter way to shop tech</div>
          <h1>More tech.<br /><em>More possibility.</em></h1>
          <p>Discover new, pre-loved and refurbished electronics. Find the technology that fits your life, your needs and your budget.</p>
          <div className="hero-actions"><a className="button" href="/products">Explore MME <span>↗</span></a><a className="text-link" href="#why">Why shop MME? →</a></div>
          <small>More choice. Thoughtful value. A better way to shop.</small>
        </div>
        <div className="hero-art" role="img" aria-label="Stylized illustration of a laptop, smartphone and smartwatch">
          <div className="sun" /><div className="laptop"><span>MAKE<br />MORE.</span></div><div className="phone">09:41</div><div className="watch">10<br />28</div><div className="float float-a">✳ &nbsp;More choice</div><div className="float float-b">↗ &nbsp;More possibility</div>
        </div>
      </section>

      <section className="benefits" aria-label="MME shopping values">
        <div>◇ &nbsp; More ways to choose <small>New, pre-loved & refurbished</small></div>
        <div>✓ &nbsp; Value matters <small>Options for different budgets</small></div>
        <div>⌂ &nbsp; Technology for life <small>Devices for work and play</small></div>
        <div>♡ &nbsp; Here to help <small>Explore MME and get in touch</small></div>
      </section>

      <section className="section" aria-labelledby="categories-title">
        <div className="section-heading"><div><div className="eyebrow">A whole lot to explore</div><h2 id="categories-title">Find your next <em>favorite.</em></h2></div><a className="text-link" href="/products">Explore the catalog →</a></div>
        <div className="categories">
          {categories.map((category, i) => <a href="/products" className="category" key={category.name}><span className="category-icon">{["▣", "⌘", "▤", "◉", "⌁", "+"][i]}</span><b>{category.name}</b><small>{category.detail}</small><span className="arrow">↗</span></a>)}
        </div>
      </section>

      <section className="deals" id="explore">
        <div className="section">
          <div className="section-heading"><div><div className="eyebrow">The MME experience</div><h2>More than a <em>device.</em></h2></div><a className="text-link" href="/products">Explore MME →</a></div>
          <div className="products">
            <article className="product"><div className="product-image peach"><span className="product-art">▰</span></div><div className="product-info"><small>COMPUTERS</small><b>Laptops & computers</b><span>Tools for work, school and creativity.</span></div></article>
            <article className="product"><div className="product-image lilac"><span className="product-art">▱</span></div><div className="product-info"><small>TELEVISIONS</small><b>TVs & entertainment</b><span>Bring more of what you love to the screen.</span></div></article>
            <article className="product"><div className="product-image mint"><span className="product-art">▯</span></div><div className="product-info"><small>PHONES</small><b>Phones & tablets</b><span>Stay connected wherever life takes you.</span></div></article>
            <article className="product"><div className="product-image blue"><span className="product-art">◉</span></div><div className="product-info"><small>ACCESSORIES</small><b>Accessories & more</b><span>Discover the extras that make tech yours.</span></div></article>
          </div>
          <p className="catalog-note">Product availability, specifications and pricing will appear in the catalog as listings become available.</p>
        </div>
      </section>

      <section className="values section" id="why">
        <div><div className="eyebrow">More for your money</div><h2>Good tech should<br />go <em>further.</em></h2><p>We believe getting the technology you want should come with choices. Explore new, pre-loved and refurbished options as the MME catalog grows.</p><a className="button" href="/products">Explore the catalog ↗</a></div>
        <div className="value-cards"><article><small>01</small><span>✳</span><h3>More ways<br />to choose.</h3><p>Explore different device conditions and find the option that works for you.</p></article><article><small>02</small><span>↗</span><h3>More value<br />in every choice.</h3><p>Technology should fit your needs and your budget.</p></article></div>
      </section>

      <section className="newsletter"><div><div className="eyebrow">Stay connected</div><h2>More good things. <em>Coming soon.</em></h2><p>We're preparing more ways to discover MME news, new arrivals and special offers.</p></div><a className="button" href="/account">Visit your account ↗</a></section>

      <footer>
        <div className="footer-grid">
          <div><a className="brand inverse" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></a><p>More tech. More value.<br />A better way to explore electronics.</p></div>
          <div><b>Explore</b><a href="/products">Shop all</a><a href="/products?condition=new">New electronics</a><a href="/products?condition=used">Pre-loved</a><a href="/products?condition=refurbished">Refurbished</a></div>
          <div><b>Your account</b><a href="/account">Customer account</a><a href="/financing">Financing inquiry</a><a href="/employee-sign-in">Employee sign-in</a></div>
          <div><b>Discover MME</b><a href="#why">Why MME</a><a href="#explore">What we offer</a><a href="/products">Explore catalog</a></div>
        </div>
        <div className="footer-bottom"><span>© {new Date().getFullYear()} Much More Electronics</span><span>Product availability and services may vary.</span><span>Made for more.</span></div>
      </footer>
    </main>
  );
}
