import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const ALLOWED_ROLES = new Set(["ceo", "cio", "it_admin", "privacy_officer", "manager"]);

export async function GET(req: NextRequest) {
  const requestId = randomUUID();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const token = (req.headers.get("authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!url || !anon || !service) {
    return NextResponse.json({ error: "monitoring_configuration_missing", requestId }, { status: 503 });
  }
  if (!token) return NextResponse.json({ error: "authentication_required", requestId }, { status: 401 });

  const auth = await fetch(url + "/auth/v1/user", {
    headers: { apikey: anon, Authorization: "Bearer " + token },
    cache: "no-store",
  }).catch(() => null);
  if (!auth?.ok) return NextResponse.json({ error: "invalid_session", requestId }, { status: 401 });

  const user = await auth.json();
  const roles = user?.app_metadata?.roles ?? [user?.app_metadata?.role];
  if (!Array.isArray(roles) || !roles.some((role: string) => ALLOWED_ROLES.has(role))) {
    return NextResponse.json({ error: "security_monitoring_access_denied", requestId }, { status: 403 });
  }

  const response = await fetch(url + "/rest/v1/rpc/mme_security_monitoring_capture_snapshot", {
    method: "POST",
    headers: {
      apikey: service,
      Authorization: "Bearer " + service,
      "Content-Type": "application/json",
    },
    body: "{}",
    cache: "no-store",
  }).catch(() => null);

  if (!response?.ok) {
    return NextResponse.json({ error: "monitoring_snapshot_unavailable", requestId }, { status: 502 });
  }
  const snapshot = await response.json();
  return NextResponse.json({ requestId, snapshot }, {
    headers: { "Cache-Control": "no-store", "X-Request-ID": requestId },
  });
}
