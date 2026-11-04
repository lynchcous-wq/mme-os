import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

function getConfig() {
  return {
    base: process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL,
    anon: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY,
    service: process.env.SUPABASE_SERVICE_ROLE_KEY,
  };
}

async function authenticate(request: Request) {
  const token = request.headers.get("authorization")?.match(/^Bearer ([^\\s]+)$/)?.[1];
  if (!token) return { error: "Employee sign-in is required.", status: 401 as const };

  const { base, anon, service } = getConfig();
  if (!base || !anon || !service) {
    return { error: "Workflow recovery is not configured.", status: 503 as const };
  }

  const auth = await fetch(base + "/auth/v1/user", {
    headers: { apikey: anon, Authorization: "Bearer " + token },
    cache: "no-store",
  });
  if (!auth.ok) return { error: "Employee session is invalid or expired.", status: 401 as const };

  const user = await auth.json() as { id?: string };
  if (!user.id) return { error: "Employee identity could not be verified.", status: 401 as const };
  return { userId: user.id, base, service };
}

export async function GET(request: Request) {
  try {
    const session = await authenticate(request);
    if ("error" in session) return NextResponse.json({ error: session.error }, { status: session.status });

    const limit = Number(new URL(request.url).searchParams.get("limit") ?? "50");
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
      return NextResponse.json({ error: "Limit must be an integer between 1 and 100." }, { status: 400 });
    }

    const response = await fetch(session.base + "/rest/v1/rpc/mme_list_workflow_recovery_reviews", {
      method: "POST",
      headers: {
        apikey: session.service,
        Authorization: "Bearer " + session.service,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ p_actor_user_id: session.userId, p_limit: limit }),
      cache: "no-store",
    });
    if (!response.ok) {
      return NextResponse.json({ error: "Workflow recovery inbox could not be loaded." }, { status: 502 });
    }
    const reviews = await response.json() as unknown;
    if (!Array.isArray(reviews)) {
      return NextResponse.json({ error: "Workflow recovery returned an invalid response." }, { status: 502 });
    }
    return NextResponse.json({ reviews }, {
      headers: { "Cache-Control": "no-store, private", Vary: "Authorization" },
    });
  } catch {
    return NextResponse.json({ error: "Workflow recovery is temporarily unavailable." }, { status: 502 });
  }
}

export async function POST(request: Request) {
  try {
    const session = await authenticate(request);
    if ("error" in session) return NextResponse.json({ error: session.error }, { status: session.status });

    const declaredLength = Number(request.headers.get("content-length") ?? "0");
    if (declaredLength > 12000) {
      return NextResponse.json({ error: "Review request is too large." }, { status: 413 });
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json({ error: "A valid JSON review is required." }, { status: 400 });
    }

    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return NextResponse.json({ error: "Invalid review request." }, { status: 400 });
    }
    const input = body as Record<string, unknown>;
    const stepRunId = input.step_run_id;
    const resolution = input.resolution;
    const reason = input.reason;
    const evidence = input.evidence ?? {};

    if (!Number.isSafeInteger(stepRunId) || Number(stepRunId) <= 0) {
      return NextResponse.json({ error: "step_run_id must be a positive integer." }, { status: 400 });
    }
    if (!["confirmed_succeeded", "safe_to_retry", "abandoned"].includes(String(resolution))) {
      return NextResponse.json({ error: "Unsupported recovery resolution." }, { status: 400 });
    }
    if (typeof reason !== "string" || reason.trim().length < 3 || reason.trim().length > 1000) {
      return NextResponse.json({ error: "A review reason between 3 and 1000 characters is required." }, { status: 400 });
    }
    if (!evidence || typeof evidence !== "object" || Array.isArray(evidence)
        || JSON.stringify(evidence).length > 8000) {
      return NextResponse.json({ error: "Evidence must be a JSON object no larger than 8000 characters." }, { status: 400 });
    }

    const response = await fetch(session.base + "/rest/v1/rpc/mme_review_workflow_step", {
      method: "POST",
      headers: {
        apikey: session.service,
        Authorization: "Bearer " + session.service,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        p_actor_user_id: session.userId,
        p_step_run_id: stepRunId,
        p_resolution: resolution,
        p_reason: reason.trim(),
        p_evidence: evidence,
      }),
      cache: "no-store",
    });

    if (!response.ok) {
      const status = response.status;
      if (status === 400 || status === 403 || status === 404 || status === 409) {
        return NextResponse.json({ error: "The review was rejected by workflow authorization or state controls." }, { status: status === 400 ? 400 : 409 });
      }
      return NextResponse.json({ error: "Workflow recovery decision could not be recorded." }, { status: 502 });
    }

    const executionStatus = await response.json() as unknown;
    if (typeof executionStatus !== "string" ||
        !["queued", "failed"].includes(executionStatus)) {
      return NextResponse.json({ error: "Workflow recovery returned an invalid result." }, { status: 502 });
    }

    return NextResponse.json({ accepted: true, execution_status: executionStatus }, {
      headers: { "Cache-Control": "no-store, private", Vary: "Authorization" },
    });
  } catch {
    return NextResponse.json({ error: "Workflow recovery is temporarily unavailable." }, { status: 502 });
  }
}
