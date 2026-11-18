export type FinancingProvider = {
  providerKey: string;
  name: string;
  model: string;
  products: string[];
  merchantUrl: string;
  requirements: string[];
  approval: string;
  fees: string;
  integrations: string[];
  eligibility: "electronics_supported" | "category_review" | "channel_dependent";
  readinessNote: string;
  customerApplicationUrl: null;
};

export const financingProviders: FinancingProvider[] = [
  {
    providerKey: "synchrony",
    name: "Synchrony",
    model: "Private-label / co-branded revolving credit cards and installment loans",
    products: ["Store credit card", "Promotional financing", "Installment loans"],
    merchantUrl: "https://www.synchrony.com/business/partner-with-us",
    requirements: ["Merchant application and industry review", "Business and ownership details", "Store / website information", "Banking and settlement setup after approval"],
    approval: "Synchrony underwrites each consumer application and returns the decision and available offer. MME must not make or override the credit decision.",
    fees: "No partner application fee is publicly stated. Merchant pricing depends on the selected financing promotions and negotiated program terms; request a written schedule.",
    integrations: ["Synchrony Business Center / hosted workflow", "Apply & Buy APIs for approved ISV / direct integration partners", "In-store and ecommerce application flows"],
    eligibility: "electronics_supported",
    readinessNote: "Electronics retail is a relevant category, but MME approval, used/refurbished inventory acceptance, promotional pricing and integration access require written confirmation.",
    customerApplicationUrl: null,
  },
  {
    providerKey: "bread-pay",
    name: "Bread Pay (Bread Financial)",
    model: "Installment loans / pay-over-time financing",
    products: ["Short- and long-term installment plans", "Merchant-funded promotional programs where offered"],
    merchantUrl: "https://www.breadfinancial.com/",
    requirements: ["Contact Bread Pay sales for merchant onboarding", "Business, website, product and ownership review", "Underwriting and commercial agreement", "Required lending disclosures and marketing approval before launch"],
    approval: "Bread Pay's bank / lending partners underwrite applications and issue the actual terms and decisions. Product availability and term length depend on the signed program.",
    fees: "Merchant discount and program costs are contract-specific. Some promotional loan programs may require additional merchant-funded costs. No universal public MME rate is available.",
    integrations: ["Direct merchant / platform API subject to approval", "Embedded lending through ChargeAfter network", "Hosted application and checkout flows subject to contract"],
    eligibility: "category_review",
    readinessNote: "Consumer electronics fit must be confirmed with Bread Pay. ChargeAfter publicly announced Bread Pay in its lender network; confirm current availability and merchant terms.",
    customerApplicationUrl: null,
  },
  {
    providerKey: "citi",
    name: "Citi Retail Services",
    model: "Private-label and co-branded retail credit cards",
    products: ["Retail credit card", "Promotional financing", "Online / in-store Apply & Buy where enabled"],
    merchantUrl: "https://partner.citi.com/products/credit-cards",
    requirements: ["Commercial partnership / portfolio review", "Retail category and scale assessment", "Program sponsor or channel requirements may apply", "Written issuer approval and operating agreement"],
    approval: "Citi and its issuing bank program determine consumer credit approval, credit line and terms. Approval messaging must be returned from the issuer integration.",
    fees: "Merchant economics are negotiated and program-specific; public standard MDR, subsidy or servicing rates are not published.",
    integrations: ["Citi Apply & Buy where merchant program supports it", "Online and in-store application experience", "Partner / program integration"],
    eligibility: "channel_dependent",
    readinessNote: "Citi advertises consumer-electronics card programs through selected retail channels such as BrandSource. MME must confirm direct eligibility or any required buying-group affiliation.",
    customerApplicationUrl: null,
  },
  {
    providerKey: "affirm",
    name: "Affirm",
    model: "Pay-over-time installment financing",
    products: ["Pay in 4 where offered", "Monthly installment loans", "Promotional APR programs subject to offer"],
    merchantUrl: "https://www.affirm.com/business/",
    requirements: ["US-facing English-language website", "USD pricing and US bank account", "Business and prohibited-category review", "Fully live website and supported ecommerce platform are required for partnership review"],
    approval: "Affirm and its lending partners make real-time consumer eligibility, offer, APR and term decisions. The exact offer is customer- and transaction-specific.",
    fees: "Merchant discount rate plus per-transaction fee. Exact pricing depends on program, business size and risk profile. Affirm states no integration, annual or monthly fee; obtain the merchant-specific rate card.",
    integrations: ["Supported ecommerce platform / PSP integration", "Affirm API and checkout components", "In-store / telesales flows where enabled"],
    eligibility: "electronics_supported",
    readinessNote: "Electronics are not automatically approved. Affirm says a fully live website is required; MME checkout is currently marked not open, so this is a launch-readiness blocker.",
    customerApplicationUrl: null,
  },
  {
    providerKey: "klarna",
    name: "Klarna",
    model: "BNPL and installment financing",
    products: ["Pay in 4 / Pay in 3 where offered", "Pay later", "Longer-term financing where enabled", "Pay in full"],
    merchantUrl: "https://www.klarna.com/us/business/",
    requirements: ["Merchant onboarding and risk review", "Eligible product/category and country review", "Merchant agreement and bank settlement setup", "Approved messaging and disclosure implementation"],
    approval: "Klarna's consumer risk and credit processes determine eligibility and available payment programs. Product availability varies by merchant, market and customer.",
    fees: "Merchant pricing is negotiated and depends on merchant agreement, payment product and integration/acquirer. Do not display an estimated fee as a quote.",
    integrations: ["Direct Klarna Payments API / hosted redirect or inline widget", "PSP/acquirer integrations", "Klarna Partner Portal and account configuration"],
    eligibility: "category_review",
    readinessNote: "Electronics category and used/refurbished product eligibility require direct underwriting confirmation. Some PSP routes may simplify integration; confirm US merchant availability.",
    customerApplicationUrl: null,
  },
  {
    providerKey: "paypal-pay-later",
    name: "PayPal Pay Later",
    model: "BNPL installments and monthly financing",
    products: ["Pay in 4: $10–$2,000 purchase range", "Pay Monthly: $49–$10,000 purchase range; 3, 6, 12 or 24 monthly payments"],
    merchantUrl: "https://www.paypal.com/us/business/accept-payments/installment-payments",
    requirements: ["US-based PayPal merchant", "US-facing website and USD transactions", "Eligible PayPal one-time payment integration", "Compliance with PayPal Pay Later messaging and program terms"],
    approval: "PayPal / its lending partners decide Pay Monthly eligibility and terms. Pay in 4 is subject to PayPal's eligibility and transaction checks. MME receives payment confirmation, not the customer's underwriting data.",
    fees: "PayPal currently publishes a standard domestic Pay Later merchant rate of 4.99% + $0.49 per transaction, subject to change; custom pricing may be available for established high-volume merchants. No monthly or setup fee is listed.",
    integrations: ["PayPal Checkout / JavaScript SDK", "Supported ecommerce platforms", "Pay Later messaging components on eligible pages"],
    eligibility: "category_review",
    readinessNote: "Potentially the clearest published public pricing reference. Confirm MME's used/refurbished electronics eligibility and account enablement before presenting Pay Later at checkout.",
    customerApplicationUrl: null,
  },
  {
    providerKey: "acima",
    name: "Acima",
    model: "Lease-to-own plus Acima Private Credit option",
    products: ["Lease-to-own", "Private Credit option where approved"],
    merchantUrl: "https://www.acima.com/en/partner",
    requirements: ["Retailer partnership and product eligibility review", "In-store and/or ecommerce integration review", "Delivery / pickup and merchant settlement workflow", "Customer disclosures and signed lease or credit agreement"],
    approval: "Acima evaluates multiple data points and may consider a customer for its private credit product and/or lease-to-own. Decision and product path are determined by Acima, not MME.",
    fees: "Merchant settlement, discount and program costs are contract-specific. Customer lease total cost can exceed the cash price; show the provider's full lease disclosures and purchase options.",
    integrations: ["Acima ecommerce integration", "In-store application / Acima app", "Merchant reporting and settlement reconciliation"],
    eligibility: "electronics_supported",
    readinessNote: "Acima lists electronics and online/in-store integration. Confirm exact MME product eligibility, refurbished-device rules, delivery and settlement terms.",
    customerApplicationUrl: null,
  },
  {
    providerKey: "snap-finance",
    name: "Snap Finance",
    model: "Lease-to-own, installment loans and retail installment contracts",
    products: ["Lease-to-own", "Installment loan options", "Retail installment contracts"],
    merchantUrl: "https://snapfinance.com/partner",
    requirements: ["US business in an approved retail category", "Physical storefront or customer-facing location", "Products sold in-store or through connected ecommerce", "Merchant underwriting and signed agreement"],
    approval: "Snap and its financing partners make consumer decisions and present available offers. Not all applicants are approved; do not characterize it as guaranteed or no-credit-check financing.",
    fees: "Merchant fees and settlement terms are contract-specific and not publicly quoted as a universal rate. Obtain complete merchant pricing and recourse terms.",
    integrations: ["Snap merchant portal", "Text-to-apply / QR in-store flows", "Snap ecommerce developer APIs and plugins"],
    eligibility: "electronics_supported",
    readinessNote: "Snap lists TVs, laptops, home audio, tablets and computers as target categories and requires a physical customer-facing location. Confirm Mableton storefront readiness and refurbished-product rules.",
    customerApplicationUrl: null,
  },
];
