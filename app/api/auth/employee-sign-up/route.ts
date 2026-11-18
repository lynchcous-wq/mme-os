import { NextRequest, NextResponse } from "next/server";
import { enforceAuthRateLimit } from "@/lib/security/auth-rate-limit";
import { hasSameOrigin, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) {
    return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  }
  const limited = await enforceAuthRateLimit(request, "employee-sign-up", 5, 3600);
  if (limited) return limited;
  if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) {
    return NextResponse.json({ error: "JSON request required." }, { status: 415 });
  }

  try {
    const body = await request.json() as { email?: unknown; password?: unknown };
    if (typeof body.email !== "string" || typeof body.password !== "string" ||
        body.email.trim().length < 3 || body.email.length > 320 ||
        body.password.length < 12 || body.password.length > 1024) {
      return NextResponse.json({ error: "Enter a valid email and a password of at least 12 characters." }, { status: 400 });
    }

    const { url, anon } = supabaseConfig();
    const response = await fetch(`${url}/auth/v1/signup`, {
      method: "POST",
      headers: { apikey: anon, "Content-Type": "application/json" },
      body: JSON.stringify({
        email: body.email.trim().toLowerCase(),
        password: body.password,
        options: { emailRedirectTo: new URL("/employee-sign-in", request.nextUrl.origin).toString() },
      }),
      cache: "no-store",
    });

    // Do not reveal whether an email already has an account or is eligible for staff access.
    if (!response.ok) {
      return NextResponse.json({
        accepted: true,
        message: "If this address can be registered, a confirmation email will be sent. Employee access still requires a separately approved MME employee identity.",
      }, { status: 202, headers: { "Cache-Control": "no-store" } });
    }
    return NextResponse.json({
      accepted: true,
      message: "If this address can be registered, a confirmation email will be sent. Employee access still requires a separately approved MME employee identity.",
    }, { status: 202, headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "Employee registration is temporarily unavailable." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
