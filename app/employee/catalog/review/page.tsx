import { redirect } from "next/navigation";
import Link from "next/link";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import ReviewQueue from "./ReviewQueue";

export default async function CatalogReviewPage() {
  const session = await createSessionClient();
  const { data: { user }, error } = await session.auth.getUser();
  if (error || !user) redirect("/employee/login");
  try {
    const admin = createAdminClient();
    const { data: allowed, error: permissionError } = await admin.rpc("mme_employee_authorize_catalog_action", {
      p_actor_user_id: user.id, p_permission_key: "catalog.review", p_target_product_id: null, p_submitter_user_id: null,
    });
    if (permissionError || allowed !== true) redirect("/employee/access-denied");
  } catch {
    redirect("/employee/access-denied?reason=configuration");
  }
  return <main className="simple-page"><header className="header"><Link className="brand" href="/"><span className="brand-mark">MM</span><span>MUCH MORE<br/><b>ELECTRONICS</b></span></Link><nav><Link href="/employee/catalog">Product workspace</Link></nav><div className="actions"><form action="/api/employee/logout" method="post"><button type="submit">Sign out</button></form></div></header><section style={{maxWidth:1180,width:"100%",margin:"0 auto",padding:"44px 6%"}}><ReviewQueue/></section></main>;
}
