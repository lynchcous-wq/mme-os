import { NextRequest, NextResponse } from "next/server";
import { clearSessionCookies, hasSameOrigin } from "@/lib/auth/supabase-session";

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  const response = NextResponse.json({ authenticated: false }, { headers: { "Cache-Control": "no-store" } });
  clearSessionCookies(response);
  return response;
}
