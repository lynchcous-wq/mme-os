import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const OUTCOMES = new Set([
  "confirmed_completed",
  "confirmed_not_completed",
  "compensation_verified",
  "unresolved_escalated",
]);

type EvidenceReference = {
  kind: string;
  reference: string;
  sha256?: string;
};

function jsonError(message: string, status: number) {
  return NextResponse.json({ error: message }, {
    status,
    headers: { "Cache-Control": "no-store, private", Vary: "Authorization" },
  });
}

export async function POST(request: Request) {
  try {
    const token = request.headers.get("authorization")?.match(/^Bearer (\S+)$/)?.[1];
    if (!token) return jsonError("Employee sign-in is required.", 401);

    const base = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY;
    const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!base || !anon || !service) {
      return jsonError("Reconciliation decisions are not configured.", 503);
    }

    const auth = await fetch(base + "/auth/v1/user", {
      headers: { apikey: anon, Authorization: "Bearer " + token },
      cache: "no-store",
    });
    if (!auth.ok) return jsonError("Employee session is invalid or expired.", 401);
    const user = await auth.json() as { id?: string };
    if (!user.id || !UUID.test(user.id)) {
      return jsonError("Employee identity could not be verified.", 401);
    }

    if (!(request.headers.get("content-type") ?? "").toLowerCase().includes("application/json")) {
      return jsonError("Content-Type must be application/json.", 415);
    }
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > 12000) {
      return jsonError("Reconciliation decision request is too large.", 413);
    }

    let parsed: unknown;
    try { parsed = JSON.parse(raw); } catch {
      return jsonError("A valid JSON decision request is required.", 400);
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return jsonError("Invalid reconciliation decision request.", 400);
    }

    const body = parsed as Record<string, unknown>;
    const allowedKeys = new Set(["step_run_id", "outcome", "reason", "evidence_references"]);
    if (Object.keys(body).some((key) => !allowedKeys.has(key))) {
      return jsonError("The request contains unsupported fields.", 400);
    }

    const stepRunId = body.step_run_id;
    if (typeof stepRunId !== "number" || !Number.isSafeInteger(stepRunId) || stepRunId <= 0) {
      return jsonError("step_run_id must be a positive safe integer.", 400);
    }
    if (typeof body.outcome !== "string" || !OUTCOMES.has(body.outcome)) {
      return jsonError("A supported reconciliation outcome is required.", 400);
    }
    if (typeof body.reason !== "string" || body.reason.trim().length < 3 || body.reason.trim().length > 1000) {
      return jsonError("A reason between 3 and 1000 characters is required.", 400);
    }
    if (!Array.isArray(body.evidence_references) || body.evidence_references.length < 1 || body.evidence_references.length > 20) {
      return jsonError("Provide between 1 and 20 evidence references.", 400);
    }

    const evidence: EvidenceReference[] = [];
    for (const item of body.evidence_references) {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        return jsonError("Each evidence reference must be an object.", 400);
      }
      const entry = item as Record<string, unknown>;
      const keys = Object.keys(entry);
      if (keys.some((key) => !["kind", "reference", "sha256"].includes(key))
          || typeof entry.kind !== "string" || entry.kind.trim().length < 2 || entry.kind.trim().length > 80
          || typeof entry.reference !== "string" || entry.reference.trim().length < 1 || entry.reference.trim().length > 500
          || (entry.sha256 !== undefined && (typeof entry.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(entry.sha256)))) {
        return jsonError("Evidence entries require a kind and opaque reference; optional SHA-256 must be a 64-character lowercase digest.", 400);
      }
      evidence.push({
        kind: entry.kind.trim(),
        reference: entry.reference.trim(),
        ...(entry.sha256 === undefined ? {} : { sha256: entry.sha256 }),
      });
    }

    const response = await fetch(base + "/rest/v1/rpc/mme_record_cancelled_workflow_reconciliation_decision", {
      method: "POST",
      headers: {
        apikey: service,
        Authorization: "Bearer " + service,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        p_actor_user_id: user.id,
        p_step_run_id: stepRunId,
        p_outcome: body.outcome,
        p_reason: body.reason.trim(),
        p_evidence_references: evidence,
      }),
      cache: "no-store",
    });

    if (!response.ok) {
      if ([400, 401, 403, 404, 409, 422].includes(response.status)) {
        return jsonError("The decision was rejected by workflow state, evidence, or supervisor authorization controls.", 409);
      }
      return jsonError("The reconciliation decision could not be recorded.", 502);
    }

    const decisionId = await response.json() as unknown;
    const idText = typeof decisionId === "number" || typeof decisionId === "string" ? String(decisionId) : "";
    if (!/^\d+$/.test(idText) || BigInt(idText) <= 0n) {
      return jsonError("The reconciliation service returned an invalid decision identifier.", 502);
    }

    return NextResponse.json({
      accepted: true,
      decision_id: idText,
      outcome: body.outcome,
      workflow_status_changed: false,
      retry_or_resume_authorized: false,
    }, {
      headers: { "Cache-Control": "no-store, private", Vary: "Authorization" },
    });
  } catch {
    return jsonError("Reconciliation decisions are temporarily unavailable.", 502);
  }
}
