import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function middleware(request: NextRequest) {
  const isEmployeeArea = request.nextUrl.pathname.startsWith("/employee/");
  const isLoginPage = request.nextUrl.pathname === "/employee/login";
  if (!isEmployeeArea) return NextResponse.next();

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) {
    if (isLoginPage) return NextResponse.next();
    const loginUrl = new URL("/employee/login", request.url);
    loginUrl.searchParams.set("setup", "required");
    return NextResponse.redirect(loginUrl);
  }

  let response = NextResponse.next({ request });
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  // Validate the identity with Supabase; do not authorize from an unverified session payload.
  const { data: { user }, error } = await supabase.auth.getUser();
  if (!isLoginPage && (error || !user)) {
    const loginUrl = new URL("/employee/login", request.url);
    loginUrl.searchParams.set("next", request.nextUrl.pathname);
    return NextResponse.redirect(loginUrl);
  }
  if (isLoginPage && user && !error) return NextResponse.redirect(new URL("/employee/catalog", request.url));
  return response;
}

export const config = { matcher: ["/employee/:path*"] };
