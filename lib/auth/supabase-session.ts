import { NextRequest, NextResponse } from "next/server";

const ACCESS_COOKIE = "mme_access_token";
const REFRESH_COOKIE = "mme_refresh_token";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type AuthUser = { id: string; email?: string; role?: string; email_confirmed_at?: string | null };
export type AuthSession = { access_token: string; refresh_token: string; expires_in?: number; user?: AuthUser };

export function supabaseConfig() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) throw new Error("Supabase authentication is not configured.");
  return { url: url.replace(/\/$/, ""), anon };
}

export function setSessionCookies(response: NextResponse, session: AuthSession) {
  const secure = process.env.NODE_ENV === "production";
  const maxAge = Math.max(60, Math.min(Number(session.expires_in ?? 3600), 86400));
  response.cookies.set(ACCESS_COOKIE, session.access_token, {
    httpOnly: true, secure, sameSite: "lax", path: "/", maxAge,
  });
  response.cookies.set(REFRESH_COOKIE, session.refresh_token, {
    httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 60 * 60 * 24 * 30,
  });
}

export function clearSessionCookies(response: NextResponse) {
  const secure = process.env.NODE_ENV === "production";
  for (const name of [ACCESS_COOKIE, REFRESH_COOKIE]) {
    response.cookies.set(name, "", { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 0 });
  }
}

export function hasSameOrigin(request: NextRequest) {
  const origin = request.headers.get("origin");
  if (!origin) return false;
  try {
    return new URL(origin).host === request.nextUrl.host;
  } catch {
    return false;
  }
}

export async function passwordSignIn(email: string, password: string): Promise<AuthSession> {
  const { url, anon } = supabaseConfig();
  const response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anon, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
    cache: "no-store",
  });
  const body = await response.json().catch(() => ({})) as AuthSession & { msg?: string; message?: string; error_description?: string };
  if (!response.ok || typeof body.access_token !== "string" || typeof body.refresh_token !== "string") {
    throw new Error("Email or password could not be verified.");
  }
  const verifiedUser = await getAuthUser(body.access_token);
  if (!verifiedUser) throw new Error("Authentication provider did not return a verifiable session.");
  body.user = verifiedUser;
  return body;
}

export async function getAuthUser(accessToken: string): Promise<AuthUser | null> {
  const { url, anon } = supabaseConfig();
  const response = await fetch(`${url}/auth/v1/user`, {
    headers: { apikey: anon, Authorization: `Bearer ${accessToken}` },
    cache: "no-store",
  });
  if (!response.ok) return null;
  const user = await response.json() as AuthUser;
  return typeof user.id === "string" && UUID.test(user.id) ? user : null;
}

export async function refreshAuthSession(refreshToken: string): Promise<AuthSession | null> {
  const { url, anon } = supabaseConfig();
  const response = await fetch(`${url}/auth/v1/token?grant_type=refresh_token`, {
    method: "POST",
    headers: { apikey: anon, "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
    cache: "no-store",
  });
  if (!response.ok) return null;
  const session = await response.json() as AuthSession;
  return typeof session.access_token === "string" && typeof session.refresh_token === "string" ? session : null;
}

export async function requireBrowserUser(request: NextRequest) {
  const access = request.cookies.get(ACCESS_COOKIE)?.value;
  const refresh = request.cookies.get(REFRESH_COOKIE)?.value;
  if (access) {
    const user = await getAuthUser(access);
    if (user) return { user, refreshed: null as AuthSession | null };
  }
  if (!refresh) return { user: null, refreshed: null as AuthSession | null };
  const refreshed = await refreshAuthSession(refresh);
  if (!refreshed) return { user: null, refreshed: null as AuthSession | null };
  const user = await getAuthUser(refreshed.access_token);
  return { user, refreshed: user ? refreshed : null };
}

export async function requireEmployeeIdentity(authUserId: string) {
  if (!UUID.test(authUserId)) return null;
  const { url } = supabaseConfig();
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) return null;

  const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
  const identityResponse = await fetch(`${url}/rest/v1/rpc/mme_resolve_person_for_auth_subject`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ p_auth_user_id: authUserId }),
    cache: "no-store",
  });
  if (!identityResponse.ok) return null;
  const personId = await identityResponse.json() as unknown;
  if (typeof personId !== "string" || !UUID.test(personId)) return null;

  const employeeResponse = await fetch(
    `${url}/rest/v1/employee_relationships?person_id=eq.${encodeURIComponent(personId)}&employment_status=eq.active&select=person_id&limit=1`,
    { headers, cache: "no-store" },
  );
  if (!employeeResponse.ok) return null;
  const rows = await employeeResponse.json() as Array<{ person_id: string }>;
  return rows.length === 1 ? { personId } : null;
}
