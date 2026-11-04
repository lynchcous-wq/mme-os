import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const token = request.headers.get("authorization")?.match(/^Bearer ([^\\s]+)$/)?.[1];
    if (!token) return NextResponse.json({ error: "Employee sign-in is required." }, { status: 401 });

    const base = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY;
    const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!base || !anon || !service) {
      return NextResponse.json({ error: "Reconciliation inbox is not configured." }, { status: 503 });
    }

    const auth = await fetch(base + "/auth/v1/user", {
      headers: { apikey: anon, Authorization: "Bearer " + token }, cache: "no-store",
    });
    if (!auth.ok) return NextResponse.json({ error: "Employee session is invalid or expired." }, { status: 401 });
    const user = await auth.json() as { id?: string };
    if (!user.id) return NextResponse.json({ error: "Employee identity could not be verified." }, { status: 401 });

    const limit = Number(new URL(request.url).searchParams.get("limit") ?? "50");
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
      return NextResponse.json({ error: "Limit must be an integer between 1 and 100." }, { status: 400 });
    }

    const response = await fetch(base + "/rest/v1/rpc/mme_list_cancelled_workflow_reconciliations", {
      method: "POST",
      headers: { apikey: service, Authorization: "Bearer " + service, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ p_actor_user_id: user.id, p_limit: limit }), cache: "no-store",
    });
    if (!response.ok) return NextResponse.json({ error: "Reconciliation inbox could not be loaded." }, { status: 502 });
    const items = await response.json() as unknown;
    if (!Array.isArray(items)) return NextResponse.json({ error: "Reconciliation returned an invalid response." }, { status: 502 });
    return NextResponse.json({ items }, { headers: { "Cache-Control": "no-store, private", Vary: "Authorization" } });
  } catch {
    return NextResponse.json({ error: "Reconciliation inbox is temporarily unavailable." }, { status: 502 });
  }
}
