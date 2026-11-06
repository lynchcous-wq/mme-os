import { NextRequest, NextResponse } from "next/server";
import { createHash, randomUUID } from "node:crypto";

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

function reply(status: number, error: string, requestId: string) {
  return NextResponse.json({ error, requestId }, {
    status, headers: { "Cache-Control": "no-store", "X-Request-ID": requestId },
  });
}
function rolesFromUser(user: any): Role[] {
  const raw = user?.app_metadata?.roles ?? (user?.app_metadata?.role ? [user.app_metadata.role] : []);
  if (!Array.isArray(raw)) return [];
  return raw.filter((r: unknown): r is Role =>
    r === "ceo" || r === "privacy_officer" || r === "manager" || r === "warranty_specialist"
  );
}
function digest(value: string) {
  return createHash("sha256").update(value).digest("hex");
}
async function rpc(url: string, key: string, name: string, body: unknown) {
  const response = await fetch(url + "/rest/v1/rpc/" + name, {
    method: "POST",
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify(body), cache: "no-store",
  });
  if (!response.ok) throw new Error("audit_rpc_failed");
  return response.json().catch(() => null);
}

export async function GET(request: NextRequest) {
  const requestId = randomUUID();
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !anonKey || !serviceKey) return reply(503, "compliance_api_not_configured", requestId);

  const resourceParam = request.nextUrl.searchParams.get("resource") ?? "unknown";
  const resource = resourceParam in VIEW_BY_RESOURCE ? resourceParam as Resource : null;
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    ?? request.headers.get("x-real-ip") ?? "unknown";
  const ipDigest = digest(ip);
  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);

  let user: any = null;
  if (match) {
    const authResponse = await fetch(supabaseUrl + "/auth/v1/user", {
      headers: { apikey: anonKey, Authorization: "Bearer " + match[1] }, cache: "no-store",
    }).catch(() => null);
    if (authResponse?.ok) user = await authResponse.json().catch(() => null);
  }
  if (!user?.id) {
    await rpc(supabaseUrl, serviceKey, "mme_warranty_compliance_record_api_audit", {
      p_request_id: requestId, p_actor_id: null, p_resource: resource ?? "unknown",
      p_action: "denied", p_outcome: "denied", p_roles: [], p_ip_digest: ipDigest,
      p_reason_code: match ? "invalid_session" : "authentication_required",
    }).catch(() => null);
    return reply(401, match ? "invalid_session" : "authentication_required", requestId);
  }

  const roles = rolesFromUser(user);
  const audit = (action: string, outcome: string, reason: string) =>
    rpc(supabaseUrl, serviceKey, "mme_warranty_compliance_record_api_audit", {
      p_request_id: requestId, p_actor_id: user.id, p_resource: resource ?? "unknown",
      p_action: action, p_outcome: outcome, p_roles: roles, p_ip_digest: ipDigest,
      p_reason_code: reason,
    });

  if (!resource) {
    await audit("denied", "denied", "invalid_resource").catch(() => null);
    return reply(400, "invalid_resource", requestId);
  }
  if (!roles.some((role) => ROLE_ACCESS[resource].includes(role))) {
    await audit("denied", "denied", "insufficient_permissions").catch(() => null);
    return reply(403, "insufficient_permissions", requestId);
  }

  const userBucket = digest("user:" + user.id);
  const ipBucket = digest("ip:" + ipDigest);
  let userLimit: any;
  let ipLimit: any;
  try {
    [userLimit, ipLimit] = await Promise.all([
      rpc(supabaseUrl, serviceKey, "mme_warranty_compliance_consume_rate_limit", {
        p_bucket_key: userBucket, p_limit: 60, p_window_seconds: 60,
      }),
      rpc(supabaseUrl, serviceKey, "mme_warranty_compliance_consume_rate_limit", {
        p_bucket_key: ipBucket, p_limit: 180, p_window_seconds: 60,
      }),
    ]);
  } catch {
    await audit("upstream_error", "failed", "rate_limit_unavailable").catch(() => null);
    return reply(503, "compliance_api_temporarily_unavailable", requestId);
  }
  const allowed = (Array.isArray(userLimit) ? userLimit[0]?.allowed : userLimit?.allowed)
    && (Array.isArray(ipLimit) ? ipLimit[0]?.allowed : ipLimit?.allowed);
  if (!allowed) {
    await audit("rate_limited", "limited", "rate_limit_exceeded").catch(() => null);
    return reply(429, "rate_limit_exceeded", requestId);
  }

  const response = await fetch(supabaseUrl + "/rest/v1/" + VIEW_BY_RESOURCE[resource] + "?select=*", {
    headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, Accept: "application/json" },
    cache: "no-store",
  }).catch(() => null);
  if (!response?.ok) {
    await audit("upstream_error", "failed", response ? "compliance_query_failed" : "compliance_data_unavailable").catch(() => null);
    return reply(502, "compliance_data_unavailable", requestId);
  }
  const data = await response.json().catch(() => null);
  if (!Array.isArray(data)) {
    await audit("upstream_error", "failed", "invalid_compliance_response").catch(() => null);
    return reply(502, "invalid_compliance_response", requestId);
  }
  await audit("read", "allowed", "authorized_read").catch(() => null);
  const safeRows = data.slice(0, 500);
  return NextResponse.json(
    { requestId, resource, data: safeRows, count: safeRows.length, truncated: data.length > safeRows.length, asOf: new Date().toISOString() },
    { status: 200, headers: { "Cache-Control": "no-store", "Vary": "Authorization", "X-Request-ID": requestId } },
  );
}
