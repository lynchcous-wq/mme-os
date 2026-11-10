import { NextRequest, NextResponse } from "next/server";
import { hasSameOrigin, passwordSignIn, requireCustomerIdentity, setSessionCookies } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) {
    return NextResponse.json({ error: "JSON request required." }, { status: 415 });
  }
  try {
    const body = await request.json() as { email?: unknown; password?: unknown };
    if (typeof body.email !== "string" || typeof body.password !== "string" ||
        body.email.length > 320 || body.password.length < 1 || body.password.length > 1024) {
      return NextResponse.json({ error: "Enter a valid email and password." }, { status: 400 });
    }
    const session = await passwordSignIn(body.email.trim().toLowerCase(), body.password);
    const customer = await requireCustomerIdentity(session.user!);
    if (!customer || customer.status !== "active") {
      return NextResponse.json({ error: customer?.status === "pending"
        ? "Your email is confirmed. Customer access is awaiting MME activation."
        : "This account does not have active customer access." }, {
        status: 403, headers: { "Cache-Control": "no-store" },
      });
    }
    const response = NextResponse.json({ authenticated: true, customerAccess: true }, {
      headers: { "Cache-Control": "no-store" },
    });
    setSessionCookies(response, session);
    return response;
  } catch (error) {
    const configurationError = error instanceof Error && /not configured|unavailable/.test(error.message);
    return NextResponse.json({ error: configurationError
      ? "Customer sign-in is temporarily unavailable."
      : "Email or password could not be verified." }, {
      status: configurationError ? 503 : 401, headers: { "Cache-Control": "no-store" },
    });
  }
}
