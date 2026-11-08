import { NextRequest, NextResponse } from "next/server";
import { requireBrowserUser, requireEmployeeIdentity, setSessionCookies } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return NextResponse.json({ authorized: false }, { status: 401, headers: { "Cache-Control": "no-store" } });
    const employee = await requireEmployeeIdentity(session.user.id);
    if (!employee) return NextResponse.json({ authorized: false }, { status: 403, headers: { "Cache-Control": "no-store" } });
    const response = NextResponse.json({ authorized: true, employeeAccess: true }, { headers: { "Cache-Control": "no-store" } });
    if (session.refreshed) setSessionCookies(response, session.refreshed);
    return response;
  } catch {
    return NextResponse.json({ authorized: false, error: "Employee verification is temporarily unavailable." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
