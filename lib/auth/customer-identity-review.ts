import { NextRequest } from "next/server";
import { requireBrowserUser, supabaseConfig } from "@/lib/auth/supabase-session";

export async function requireCustomerIdentityReviewer(request: NextRequest) {
  const session = await requireBrowserUser(request);
  if (!session.user) return { user: null, refreshed: session.refreshed, authorized: false as const, status: 401 };
  const { url } = supabaseConfig();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return { user: session.user, refreshed: session.refreshed, authorized: false as const, status: 503 };
  const response = await fetch(`${url}/rest/v1/rpc/mme_employee_authorize_customer_identity_review`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_actor_auth_user_id: session.user.id }),
    cache: "no-store",
  });
  if (!response.ok) return { user: session.user, refreshed: session.refreshed, authorized: false as const, status: response.status === 401 || response.status === 403 ? 403 : 503 };
  const authorized = await response.json().catch(() => false);
  return { user: session.user, refreshed: session.refreshed, authorized: authorized === true, status: authorized === true ? 200 : 403 };
}
