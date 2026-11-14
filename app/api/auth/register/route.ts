import { NextRequest, NextResponse } from "next/server";
import { hasSameOrigin, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

type SignupResponse = { user?: { id?: string; email?: string; identities?: unknown[] | null }; session?: unknown; msg?: string; message?: string };

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return NextResponse.json({ error: "A JSON request is required." }, { status: 415 });
  }

  let input: { email?: unknown; password?: unknown; fullName?: unknown };
  try { input = await request.json(); } catch { return NextResponse.json({ error: "Invalid request body." }, { status: 400 }); }

  const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
  const password = typeof input.password === "string" ? input.password : "";
  const fullName = typeof input.fullName === "string" ? input.fullName.trim() : "";
  if (email.length > 320 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
  }
  if (password.length < 12 || password.length > 128) {
    return NextResponse.json({ error: "Use a password between 12 and 128 characters." }, { status: 400 });
  }
  if (fullName.length < 1 || fullName.length > 120 || /[\u0000-\u001f\u007f]/.test(fullName)) {
    return NextResponse.json({ error: "Enter your name (up to 120 characters)." }, { status: 400 });
  }

  try {
    const { url, anon } = supabaseConfig();
    const response = await fetch(`${url}/auth/v1/signup`, {
      method: "POST",
      headers: { apikey: anon, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, data: { full_name: fullName } }),
      cache: "no-store",
    });
    const result = await response.json().catch(() => ({})) as SignupResponse & { error_description?: string };
    if (!response.ok) {
      // Avoid disclosing whether an email already has an account.
      return NextResponse.json({ error: "We couldn't complete registration. Check the details or try signing in." }, { status: 400, headers: { "Cache-Control": "no-store" } });
    }
    if (result.session) {
      // A session here indicates email confirmation may be disabled. Never create a customer session from registration.
      return NextResponse.json({ error: "Registration is not available until email confirmation is enabled for MME authentication." }, { status: 503, headers: { "Cache-Control": "no-store" } });
    }
    return NextResponse.json({
      accepted: true,
      message: "If registration can be completed, MME will send an email verification link. Verify your email, then contact MME to link your customer profile if one already exists.",
    }, { status: 202, headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "Registration is temporarily unavailable." }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }
}
