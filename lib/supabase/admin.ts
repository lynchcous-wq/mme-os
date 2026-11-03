import "server-only";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { getSupabasePublicEnv, getSupabaseServiceRoleKey } from "./env";

/**
 * Privileged server-only client. Never import this module into a Client
 * Component, expose its key, or use it before validating the signed-in user.
 * All actor IDs must be derived from supabase.auth.getUser(), never request data.
 */
export function createAdminClient() {
  const { url } = getSupabasePublicEnv();
  return createSupabaseClient(url, getSupabaseServiceRoleKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
