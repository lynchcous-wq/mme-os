import { NextRequest, NextResponse } from "next/server";
import { enforceAuthRateLimit } from "@/lib/security/auth-rate-limit";
import { hasSameOrigin, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

const PRODUCT_INTERESTS = ["television", "computer", "phone_tablet", "wearable", "accessories", "multiple", "not_sure"] as const;
const BUDGETS = ["under_250", "250_499", "500_999", "1000_1999", "2000_plus", "not_sure"] as const;
const CONTACT_METHODS = ["email", "phone", "either"] as const;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE = /^[+()\d.\-\s]{7,32}$/;

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) {
    return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403, headers: { "Cache-Control": "no-store" } });
  }
  const limited = await enforceAuthRateLimit(request, "financing-inquiry", 5, 3600);
  if (limited) return limited;
  if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) {
    return NextResponse.json({ error: "JSON request required." }, { status: 415, headers: { "Cache-Control": "no-store" } });
  }

  try {
    const body = await request.json() as Record<string, unknown>;
    // Honeypot: silently accept bots without creating a lead.
    if (typeof body.website === "string" && body.website.trim()) {
      return NextResponse.json({ submitted: true }, { status: 202, headers: { "Cache-Control": "no-store" } });
    }

    const fullName = typeof body.fullName === "string" ? body.fullName.trim().replace(/\s+/g, " ") : "";
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const phone = typeof body.phone === "string" ? body.phone.trim() : "";
    const productInterest = body.productInterest;
    const estimatedBudget = body.estimatedBudget;
    const preferredContact = body.preferredContact;
    if (fullName.length < 2 || fullName.length > 120 ||
        email.length > 320 || !EMAIL.test(email) ||
        !PHONE.test(phone) ||
        typeof productInterest !== "string" || !PRODUCT_INTERESTS.includes(productInterest as typeof PRODUCT_INTERESTS[number]) ||
        typeof estimatedBudget !== "string" || !BUDGETS.includes(estimatedBudget as typeof BUDGETS[number]) ||
        typeof preferredContact !== "string" || !CONTACT_METHODS.includes(preferredContact as typeof CONTACT_METHODS[number]) ||
        body.consentToContact !== true) {
      return NextResponse.json({ error: "Please review the required fields and consent before submitting." }, { status: 400, headers: { "Cache-Control": "no-store" } });
    }

    const { url } = supabaseConfig();
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!serviceKey) throw new Error("Financing inquiry storage is not configured.");
    const response = await fetch(`${url}/rest/v1/mme_financing_inquiries`, {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({
        full_name: fullName,
        email,
        phone,
        product_interest: productInterest,
        estimated_budget: estimatedBudget,
        preferred_contact: preferredContact,
        consent_to_contact: true,
      }),
      cache: "no-store",
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error("Financing inquiry storage failed.");
    return NextResponse.json({
      submitted: true,
      message: "Thank you. Your financing inquiry has been received. This is not a credit application or an approval. An MME representative may contact you using your selected method.",
    }, { status: 201, headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "We could not submit your inquiry right now. Please try again later." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
