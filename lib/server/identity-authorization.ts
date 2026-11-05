import "server-only";

export type IdentityScope = Record<string, string>;

export type IdentityAuthorizationResult =
  | { ok: true; actorUserId: string }
  | { ok: false; status: 401 | 403 | 503; error: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function config() {
  return {
    base: process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL,
    anon: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY,
    service: process.env.SUPABASE_SERVICE_ROLE_KEY,
  };
}

/**
 * Verify the bearer token with Supabase Auth, then ask the Build 004
 * server-only authorization function for a permission decision.
 *
 * Never pass an actor ID supplied by the request. The actor ID is read only
 * from the validated Auth response. Scope must be derived by the caller from
 * trusted database records, not copied from request JSON.
 */
export async function authenticateAndAuthorizeEmployee(
  bearerToken: string | null,
  resourceKey: string,
  actionKey: string,
  requestedScope: IdentityScope,
): Promise<IdentityAuthorizationResult> {
  if (!bearerToken) return { ok: false, status: 401, error: "Employee sign-in is required." };

  const { base, anon, service } = config();
  if (!base || !anon || !service) {
    return { ok: false, status: 503, error: "Employee authorization is not configured." };
  }

  try {
    const auth = await fetch(`${base}/auth/v1/user`, {
      headers: { apikey: anon, Authorization: `Bearer ${bearerToken}` },
      cache: "no-store",
    });
    if (!auth.ok) return { ok: false, status: 401, error: "Employee session is invalid or expired." };

    const user = await auth.json() as { id?: unknown };
    if (typeof user.id !== "string" || !UUID.test(user.id)) {
      return { ok: false, status: 401, error: "Employee identity could not be verified." };
    }

    const decision = await fetch(`${base}/rest/v1/rpc/mme_authorize_employee_action`, {
      method: "POST",
      headers: {
        apikey: service,
        Authorization: `Bearer ${service}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_actor_auth_user_id: user.id,
        p_resource_key: resourceKey,
        p_action_key: actionKey,
        p_requested_scope: requestedScope,
      }),
      cache: "no-store",
    });

    if (!decision.ok) {
      return { ok: false, status: 503, error: "Employee authorization could not be verified." };
    }
    if (await decision.json() !== true) {
      return { ok: false, status: 403, error: "Employee does not have the required permission." };
    }

    return { ok: true, actorUserId: user.id };
  } catch {
    return { ok: false, status: 503, error: "Employee authorization is temporarily unavailable." };
  }
}
