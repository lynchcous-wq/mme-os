import Link from "next/link";

export default function EmployeeAccessDeniedPage() {
  return (
    <main style={{minHeight:"100vh",display:"grid",placeItems:"center",padding:24,background:"#f3f0e9"}}>
      <section style={{maxWidth:520,padding:32,background:"#fff",border:"1px solid #ddd",borderRadius:8}}>
        <p style={{fontSize:11,letterSpacing:2,color:"#68727b"}}>MME OS · SECURITY</p>
        <h1 style={{fontSize:28}}>Employee access unavailable</h1>
        <p style={{fontSize:14,lineHeight:1.8,color:"#626b73"}}>The system could not verify an active employee relationship and current company access controls. Access is denied by default. Contact an authorized MME administrator; customer account access is not changed by this employee-access decision.</p>
        <Link href="/" style={{color:"#193b55",fontWeight:700}}>Return to storefront</Link>
      </section>
    </main>
  );
}
