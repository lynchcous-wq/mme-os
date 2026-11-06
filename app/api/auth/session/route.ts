import { NextRequest, NextResponse } from "next/server";
import { clearSessionCookies, getAuthUser, requireBrowserUser, setSessionCookies } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const result = await requireBrowserUser(request);
    if (!result.user) {
      const response = NextResponse.json({ authenticated: false }, { headers: { "Cache-Control": "no-store" } });
      clearSessionCookies(response);
      return response;
    }
    const response = NextResponse.json({
      authenticated: true,
      user: { id: result.user.id, email: result.user.email ?? null },
    }, { headers: { "Cache-Control": "no-store" } });
    if (result.refreshed) setSessionCookies(response, result.refreshed);
    return response;
  } catch {
    return NextResponse.json({ authenticated: false, error: "Authentication service unavailable." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
