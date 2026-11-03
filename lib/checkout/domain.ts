/**
 * Build 001 checkout domain contracts.
 *
 * This module is intentionally infrastructure-free. It does not create orders,
 * reserve stock, calculate tax, or call Stripe. Those operations require trusted
 * server/database adapters and are specified in docs/BUILD-001-CHECKOUT-DOMAIN.md.
 */

export type FulfillmentChoice =
  | { method: "pickup"; locationId: string }
  | { method: "shipping"; address: ShippingAddress };

export type ShippingAddress = {
  name: string;
  line1: string;
  line2?: string;
  city: string;
  region: string;
  postalCode: string;
  countryCode: string;
};

export type CartLineRequest = {
  productId: string;
  quantity: number;
};

export type CheckoutRequest = {
  items: CartLineRequest[];
  fulfillment: FulfillmentChoice;
};

export type AuthoritativeProduct = {
  id: string;
  sku: string;
  title: string;
  unitPriceCents: number;
  currency: "USD";
  active: boolean;
  availableQuantity: number;
  serialized: boolean;
};

export type QuoteLine = {
  productId: string;
  sku: string;
  title: string;
  quantity: number;
  unitPriceCents: number;
  lineTotalCents: number;
};

export type ServerCharge = {
  /** A server-calculated amount in cents; never accept this from the browser. */
  amountCents: number;
  /** Identifier for the tax/shipping ruleset or provider calculation. */
  calculationReference: string;
};

export type CheckoutQuote = {
  currency: "USD";
  lines: QuoteLine[];
  subtotalCents: number;
  tax: ServerCharge;
  fulfillmentCharge: ServerCharge;
  totalCents: number;
};

export type CheckoutDomainErrorCode =
  | "INVALID_REQUEST"
  | "INVALID_QUANTITY"
  | "DUPLICATE_PRODUCT"
  | "PRODUCT_UNAVAILABLE"
  | "INSUFFICIENT_STOCK"
  | "INVALID_SERVER_CHARGE";

export class CheckoutDomainError extends Error {
  constructor(
    public readonly code: CheckoutDomainErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "CheckoutDomainError";
  }
}

const MAX_LINE_QUANTITY = 20;
const MAX_CART_LINES = 50;

export function parseCheckoutRequest(input: unknown): CheckoutRequest {
  if (!input || typeof input !== "object") {
    throw new CheckoutDomainError("INVALID_REQUEST", "Checkout request must be an object.");
  }

  const value = input as Record<string, unknown>;
  if (!Array.isArray(value.items) || value.items.length === 0 || value.items.length > MAX_CART_LINES) {
    throw new CheckoutDomainError("INVALID_REQUEST", "Cart must contain between 1 and 50 items.");
  }

  const seen = new Set<string>();
  const items = value.items.map((raw): CartLineRequest => {
    if (!raw || typeof raw !== "object") {
      throw new CheckoutDomainError("INVALID_REQUEST", "Each cart line must be an object.");
    }
    const line = raw as Record<string, unknown>;
    if (typeof line.productId !== "string" || !line.productId.trim()) {
      throw new CheckoutDomainError("INVALID_REQUEST", "Each cart line needs a product identifier.");
    }
    if (seen.has(line.productId)) {
      throw new CheckoutDomainError("DUPLICATE_PRODUCT", "A product may appear only once in the cart.");
    }
    seen.add(line.productId);

    if (!Number.isInteger(line.quantity) || (line.quantity as number) < 1 || (line.quantity as number) > MAX_LINE_QUANTITY) {
      throw new CheckoutDomainError("INVALID_QUANTITY", "Each quantity must be a whole number from 1 to 20.");
    }
    return { productId: line.productId, quantity: line.quantity as number };
  });

  const rawFulfillment = value.fulfillment;
  if (!rawFulfillment || typeof rawFulfillment !== "object") {
    throw new CheckoutDomainError("INVALID_REQUEST", "A fulfillment choice is required.");
  }
  const fulfillment = rawFulfillment as Record<string, unknown>;

  if (fulfillment.method === "pickup" && typeof fulfillment.locationId === "string" && fulfillment.locationId.trim()) {
    return { items, fulfillment: { method: "pickup", locationId: fulfillment.locationId } };
  }

  if (fulfillment.method === "shipping" && fulfillment.address && typeof fulfillment.address === "object") {
    const address = fulfillment.address as Record<string, unknown>;
    const required = ["name", "line1", "city", "region", "postalCode", "countryCode"] as const;
    if (required.some((key) => typeof address[key] !== "string" || !(address[key] as string).trim())) {
      throw new CheckoutDomainError("INVALID_REQUEST", "Shipping address is incomplete.");
    }
    if ((address.countryCode as string).length !== 2) {
      throw new CheckoutDomainError("INVALID_REQUEST", "Country code must be a two-letter ISO code.");
    }
    return {
      items,
      fulfillment: {
        method: "shipping",
        address: {
          name: address.name as string,
          line1: address.line1 as string,
          ...(typeof address.line2 === "string" && address.line2.trim() ? { line2: address.line2 } : {}),
          city: address.city as string,
          region: address.region as string,
          postalCode: address.postalCode as string,
          countryCode: (address.countryCode as string).toUpperCase(),
        },
      },
    };
  }

  throw new CheckoutDomainError("INVALID_REQUEST", "Choose a valid pickup location or shipping address.");
}

/**
 * Produces a quote only from authoritative server-loaded product records and
 * server-calculated tax/fulfillment charges. Browser-supplied prices are not
 * part of CheckoutRequest and cannot affect the result.
 */
export function buildCheckoutQuote(
  request: CheckoutRequest,
  products: ReadonlyMap<string, AuthoritativeProduct>,
  tax: ServerCharge,
  fulfillmentCharge: ServerCharge,
): CheckoutQuote {
  validateServerCharge(tax);
  validateServerCharge(fulfillmentCharge);

  const lines = request.items.map((item): QuoteLine => {
    const product = products.get(item.productId);
    if (!product || !product.active) {
      throw new CheckoutDomainError("PRODUCT_UNAVAILABLE", "One or more products are unavailable.");
    }
    if (!Number.isSafeInteger(product.unitPriceCents) || product.unitPriceCents < 0 || product.currency !== "USD") {
      throw new CheckoutDomainError("PRODUCT_UNAVAILABLE", "Product pricing is not valid for checkout.");
    }
    if (!Number.isInteger(product.availableQuantity) || product.availableQuantity < item.quantity) {
      throw new CheckoutDomainError("INSUFFICIENT_STOCK", "There is not enough available stock for one or more products.");
    }
    const lineTotalCents = product.unitPriceCents * item.quantity;
    if (!Number.isSafeInteger(lineTotalCents)) {
      throw new CheckoutDomainError("INVALID_SERVER_CHARGE", "Line total exceeds the supported amount.");
    }
    return {
      productId: product.id,
      sku: product.sku,
      title: product.title,
      quantity: item.quantity,
      unitPriceCents: product.unitPriceCents,
      lineTotalCents,
    };
  });

  const subtotalCents = lines.reduce((sum, line) => sum + line.lineTotalCents, 0);
  const totalCents = subtotalCents + tax.amountCents + fulfillmentCharge.amountCents;
  if (!Number.isSafeInteger(totalCents)) {
    throw new CheckoutDomainError("INVALID_SERVER_CHARGE", "Checkout total exceeds the supported amount.");
  }

  return { currency: "USD", lines, subtotalCents, tax, fulfillmentCharge, totalCents };
}

function validateServerCharge(charge: ServerCharge): void {
  if (!charge || !Number.isSafeInteger(charge.amountCents) || charge.amountCents < 0 ||
      typeof charge.calculationReference !== "string" || !charge.calculationReference.trim()) {
    throw new CheckoutDomainError("INVALID_SERVER_CHARGE", "Tax and fulfillment charges must come from a valid server calculation.");
  }
}
