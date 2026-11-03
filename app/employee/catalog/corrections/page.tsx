import { redirect } from "next/navigation";
import Link from "next/link";
import { createClient as createSessionClient } from "@/lib/supabase/server";
import CorrectionWorkspace from "./CorrectionWorkspace";

export default async function EmployeeCorrectionsPage() {
  const session = await createSessionClient();
  const { data: { user }, error } = await session.auth.getUser();
  if (error || !user) redirect("/employee/login");
  return <main className="simple-page"><header className="header"><Link className="brand" href="/"><span className="brand-mark">MM</span><span>MUCH MORE<br/><b>ELECTRONICS</b></span></Link><nav><Link href="/employee/catalog">Product workspace</Link><span style={{margin:"0 10px"}}>·</span><Link href="/employee/catalog/review">Review center</Link></nav><div className="actions"><form action="/api/employee/logout" method="post"><button type="submit">Sign out</button></form></div></header><section style={{maxWidth:1180,width:"100%",margin:"0 auto",padding:"44px 6%"}}><CorrectionWorkspace/></section></main>;
}
