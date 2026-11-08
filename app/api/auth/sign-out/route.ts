import { NextRequest, NextResponse } from "next/server";
import { clearSessionCookies, hasSameOrigin, revokeProviderSession } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  await revokeProviderSession(request);
  const response = NextResponse.json({ authenticated: false }, { headers: { "Cache-Control": "no-store" } });
  clearSessionCookies(response);
  return response;
}
