import { NextRequest, NextResponse } from "next/server";
import { getAuthUser, hasSameOrigin, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return NextResponse.json({ error: "A JSON request is required." }, { status: 415 });
  }

  let input: { tokenHash?: unknown; type?: unknown };
  try { input = await request.json(); } catch { return NextResponse.json({ error: "Invalid verification request." }, { status: 400 }); }
  const tokenHash = typeof input.tokenHash === "string" ? input.tokenHash.trim() : "";
  // This endpoint is deliberately restricted to signup email verification.
  if (input.type !== "email" || tokenHash.length < 20 || tokenHash.length > 512 || !/^[A-Za-z0-9_-]+$/.test(tokenHash)) {
    return NextResponse.json({ error: "This verification link is invalid or expired. Request a new registration email." }, { status: 400 });
  }

  try {
    const { url, anon } = supabaseConfig();
    const response = await fetch(`${url}/auth/v1/verify`, {
      method: "POST",
      headers: { apikey: anon, "Content-Type": "application/json" },
      body: JSON.stringify({ token_hash: tokenHash, type: "email" }),
      cache: "no-store",
    });
    const verified = await response.json().catch(() => ({})) as { access_token?: string; refresh_token?: string };
    if (!response.ok || typeof verified.access_token !== "string" || typeof verified.refresh_token !== "string") {
      return NextResponse.json({ error: "This verification link is invalid, expired, or already used. Request a new registration email." }, { status: 400, headers: { "Cache-Control": "no-store" } });
    }

    const user = await getAuthUser(verified.access_token);
    if (!user || !user.email_confirmed_at) {
      return NextResponse.json({ error: "Email verification could not be confirmed. Contact MME support." }, { status: 403, headers: { "Cache-Control": "no-store" } });
    }

    // Tokens are intentionally discarded. The user must sign in normally; customer identity linking remains a separate approval.
    return NextResponse.json({ verified: true, message: "Email verified. You can now sign in. Customer account access may require MME identity linking." }, {
      status: 200,
      headers: { "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" },
    });
  } catch {
    return NextResponse.json({ error: "Email verification is temporarily unavailable. Try again later." }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }
}
