"use client";

import { createBrowserClient } from "@supabase/ssr";
import { getSupabasePublicEnv } from "./env";

/** Browser session client. Database access remains governed by Supabase RLS. */
export function createClient() {
  const { url, key } = getSupabasePublicEnv();
  return createBrowserClient(url, key);
}
