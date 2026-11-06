import { NextRequest, NextResponse } from "next/server";
import { requireBrowserUser, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return NextResponse.json({ error: "Sign in is required." }, { status: 401 });
    const { url } = supabaseConfig();
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!serviceKey) return NextResponse.json({ error: "Customer account access is not configured." }, { status: 503 });
    const response = await fetch(
      `${url}/rest/v1/mme_customer_account_links?auth_user_id=eq.${encodeURIComponent(session.user.id)}&link_status=eq.active&select=person_id&limit=1`,
      { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` }, cache: "no-store" },
    );
    if (!response.ok) return NextResponse.json({ error: "Customer account access could not be verified." }, { status: 503 });
    const links = await response.json() as Array<{ person_id: string }>;
    if (links.length !== 1) return NextResponse.json({ error: "Your login is valid, but your MME customer account has not been linked yet." }, { status: 403 });
    return NextResponse.json({ customerAccess: true, personId: links[0].person_id }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "Customer account verification is temporarily unavailable." }, { status: 503 });
  }
}
