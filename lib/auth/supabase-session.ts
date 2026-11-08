import { NextRequest, NextResponse } from "next/server";

const ACCESS_COOKIE = "mme_access_token";
const REFRESH_COOKIE = "mme_refresh_token";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type AuthUser = { id: string; email?: string };
export type AuthSession = { access_token: string; refresh_token: string; expires_in?: number; user?: AuthUser };

export function supabaseConfig() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) throw new Error("Supabase authentication is not configured.");
  return { url: url.replace(/\/$/, ""), anon };
}

export function hasSameOrigin(request: NextRequest) {
  const origin = request.headers.get("origin");
  if (!origin) return false;
  try { return new URL(origin).host === request.nextUrl.host; } catch { return false; }
}

export function setSessionCookies(response: NextResponse, session: AuthSession) {
  const secure = process.env.NODE_ENV === "production";
  const maxAge = Math.max(60, Math.min(Number(session.expires_in ?? 3600), 86400));
  response.cookies.set(ACCESS_COOKIE, session.access_token, { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge });
  response.cookies.set(REFRESH_COOKIE, session.refresh_token, { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 60 * 60 * 24 * 30 });
}

export function clearSessionCookies(response: NextResponse) {
  const secure = process.env.NODE_ENV === "production";
  for (const name of [ACCESS_COOKIE, REFRESH_COOKIE]) {
    response.cookies.set(name, "", { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 0 });
  }
}

export async function passwordSignIn(email: string, password: string): Promise<AuthSession> {
  const { url, anon } = supabaseConfig();
  const response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: anon, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }), cache: "no-store",
  });
  if (!response.ok) throw new Error("Sign-in could not be verified.");
  const body = await response.json() as AuthSession;
  if (typeof body.access_token !== "string" || typeof body.refresh_token !== "string") throw new Error("Sign-in could not be verified.");
  const user = await getAuthUser(body.access_token);
  if (!user) throw new Error("Sign-in could not be verified.");
  body.user = user;
  return body;
}

export async function getAuthUser(accessToken: string): Promise<AuthUser | null> {
  const { url, anon } = supabaseConfig();
  const response = await fetch(`${url}/auth/v1/user`, {
    headers: { apikey: anon, Authorization: `Bearer ${accessToken}` }, cache: "no-store",
  });
  if (!response.ok) return null;
  const user = await response.json() as AuthUser;
  return typeof user.id === "string" && UUID.test(user.id) ? user : null;
}

export async function refreshAuthSession(refreshToken: string): Promise<AuthSession | null> {
  const { url, anon } = supabaseConfig();
  const response = await fetch(`${url}/auth/v1/token?grant_type=refresh_token`, {
    method: "POST", headers: { apikey: anon, "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }), cache: "no-store",
  });
  if (!response.ok) return null;
  const session = await response.json() as AuthSession;
  if (typeof session.access_token !== "string" || typeof session.refresh_token !== "string") return null;
  const user = await getAuthUser(session.access_token);
  if (!user) return null;
  session.user = user;
  return session;
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
  return { user: refreshed?.user ?? null, refreshed };
}

/** Resolve the authenticated Supabase subject to an active MME employee relationship. */
export async function requireEmployeeIdentity(authUserId: string) {
  if (!UUID.test(authUserId)) return null;
  const { url } = supabaseConfig();
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) throw new Error("Employee identity verification is not configured.");
  const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
  const identityResponse = await fetch(`${url}/rest/v1/rpc/mme_resolve_person_for_auth_subject`, {
    method: "POST", headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ p_auth_user_id: authUserId }), cache: "no-store",
  });
  if (!identityResponse.ok) throw new Error("Employee identity verification is unavailable.");
  const personId = await identityResponse.json() as unknown;
  if (typeof personId !== "string" || !UUID.test(personId)) return null;
  const employeeResponse = await fetch(
    `${url}/rest/v1/mme_employee_relationships?person_identity_id=eq.${encodeURIComponent(personId)}&status=eq.active&select=id&limit=1`,
    { headers, cache: "no-store" },
  );
  if (!employeeResponse.ok) throw new Error("Employee identity verification is unavailable.");
  const rows = await employeeResponse.json() as Array<{ id: string }>;
  return rows.length === 1 ? { personId } : null;
}

export async function revokeProviderSession(request: NextRequest) {
  const access = request.cookies.get(ACCESS_COOKIE)?.value;
  if (!access) return;
  const { url, anon } = supabaseConfig();
  await fetch(`${url}/auth/v1/logout?scope=local`, {
    method: "POST", headers: { apikey: anon, Authorization: `Bearer ${access}` }, cache: "no-store",
  });
}
