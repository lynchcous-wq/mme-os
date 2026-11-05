import { NextResponse } from "next/server";

export type PosAuthContext = {
  authUserId: string;
  personId: string;
  baseUrl: string;
  serviceKey: string;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function authenticatePosRequest(request: Request): Promise<
  { ok: true; context: PosAuthContext } |
  { ok: false; response: ReturnType<typeof NextResponse.json> }
> {
  const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const publicKey = process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!baseUrl || !serviceKey || !publicKey) {
    return { ok: false, response: NextResponse.json({ error: "POS authentication is not configured." }, { status: 503 }) };
  }

  const authorization = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+([A-Za-z0-9._~-]+)$/i.exec(authorization);
  if (!match) {
    return { ok: false, response: NextResponse.json({ error: "A valid employee session is required." }, { status: 401 }) };
  }

  try {
    const userResponse = await fetch(`${baseUrl}/auth/v1/user`, {
      headers: { apikey: publicKey, Authorization: `Bearer ${match[1]}` },
      cache: "no-store",
    });
    if (!userResponse.ok) {
      return { ok: false, response: NextResponse.json({ error: "Employee session is invalid or expired." }, { status: 401 }) };
    }

    const user = await userResponse.json() as { id?: unknown };
    if (typeof user.id !== "string" || !uuidPattern.test(user.id)) {
      return { ok: false, response: NextResponse.json({ error: "Employee session identity could not be verified." }, { status: 401 }) };
    }

    const identityResponse = await fetch(`${baseUrl}/rest/v1/rpc/mme_resolve_person_for_auth_subject`, {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_auth_user_id: user.id }),
      cache: "no-store",
    });
    if (!identityResponse.ok) {
      return { ok: false, response: NextResponse.json({ error: "Employee identity could not be resolved." }, { status: 503 }) };
    }

    const personId = await identityResponse.json() as unknown;
    if (typeof personId !== "string" || !uuidPattern.test(personId)) {
      return { ok: false, response: NextResponse.json({ error: "This login is not linked to an active MME employee identity." }, { status: 403 }) };
    }

    return { ok: true, context: { authUserId: user.id, personId, baseUrl, serviceKey } };
  } catch {
    return { ok: false, response: NextResponse.json({ error: "Employee authentication is temporarily unavailable." }, { status: 503 }) };
  }
}

export const isUuid = (value: unknown): value is string =>
  typeof value === "string" && uuidPattern.test(value);
