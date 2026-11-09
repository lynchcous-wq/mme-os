import { NextRequest, NextResponse } from "next/server";
import { hasSameOrigin, requireBrowserUser, supabaseConfig, setSessionCookies } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  const { user, refreshed } = await requireBrowserUser(request);
  if (!user) return NextResponse.json({ error: "Sign in is required before requesting customer account linking." }, { status: 401 });
  if (!user.email || !user.email_confirmed_at) return NextResponse.json({ error: "Verify your email before requesting customer account linking." }, { status: 403 });
  if (!hasSameOrigin(request)) {
    return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  }
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return NextResponse.json({ error: "A JSON request is required." }, { status: 415 });
  }

  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > 4096) return NextResponse.json({ error: "Request body is too large." }, { status: 413 });
  let input: { customerReference?: unknown; phoneLast4?: unknown; note?: unknown };
  try {
    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).byteLength > 4096) {
      return NextResponse.json({ error: "Request body is too large." }, { status: 413 });
    }
    input = JSON.parse(rawBody);
  } catch { return NextResponse.json({ error: "Invalid request body." }, { status: 400 }); }
  const customerReference = typeof input.customerReference === "string" ? input.customerReference.trim() : "";
  const phoneLast4 = typeof input.phoneLast4 === "string" ? input.phoneLast4.trim() : "";
  const note = typeof input.note === "string" ? input.note.trim() : "";
  if (customerReference.length > 80 || phoneLast4 && !/^\d{4}$/.test(phoneLast4) || note.length > 1000) {
    return NextResponse.json({ error: "Check the customer reference, last four phone digits, and note fields." }, { status: 400 });
  }

  try {
    const { url } = supabaseConfig();
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!serviceKey) return NextResponse.json({ error: "Customer identity review is not configured." }, { status: 503 });
    const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" };
    const pending = await fetch(`${url}/rest/v1/mme_customer_identity_link_requests?auth_user_id=eq.${encodeURIComponent(user.id)}&request_status=in.(pending,under_review)&select=request_id,request_status&limit=1`, { headers, cache: "no-store" });
    if (!pending.ok) return NextResponse.json({ error: "Customer identity review is temporarily unavailable." }, { status: 503 });
    const existing = await pending.json() as Array<{request_id:string;request_status:string}>;
    if (existing.length) {
      const response = NextResponse.json({ accepted: true, status: existing[0].request_status, message: "Your customer account-link request is already in the review queue." }, { headers: { "Cache-Control": "no-store" } });
      if (refreshed) setSessionCookies(response, refreshed);
      return response;
    }

    const inserted = await fetch(`${url}/rest/v1/mme_customer_identity_link_requests`, {
      method: "POST",
      headers: { ...headers, Prefer: "return=representation" },
      body: JSON.stringify({
        auth_user_id: user.id,
        verified_email: user.email.toLowerCase(),
        email_verified_at: user.email_confirmed_at,
        customer_reference: customerReference || null,
        contact_phone_last4: phoneLast4 || null,
        customer_note: note || null,
      }),
      cache: "no-store",
    });
    if (!inserted.ok) {
      // A concurrent duplicate pending request is treated as already accepted.
      if (inserted.status === 409) {
        const response = NextResponse.json({ accepted: true, message: "Your request is already being reviewed." }, { status: 202, headers: { "Cache-Control": "no-store" } });
        if (refreshed) setSessionCookies(response, refreshed);
        return response;
      }
      return NextResponse.json({ error: "We couldn't submit your request. Please try again later." }, { status: 503, headers: { "Cache-Control": "no-store" } });
    }
    const response = NextResponse.json({ accepted: true, message: "Your request has been submitted for MME identity review. Submission does not grant customer account access." }, { status: 202, headers: { "Cache-Control": "no-store" } });
    if (refreshed) setSessionCookies(response, refreshed);
    return response;
  } catch {
    return NextResponse.json({ error: "Customer identity review is temporarily unavailable." }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }
}
