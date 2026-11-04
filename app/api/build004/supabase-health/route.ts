import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const projectUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!projectUrl || !publishableKey) {
    return NextResponse.json(
      { configured: false, connected: false, message: "Preview Supabase configuration is incomplete." },
      { status: 503, headers: { "Cache-Control": "no-store" } }
    );
  }

  let parsedUrl: URL;
  try {
    parsedUrl = new URL(projectUrl);
  } catch {
    return NextResponse.json(
      { configured: false, connected: false, message: "Supabase project URL is invalid." },
      { status: 503, headers: { "Cache-Control": "no-store" } }
    );
  }

  if (
    parsedUrl.protocol !== "https:" ||
    !parsedUrl.hostname.endsWith(".supabase.co") ||
    !publishableKey.startsWith("sb_publishable_")
  ) {
    return NextResponse.json(
      { configured: false, connected: false, message: "Supabase Preview configuration did not pass validation." },
      { status: 503, headers: { "Cache-Control": "no-store" } }
    );
  }

  try {
    const response = await fetch(new URL("/auth/v1/settings", parsedUrl), {
      method: "GET",
      headers: { apikey: publishableKey },
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
    });

    if (!response.ok) {
      return NextResponse.json(
        { configured: true, connected: false, message: "Supabase endpoint responded but rejected the connectivity check.", upstreamStatus: response.status },
        { status: 502, headers: { "Cache-Control": "no-store" } }
      );
    }

    return NextResponse.json(
      { configured: true, connected: true, message: "Supabase Auth endpoint responded successfully. Database schema and migrations have not been verified." },
      { status: 200, headers: { "Cache-Control": "no-store" } }
    );
  } catch {
    return NextResponse.json(
      { configured: true, connected: false, message: "Could not reach the Supabase Auth endpoint." },
      { status: 502, headers: { "Cache-Control": "no-store" } }
    );
  }
}
