import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import CatalogEditor from "./CatalogEditor";

export default async function EmployeeCatalogPage() {
  const sessionClient = await createSessionClient();
  const { data: { user }, error: userError } = await sessionClient.auth.getUser();
  if (userError || !user) redirect("/employee/login");

  let employeeAccessAllowed = false;
  try {
    const admin = createAdminClient();
    const [{ data: employee, error: employeeError }, { data: settings, error: settingsError }] = await Promise.all([
      admin.from("employee_relationships").select("employment_status").eq("user_id", user.id).maybeSingle(),
      admin.from("employee_security_settings").select("employee_access_frozen,ceo_user_id").eq("singleton", true).maybeSingle(),
    ]);
    employeeAccessAllowed = !employeeError && !settingsError && employee?.employment_status === "active" && !!settings && !settings.employee_access_frozen && !!settings.ceo_user_id;
  } catch {
    redirect("/employee/access-denied?reason=configuration");
  }
  if (!employeeAccessAllowed) redirect("/employee/access-denied");
  return (
    <main className="simple-page">
      <header className="header">
        <Link className="brand" href="/"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
        <nav><Link href="/products">Customer storefront</Link><span style={{margin:"0 10px"}}>·</span><Link href="/employee/catalog/review">Review center</Link><span style={{margin:"0 10px"}}>·</span><Link href="/employee/catalog/corrections">My corrections</Link></nav>
        <div className="actions"><span>Employee workspace</span><form action="/api/employee/logout" method="post"><button type="submit" style={{border:"1px solid var(--line)",background:"transparent",padding:"8px 12px",cursor:"pointer"}}>Sign out</button></form></div>
      </header>
      <section style={{maxWidth:1180, width:"100%", margin:"0 auto", padding:"52px 6%"}}>
        <div className="eyebrow">MME OS · Catalog management</div>
        <h1 style={{fontFamily:"Manrope,sans-serif",fontSize:"clamp(34px,5vw,52px)",letterSpacing:"-.06em",margin:"12px 0"}}>Product <em style={{color:"var(--accent)"}}>workspace.</em></h1>
        <p style={{maxWidth:700,color:"var(--muted)",lineHeight:1.8,fontSize:13}}>Prepare a product record for review. Product details live here; stock units, reservations, acquisition cost and selling prices are managed in their own MME OS modules.</p>
        <div style={{margin:"24px 0",padding:16,border:"1px solid #e5c69a",background:"#fff8eb",borderRadius:4,color:"#664b28",fontSize:12,lineHeight:1.7}}>
          <b>Employee access is checked on the server when Supabase and the employee-control migrations are configured. Product drafts are saved to the catalog but remain unpublished until approved.</b><br/>
          This page demonstrates the catalog entry workflow. Do not enter real customer, payment, IMEI or serial-number data. Drafts are not visible on the customer storefront until approved and published.
        </div>
        <CatalogEditor />
      </section>
      <footer className="simple-footer"><span>© {new Date().getFullYear()} Much More Electronics</span><Link href="/">Storefront</Link></footer>
    </main>
  );
}
