import { NextRequest, NextResponse } from "next/server";
import { requireBrowserUser, requireEmployeeIdentity, setSessionCookies } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return NextResponse.json({ error: "Sign in is required." }, { status: 401 });
    const employee = await requireEmployeeIdentity(session.user.id);
    if (!employee) {
      return NextResponse.json({ error: "This login is not linked to an active MME employee identity." }, { status: 403 });
    }
    const response = NextResponse.json({
      authorized: true,
      personId: employee.personId,
      employeeAccess: true,
    }, { headers: { "Cache-Control": "no-store" } });
    if (session.refreshed) setSessionCookies(response, session.refreshed);
    return response;
  } catch {
    return NextResponse.json({ error: "Employee authorization is temporarily unavailable." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
