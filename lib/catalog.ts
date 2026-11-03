export type ProductCondition = "new" | "used" | "refurbished";
export type ProductCategory =
  | "televisions"
  | "computers"
  | "phones-tablets"
  | "wearables"
  | "accessories";

export type CatalogProduct = {
  id: string;
  name: string;
  category: ProductCategory;
  condition: ProductCondition;
  description: string;
  priceCents: number;
  compareAtPriceCents?: number;
  specs: string[];
  demoOnly: true;
};

// These are display fixtures only. They are not inventory, offers, or purchasable SKUs.
// Replace with approved database-backed catalog records before accepting orders.
export const demoProducts: CatalogProduct[] = [
  { id: "demo-laptop-001", name: "MacBook Air 13-inch", category: "computers", condition: "refurbished", description: "A lightweight laptop for everyday work and study.", priceCents: 74900, compareAtPriceCents: 99900, specs: ["M2 processor", "8GB memory", "256GB SSD"], demoOnly: true },
  { id: "demo-tv-001", name: "4K UHD Smart TV, 55-inch", category: "televisions", condition: "used", description: "A large-screen 4K display for streaming and entertainment.", priceCents: 32900, compareAtPriceCents: 49900, specs: ["55-inch display", "4K Ultra HD", "HDR smart platform"], demoOnly: true },
  { id: "demo-phone-001", name: "Galaxy S23, 128GB", category: "phones-tablets", condition: "used", description: "An unlocked smartphone in graphite.", priceCents: 41900, compareAtPriceCents: 69900, specs: ["128GB storage", "Unlocked", "Graphite"], demoOnly: true },
  { id: "demo-tablet-001", name: "iPad, 10th generation", category: "phones-tablets", condition: "refurbished", description: "A versatile tablet for home, work, and travel.", priceCents: 29900, compareAtPriceCents: 34900, specs: ["Wi-Fi", "64GB storage", "Blue"], demoOnly: true },
  { id: "demo-watch-001", name: "Smart Watch", category: "wearables", condition: "new", description: "A sample wearable listing for catalog layout testing.", priceCents: 12900, specs: ["Fitness tracking", "Notifications", "Demo listing"], demoOnly: true },
  { id: "demo-accessory-001", name: "Wireless Charging Pad", category: "accessories", condition: "new", description: "A sample accessory listing for catalog layout testing.", priceCents: 1900, specs: ["Wireless charging", "Compact design", "Demo listing"], demoOnly: true },
];

export const categoryLabels: Record<ProductCategory, string> = {
  televisions: "Televisions",
  computers: "Computers",
  "phones-tablets": "Phones & tablets",
  wearables: "Wearables",
  accessories: "Accessories",
};

export const conditionLabels: Record<ProductCondition, string> = {
  new: "New",
  used: "Pre-owned",
  refurbished: "Refurbished",
};

export function formatPrice(cents: number) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100);
}
