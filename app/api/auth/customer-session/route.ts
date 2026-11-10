import { NextRequest, NextResponse } from "next/server";
import { getAuthUser, hasSameOrigin, refreshAuthSession, requireCustomerIdentity, setSessionCookies } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) {
    return NextResponse.json({ error: "JSON request required." }, { status: 415 });
  }
  try {
    const body = await request.json() as { access_token?: unknown; refresh_token?: unknown; expires_in?: unknown; token_type?: unknown };
    if (typeof body.access_token !== "string" || body.access_token.length < 20 || body.access_token.length > 8192 ||
        typeof body.refresh_token !== "string" || body.refresh_token.length < 20 || body.refresh_token.length > 8192) {
      return NextResponse.json({ error: "The confirmation session is invalid or expired. Please sign in." }, { status: 400 });
    }
    const user = await getAuthUser(body.access_token);
    if (!user?.email_confirmed_at) {
      return NextResponse.json({ error: "Email confirmation could not be verified. Please sign in after confirming your email." }, { status: 401 });
    }
    const refreshedSession = await refreshAuthSession(body.refresh_token);
    if (!refreshedSession || refreshedSession.user?.id !== user.id) {
      return NextResponse.json({ error: "The confirmation session is invalid or expired. Please sign in." }, { status: 401 });
    }
    const customer = await requireCustomerIdentity(user);
    if (!customer) return NextResponse.json({ error: "Customer identity could not be verified." }, { status: 403 });
    const response = NextResponse.json({
      authenticated: false,
      customerStatus: customer.status,
      message: customer.status === "active"
        ? "Your email is confirmed and customer access is active."
        : "Your email is confirmed. Your MME customer account is awaiting activation.",
    }, { headers: { "Cache-Control": "no-store" } });
    setSessionCookies(response, refreshedSession);
    return response;
  } catch {
    return NextResponse.json({ error: "Email confirmation could not be completed right now." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
