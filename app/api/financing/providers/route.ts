import { NextRequest, NextResponse } from "next/server";
import { requireBrowserUser, requireEmployeeIdentity, supabaseConfig } from "@/lib/auth/supabase-session";
import { financingProviders } from "@/lib/financing/provider-catalog";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const { user } = await requireBrowserUser(request);
    if (!user) return NextResponse.json({ error: "Employee sign-in required." }, { status: 401, headers: { "Cache-Control": "no-store" } });
    const employee = await requireEmployeeIdentity(user.id);
    if (!employee) return NextResponse.json({ error: "Active employee access required." }, { status: 403, headers: { "Cache-Control": "no-store" } });

    const { url } = supabaseConfig();
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!serviceKey) throw new Error("Provider registry is not configured.");
    const response = await fetch(
      `${url}/rest/v1/mme_financing_provider_programs?select=provider_key,status,merchant_id,approved_products,agreement_reference,terms_verified_at,updated_at&order=provider_key.asc`,
      { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` }, cache: "no-store", signal: AbortSignal.timeout(5000) },
    );
    if (!response.ok) throw new Error("Provider registry unavailable.");
    const rows = await response.json() as Array<{
      provider_key: string; status: string; merchant_id: string | null;
      approved_products: string[]; agreement_reference: string | null;
      terms_verified_at: string | null; updated_at: string;
    }>;
    const records = new Map(rows.map(row => [row.provider_key, row]));
    const providers = financingProviders.map(provider => {
      const record = records.get(provider.providerKey);
      return {
        ...provider,
        status: record?.status ?? "research",
        merchantId: record?.merchant_id ?? null,
        approvedProducts: record?.approved_products ?? [],
        agreementReference: record?.agreement_reference ?? null,
        termsVerifiedAt: record?.terms_verified_at ?? null,
      };
    });
    return NextResponse.json({ providers, access: "active_employee", productionActivationAllowed: false }, {
      headers: { "Cache-Control": "no-store", Pragma: "no-cache" },
    });
  } catch {
    return NextResponse.json({ error: "The provider register is temporarily unavailable. Confirm the preview database migration and employee access." }, {
      status: 503, headers: { "Cache-Control": "no-store" },
    });
  }
}
