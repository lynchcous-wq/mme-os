import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

function config() {
  return {
    base: process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL,
    anon: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY,
    service: process.env.SUPABASE_SERVICE_ROLE_KEY,
  };
}

async function authenticate(request: Request) {
  const token = request.headers.get("authorization")?.match(/^Bearer ([^\\s]+)$/)?.[1];
  if (!token) return { error: "Employee sign-in is required.", status: 401 as const };
  const { base, anon, service } = config();
  if (!base || !anon || !service) return { error: "Workflow cancellation is not configured.", status: 503 as const };
  const auth = await fetch(base + "/auth/v1/user", {
    headers: { apikey: anon, Authorization: "Bearer " + token }, cache: "no-store",
  });
  if (!auth.ok) return { error: "Employee session is invalid or expired.", status: 401 as const };
  const user = await auth.json() as { id?: string };
  if (!user.id) return { error: "Employee identity could not be verified.", status: 401 as const };
  return { userId: user.id, base, service };
}

export async function POST(request: Request) {
  try {
    const session = await authenticate(request);
    if ("error" in session) return NextResponse.json({ error: session.error }, { status: session.status });
    if (!(request.headers.get("content-type") ?? "").toLowerCase().includes("application/json")) {
      return NextResponse.json({ error: "Content-Type must be application/json." }, { status: 415 });
    }
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > 4000) {
      return NextResponse.json({ error: "Cancellation request is too large." }, { status: 413 });
    }
    let body: unknown;
    try { body = JSON.parse(raw); } catch {
      return NextResponse.json({ error: "A valid JSON cancellation request is required." }, { status: 400 });
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return NextResponse.json({ error: "Invalid cancellation request." }, { status: 400 });
    }
    const input = body as Record<string, unknown>;
    const executionId = input.execution_id;
    const reason = input.reason;
    if (typeof executionId !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(executionId)) {
      return NextResponse.json({ error: "execution_id must be a valid UUID." }, { status: 400 });
    }
    if (typeof reason !== "string" || reason.trim().length < 3 || reason.trim().length > 1000) {
      return NextResponse.json({ error: "A cancellation reason between 3 and 1000 characters is required." }, { status: 400 });
    }
    const response = await fetch(session.base + "/rest/v1/rpc/mme_cancel_workflow_execution", {
      method: "POST",
      headers: { apikey: session.service, Authorization: "Bearer " + session.service, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ p_actor_user_id: session.userId, p_execution_id: executionId, p_reason: reason.trim() }),
      cache: "no-store",
    });
    if (!response.ok) {
      const status = response.status;
      if ([400, 403, 404, 409].includes(status)) {
        return NextResponse.json({ error: "Cancellation was rejected by workflow authorization or state controls." }, { status: status === 400 ? 400 : status === 404 ? 404 : 409 });
      }
      return NextResponse.json({ error: "Workflow cancellation could not be recorded." }, { status: 502 });
    }
    const result = await response.json() as unknown;
    if (result !== "cancelled") return NextResponse.json({ error: "Workflow cancellation returned an invalid result." }, { status: 502 });
    return NextResponse.json({ accepted: true, execution_status: "cancelled" }, {
      headers: { "Cache-Control": "no-store, private", Vary: "Authorization" },
    });
  } catch {
    return NextResponse.json({ error: "Workflow cancellation is temporarily unavailable." }, { status: 502 });
  }
}
