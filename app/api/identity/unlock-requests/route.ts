import { NextRequest, NextResponse } from "next/server";
import { requireBrowserUser, supabaseConfig, hasSameOrigin } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) {
    return NextResponse.json({ error: "Request origin could not be verified." }, { status: 403 });
  }
  if (!request.headers.get("content-type")?.toLowerCase().includes("application/json")) {
    return NextResponse.json({ error: "JSON request required." }, { status: 415 });
  }

  try {
    const { user } = await requireBrowserUser(request);
    if (!user || !user.email_confirmed_at) {
      return NextResponse.json({ error: "Sign in with a confirmed account to submit an unlock request." }, { status: 401 });
    }

    const body = await request.json() as { reason?: unknown };
    if (typeof body.reason !== "string" || body.reason.trim().length < 10 || body.reason.trim().length > 1000) {
      return NextResponse.json({ error: "Provide a reason between 10 and 1,000 characters." }, { status: 400 });
    }

    const { url } = supabaseConfig();
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!serviceKey) throw new Error("Unlock request service is not configured.");
    const headers = {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    };

    // The target and requester are derived from the verified session, never from browser-supplied IDs.
    const identityResponse = await fetch(
      `${url}/rest/v1/mme_person_identities?auth_user_id=eq.${encodeURIComponent(user.id)}&select=id,security_status&limit=1`,
      { headers, cache: "no-store" },
    );
    if (!identityResponse.ok) throw new Error("Identity lookup unavailable.");
    const identities = await identityResponse.json() as Array<{ id: string; security_status: string }>;
    if (identities.length !== 1 || !UUID.test(identities[0].id)) {
      return NextResponse.json({ error: "A unique MME identity could not be verified." }, { status: 403 });
    }
    const identity = identities[0];
    if (identity.security_status === "active") {
      return NextResponse.json({ error: "This identity is not currently locked." }, { status: 409 });
    }

    const pendingResponse = await fetch(
      `${url}/rest/v1/mme_identity_unlock_requests?target_identity_id=eq.${encodeURIComponent(identity.id)}&requested_by_identity_id=eq.${encodeURIComponent(identity.id)}&status=eq.pending&select=id&limit=1`,
      { headers, cache: "no-store" },
    );
    if (!pendingResponse.ok) throw new Error("Unlock request status unavailable.");
    const pending = await pendingResponse.json() as Array<{ id: string }>;
    if (pending.length) {
      return NextResponse.json({ submitted: true, alreadyPending: true }, {
        status: 200, headers: { "Cache-Control": "no-store" },
      });
    }

    const createResponse = await fetch(`${url}/rest/v1/mme_identity_unlock_requests`, {
      method: "POST",
      headers: { ...headers, Prefer: "return=representation" },
      body: JSON.stringify({
        target_identity_id: identity.id,
        requested_by_identity_id: identity.id,
        reason: body.reason.trim(),
        status: "pending",
      }),
      cache: "no-store",
    });
    if (!createResponse.ok) throw new Error("Unlock request could not be submitted.");
    const created = await createResponse.json() as Array<{ id: string; status: string }>;
    if (created.length !== 1 || created[0].status !== "pending") throw new Error("Unlock request could not be confirmed.");

    return NextResponse.json({ submitted: true, requestId: created[0].id }, {
      status: 201, headers: { "Cache-Control": "no-store" },
    });
  } catch {
    return NextResponse.json({ error: "Unlock request service is temporarily unavailable." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
