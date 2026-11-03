import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import CatalogEditor from "./CatalogEditor";

export default async function EmployeeCatalogPage() {
  const sessionClient = await createSessionClient();
  const { data: { user }, error: userError } = await sessionClient.auth.getUser();
  if (userError || !user) redirect("/employee/login");

  try {
    const admin = createAdminClient();
    const [{ data: employee, error: employeeError }, { data: settings, error: settingsError }] = await Promise.all([
      admin.from("employee_relationships").select("employment_status").eq("user_id", user.id).maybeSingle(),
      admin.from("employee_security_settings").select("employee_access_frozen,ceo_user_id").eq("singleton", true).maybeSingle(),
    ]);
    if (employeeError || settingsError || employee?.employment_status !== "active" || !settings || settings.employee_access_frozen || !settings.ceo_user_id) {
      redirect("/employee/access-denied");
    }
  } catch {
    redirect("/employee/access-denied?reason=configuration");
  }
  return (
    <main className="simple-page">
      <header className="header">
        <Link className="brand" href="/"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
        <nav><Link href="/products">Customer storefront</Link></nav>
        <div className="actions"><span>Employee workspace preview</span></div>
      </header>
      <section style={{maxWidth:1180, width:"100%", margin:"0 auto", padding:"52px 6%"}}>
        <div className="eyebrow">MME OS · Catalog management</div>
        <h1 style={{fontFamily:"Manrope,sans-serif",fontSize:"clamp(34px,5vw,52px)",letterSpacing:"-.06em",margin:"12px 0"}}>Product <em style={{color:"var(--accent)"}}>workspace.</em></h1>
        <p style={{maxWidth:700,color:"var(--muted)",lineHeight:1.8,fontSize:13}}>Prepare a product record for review. Product details live here; stock units, reservations, acquisition cost and selling prices are managed in their own MME OS modules.</p>
        <div style={{margin:"24px 0",padding:16,border:"1px solid #e5c69a",background:"#fff8eb",borderRadius:4,color:"#664b28",fontSize:12,lineHeight:1.7}}>
          <b>Employee access is checked on the server when Supabase and the employee-control migrations are configured. Product drafts remain preview-only and are not saved.</b><br/>
          This page demonstrates the catalog entry workflow. Do not enter real customer, payment, IMEI or serial-number data. Drafts on this screen are not saved.
        </div>
        <CatalogEditor />
      </section>
      <footer className="simple-footer"><span>© {new Date().getFullYear()} Much More Electronics</span><Link href="/">Storefront</Link></footer>
    </main>
  );
}
