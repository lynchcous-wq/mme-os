"use client";

import { useCallback, useEffect, useState } from "react";

type RequestRow={request_id:string;verified_email:string;customer_reference:string|null;contact_phone_last4:string|null;customer_note:string|null;request_status:string;requested_at:string;reviewed_by_auth_user_id:string|null;review_note:string|null};

export default function CustomerIdentityReviewPage(){
 const [rows,setRows]=useState<RequestRow[]>([]);
 const [personIds,setPersonIds]=useState<Record<string,string>>({});
 const [notes,setNotes]=useState<Record<string,string>>({});
 const [message,setMessage]=useState("");
 const [loading,setLoading]=useState(true);
 const [busy,setBusy]=useState<string|null>(null);
 const load=useCallback(async()=>{
  setLoading(true);
  try{const r=await fetch("/api/employee/customer-identity-requests",{credentials:"same-origin",cache:"no-store"});const d=await r.json();if(!r.ok)throw new Error(d.error||"Unable to load review queue.");setRows(d.requests||[]);setMessage("");}
  catch(e){setMessage(e instanceof Error?e.message:"Review queue unavailable.");}
  finally{setLoading(false);}
 },[]);
 useEffect(()=>{void load();},[load]);
 async function decide(row:RequestRow,decision:"under_review"|"approve"|"reject"){
  setBusy(row.request_id);setMessage("");
  try{
   const personId=personIds[row.request_id]||"";
   const r=await fetch("/api/employee/customer-identity-requests",{method:"POST",credentials:"same-origin",headers:{"Content-Type":"application/json"},body:JSON.stringify({requestId:row.request_id,decision,personId,note:notes[row.request_id]||""})});
   const d=await r.json();if(!r.ok)throw new Error(d.error||"Decision could not be saved.");
   setMessage(decision==="approve"?"Identity approved and customer access activated.":decision==="reject"?"Request rejected and audited.":"Request moved into review.");
   await load();
  }catch(e){setMessage(e instanceof Error?e.message:"Decision could not be saved.");}
  finally{setBusy(null);}
 }
 return <main style={{minHeight:"100vh",background:"#f3f5f7",padding:24,color:"#172432"}}>
  <div style={{maxWidth:1100,margin:"0 auto"}}>
   <header style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:16,flexWrap:"wrap"}}>
    <div><p style={{fontSize:12,fontWeight:800,letterSpacing:1.5,color:"#587083"}}>MME EMPLOYEE OPERATIONS</p><h1 style={{fontSize:30,margin:"6px 0"}}>Customer identity review</h1><p style={{color:"#607180"}}>Restricted queue · customer.identity.review permission</p></div>
    <button onClick={()=>void load()} style={{padding:"11px 16px",border:"1px solid #b9c5ce",borderRadius:8,background:"#fff",fontWeight:700}}>Refresh queue</button>
   </header>
   <p style={{padding:14,background:"#fff7e8",border:"1px solid #ead7b2",borderRadius:9,lineHeight:1.5}}>Verify the customer against trusted MME source records before approval. Customer-provided email, phone digits, notes, and references are not identity proof. Approval links the verified login to the selected active MME person and enables customer portal access.</p>
   {message&&<p role="status" aria-live="polite" style={{padding:12,background:"#fff",borderRadius:8}}>{message}</p>}
   {loading?<p>Loading review queue…</p>:rows.length===0?<section style={{background:"#fff",padding:24,borderRadius:12}}>No open customer identity requests.</section>:
    <div style={{display:"grid",gap:16}}>{rows.map(row=><section key={row.request_id} style={{background:"#fff",padding:20,border:"1px solid #dfe5ea",borderRadius:12}}>
     <div style={{display:"flex",justifyContent:"space-between",gap:12,flexWrap:"wrap"}}><div><h2 style={{fontSize:18,margin:0}}>{row.verified_email}</h2><p style={{fontSize:12,color:"#607180"}}>Submitted {new Date(row.requested_at).toLocaleString()} · {row.request_status}</p></div><code style={{fontSize:11}}>{row.request_id}</code></div>
     <p><b>Customer/order reference:</b> {row.customer_reference||"Not provided"}</p><p><b>Phone last four:</b> {row.contact_phone_last4||"Not provided"}</p><p><b>Customer note:</b> {row.customer_note||"None"}</p>
     <div style={{display:"grid",gap:10,marginTop:16}}>
      <label style={{display:"grid",gap:6,fontSize:13,fontWeight:700}}>Verified active MME person ID (required for approval)<input value={personIds[row.request_id]||""} onChange={e=>setPersonIds(s=>({...s,[row.request_id]:e.target.value.trim()}))} placeholder="UUID from trusted MME records" style={{padding:12,border:"1px solid #cbd4dc",borderRadius:8}}/></label>
      <label style={{display:"grid",gap:6,fontSize:13,fontWeight:700}}>Internal review note<textarea maxLength={1000} rows={2} value={notes[row.request_id]||""} onChange={e=>setNotes(s=>({...s,[row.request_id]:e.target.value}))} style={{padding:12,border:"1px solid #cbd4dc",borderRadius:8}}/></label>
      <div style={{display:"flex",gap:8,flexWrap:"wrap"}}>
       <button disabled={!!busy} onClick={()=>void decide(row,"under_review")} style={{padding:"10px 14px",borderRadius:8,border:"1px solid #b9c5ce",background:"#fff",fontWeight:700}}>Mark reviewing</button>
       <button disabled={!!busy||!personIds[row.request_id]} onClick={()=>void decide(row,"approve")} style={{padding:"10px 14px",borderRadius:8,border:0,background:"#173f58",color:"#fff",fontWeight:700}}>Approve & activate</button>
       <button disabled={!!busy} onClick={()=>void decide(row,"reject")} style={{padding:"10px 14px",borderRadius:8,border:"1px solid #c88",background:"#fff",color:"#8b3030",fontWeight:700}}>Reject request</button>
      </div>
      {busy===row.request_id&&<small>Saving decision…</small>}
     </div>
    </section>)}</div>}
  </div>
 </main>;
}
