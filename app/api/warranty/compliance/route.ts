import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const VIEW_BY_RESOURCE = {
  summary: "mme_warranty_compliance_dashboard_kpis",
  calendar: "mme_warranty_compliance_retention_calendar",
  approvals: "mme_warranty_compliance_approval_queue",
  alerts: "mme_warranty_compliance_alert_feed",
  assignments: "mme_warranty_compliance_department_summary",
} as const;

type Resource = keyof typeof VIEW_BY_RESOURCE;
type Role = "ceo" | "privacy_officer" | "manager" | "warranty_specialist";

const ROLE_ACCESS: Record<Resource, Role[]> = {
  summary: ["ceo", "privacy_officer", "manager"],
  calendar: ["ceo", "privacy_officer", "manager", "warranty_specialist"],
  approvals: ["ceo", "privacy_officer", "manager"],
  alerts: ["ceo", "privacy_officer", "manager", "warranty_specialist"],
  assignments: ["ceo", "privacy_officer", "manager"],
};

function jsonError(status: number, code: string) {
  return NextResponse.json({ error: code }, { status, headers: { "Cache-Control": "no-store" } });
}

function rolesFromUser(user: any): Role[] {
  const raw = user?.app_metadata?.roles ?? (user?.app_metadata?.role ? [user.app_metadata.role] : []);
  if (!Array.isArray(raw)) return [];
  return raw.filter((r: unknown): r is Role =>
    r === "ceo" || r === "privacy_officer" || r === "manager" || r === "warranty_specialist"
  );
}

export async function GET(request: NextRequest) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !anonKey || !serviceKey) return jsonError(503, "compliance_api_not_configured");

  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return jsonError(401, "authentication_required");

  const authResponse = await fetch(supabaseUrl + "/auth/v1/user", {
    headers: { apikey: anonKey, Authorization: "Bearer " + match[1] },
    cache: "no-store",
  }).catch(() => null);
  if (!authResponse || !authResponse.ok) return jsonError(401, "invalid_session");
  const user = await authResponse.json().catch(() => null);
  if (!user?.id) return jsonError(401, "invalid_session");

  const resource = request.nextUrl.searchParams.get("resource") as Resource | null;
  if (!resource || !(resource in VIEW_BY_RESOURCE)) return jsonError(400, "invalid_resource");

  const roles = rolesFromUser(user);
  if (!roles.some((role) => ROLE_ACCESS[resource].includes(role))) return jsonError(403, "insufficient_permissions");

  const view = VIEW_BY_RESOURCE[resource];
  const response = await fetch(
    supabaseUrl + "/rest/v1/" + view + "?select=*",
    {
      headers: {
        apikey: serviceKey,
        Authorization: "Bearer " + serviceKey,
        Accept: "application/json",
      },
      cache: "no-store",
    }
  ).catch(() => null);

  if (!response) return jsonError(502, "compliance_data_unavailable");
  if (!response.ok) return jsonError(502, "compliance_data_query_failed");

  const data = await response.json().catch(() => null);
  if (!Array.isArray(data)) return jsonError(502, "invalid_compliance_response");

  const safeRows = data.slice(0, 500);
  return NextResponse.json(
    { resource, data: safeRows, count: safeRows.length, truncated: data.length > safeRows.length, asOf: new Date().toISOString() },
    { status: 200, headers: { "Cache-Control": "no-store", "Vary": "Authorization" } }
  );
}
