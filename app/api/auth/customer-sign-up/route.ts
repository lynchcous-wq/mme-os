import { NextRequest, NextResponse } from "next/server";
import { hasSameOrigin, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) {
    return NextResponse.json({ error: "JSON request required." }, { status: 415 });
  }

  try {
    const body = await request.json() as { email?: unknown; password?: unknown };
    if (typeof body.email !== "string" || typeof body.password !== "string" ||
        body.email.trim().length < 3 || body.email.length > 320 ||
        body.password.length < 10 || body.password.length > 1024) {
      return NextResponse.json({ error: "Enter a valid email and a password of at least 10 characters." }, { status: 400 });
    }
    const { url, anon } = supabaseConfig();
    const response = await fetch(`${url}/auth/v1/signup`, {
      method: "POST",
      headers: { apikey: anon, "Content-Type": "application/json" },
      body: JSON.stringify({
        email: body.email.trim().toLowerCase(),
        password: body.password,
        options: { emailRedirectTo: new URL("/account", request.nextUrl.origin).toString() },
      }),
      cache: "no-store",
    });
    if (!response.ok) {
      // Keep account-existence and provider validation details out of the public response.
      return NextResponse.json({ accepted: true, message: "If this address can be registered, a confirmation email will be sent. Check your inbox and spam folder." }, {
        status: 202, headers: { "Cache-Control": "no-store" },
      });
    }
    return NextResponse.json({ accepted: true, message: "If this address can be registered, a confirmation email will be sent. Check your inbox and spam folder." }, {
      status: 202, headers: { "Cache-Control": "no-store" },
    });
  } catch {
    return NextResponse.json({ error: "Customer registration is temporarily unavailable." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
