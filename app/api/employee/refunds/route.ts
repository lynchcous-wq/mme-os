import { NextRequest, NextResponse } from "next/server";
import { hasSameOrigin, requireBrowserUser, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const headers = { "Cache-Control": "no-store, private" };

async function authorize(base: string, key: string, actor: string, permission: string, submitter: string | null = null) {
  const response = await fetch(base + "/rest/v1/rpc/mme_employee_authorize_order_refund_action", {
    method: "POST",
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify({ p_actor_user_id: actor, p_permission_key: permission, p_submitter_user_id: submitter }),
    cache: "no-store",
  });
  if (!response.ok) return false;
  return (await response.json()) === true;
}

export async function GET(request: NextRequest) {
  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return NextResponse.json({ error: "Sign in is required." }, { status: 401, headers });
    const { url } = supabaseConfig();
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!key) return NextResponse.json({ error: "Refund center is not configured." }, { status: 503, headers });
    if (!await authorize(url, key, session.user.id, "orders.refunds.view")) {
      return NextResponse.json({ error: "Refund review permission is not assigned to this employee." }, { status: 403, headers });
    }
    const response = await fetch(
      url + "/rest/v1/mme_order_refund_requests?select=id,order_id,amount_cents,currency,reason_code,status,requested_by,requested_at,updated_at,provider_status,failure_code&order=requested_at.desc&limit=100",
      { headers: { apikey: key, Authorization: "Bearer " + key }, cache: "no-store" },
    );
    if (!response.ok) return NextResponse.json({ error: "Refund queue could not be loaded." }, { status: 503, headers });
    return NextResponse.json({ requests: await response.json() }, { headers });
  } catch {
    return NextResponse.json({ error: "Refund center is temporarily unavailable." }, { status: 503, headers });
  }
}

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return NextResponse.json({ error: "Same-origin request required." }, { status: 403, headers });
  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return NextResponse.json({ error: "Sign in is required." }, { status: 401, headers });
    const body = await request.json().catch(() => null) as { refundRequestId?: string; approve?: boolean; reason?: string } | null;
    if (!body || typeof body.refundRequestId !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(body.refundRequestId) ||
        typeof body.approve !== "boolean" || typeof body.reason !== "string" || body.reason.trim().length < 2 || body.reason.length > 300) {
      return NextResponse.json({ error: "A refund request, decision, and reason are required." }, { status: 400, headers });
    }
    const { url } = supabaseConfig();
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!key) return NextResponse.json({ error: "Refund center is not configured." }, { status: 503, headers });
    const response = await fetch(url + "/rest/v1/rpc/mme_decide_order_refund_authorized", {
      method: "POST",
      headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
      body: JSON.stringify({
        p_refund_request_id: body.refundRequestId,
        p_approver_user_id: session.user.id,
        p_approve: body.approve,
        p_reason: body.reason.trim(),
      }),
      cache: "no-store",
    });
    if (!response.ok) {
      return NextResponse.json({ error: "Refund decision was not accepted. Check approval permissions and request status." }, { status: response.status === 403 ? 403 : 409, headers });
    }
    return NextResponse.json({ status: await response.json() }, { headers });
  } catch {
    return NextResponse.json({ error: "Refund decision could not be completed." }, { status: 503, headers });
  }
}
