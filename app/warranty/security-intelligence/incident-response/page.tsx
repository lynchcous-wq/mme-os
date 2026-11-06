"use client";
import {useCallback,useEffect,useState} from "react";
export default function SecurityIncidentResponse(){
 const [token,setToken]=useState(""),[role,setRole]=useState(""),[cases,setCases]=useState<any[]>([]),[events,setEvents]=useState<any[]>([]),[alerts,setAlerts]=useState<any[]>([]),[form,setForm]=useState<Record<string,string>>({}),[busy,setBusy]=useState(false),[message,setMessage]=useState("");
 const load=useCallback(async()=>{if(!token)return;setBusy(true);try{
  const [r,a]=await Promise.all([fetch("/api/warranty/security-intelligence/incident-response",{headers:{Authorization:"Bearer "+token},cache:"no-store"}),fetch("/api/warranty/security-intelligence/executive",{headers:{Authorization:"Bearer "+token},cache:"no-store"})]);
  const [j,k]=await Promise.all([r.json(),a.json()]);if(!r.ok)throw Error(j.error??"Unable to load incident cases");if(!a.ok)throw Error(k.error??"Unable to load security alerts");
  setRole(j.role);setCases(j.cases??[]);setEvents(j.events??[]);setAlerts(k.alerts??[]);setMessage("Incident response workspace refreshed.");
 }catch(e){setMessage(e instanceof Error?e.message:"Unable to load workspace")}finally{setBusy(false)}},[token]);
 useEffect(()=>{setToken(sessionStorage.getItem("mme-warranty-security-access-token")??"")},[]);
 useEffect(()=>{if(token)void load()},[token,load]);
 const act=async(alertId:string,action:string)=>{const rationale=(form[alertId+":rationale"]??"").trim(),ownerId=form[alertId+":owner"]?.trim()||null,recoveryEvidence=form[alertId+":evidence"]?.trim()||null;if(rationale.length<10){setMessage("Provide an action rationale of at least 10 characters.");return}setBusy(true);try{const r=await fetch("/api/warranty/security-intelligence/incident-response",{method:"POST",headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify({alertId,action,rationale,ownerId,recoveryEvidence}),cache:"no-store"}),j=await r.json();if(!r.ok)throw Error(j.error??"Action not recorded");setMessage("Incident action recorded.");await load()}catch(e){setMessage(e instanceof Error?e.message:"Action failed")}finally{setBusy(false)}};
 const caseByAlert=new Map(cases.map(c=>[c.alert_id,c])),canAct=["ceo","cio","it_admin","manager"].includes(role);
 const panel:React.CSSProperties={background:"#fff",border:"1px solid #dce4ea",borderRadius:12,padding:18,marginBottom:14},muted:React.CSSProperties={color:"#657789",fontSize:13},button:React.CSSProperties={background:"#173f58",color:"#fff",border:0,borderRadius:7,padding:"9px 12px",fontWeight:700,cursor:"pointer"},input:React.CSSProperties={width:"100%",boxSizing:"border-box",padding:9,border:"1px solid #ccd6dd",borderRadius:7,margin:"5px 0 9px"};
 return <main style={{minHeight:"100vh",background:"#f2f5f8",color:"#172432",padding:"28px clamp(16px,4vw,52px)",fontFamily:"Arial,sans-serif"}}>
 <div style={{fontSize:11,letterSpacing:2,fontWeight:700,color:"#557184"}}>MUCH MORE ELECTRONICS · MME OS · BUILD 010.29</div>
 <header style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:16,flexWrap:"wrap"}}><div><h1 style={{fontSize:30,margin:"8px 0"}}>Security Incident Response</h1><p style={muted}>Severity-based response cases, ownership, escalation, recovery verification and independent closure approval.</p></div><button style={button} disabled={!token||busy} onClick={()=>void load()}>{busy?"Refreshing…":"Refresh workspace"}</button></header>
 <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(170px,1fr))",gap:12,margin:"18px 0"}}>{[["Open cases",cases.filter(c=>c.status!=="closed").length],["SLA overdue",cases.filter(c=>c.status!=="closed"&&new Date(c.sla_due_at)<new Date()).length],["Escalated",cases.filter(c=>c.escalation_level>0&&c.status!=="closed").length],["Closure pending",cases.filter(c=>c.status==="closure_pending").length]].map(([k,v])=><article key={String(k)} style={panel}><small style={muted}>{k}</small><div style={{fontSize:27,fontWeight:700,marginTop:7}}>{v}</div></article>)}</section>
 <section style={panel}><h2>Incident queue</h2><p style={muted}>Critical response target: 15 minutes · Warning: 1 hour · Info: 4 hours. Deadlines are tracked from case creation.</p>
 {alerts.filter(a=>a.status!=="resolved").map(a=>{const c=caseByAlert.get(a.alert_id);return <article key={a.alert_id} style={{border:"1px solid #dfe7ec",borderRadius:9,padding:14,marginTop:10}}>
 <strong>{a.severity.toUpperCase()} · {a.source_system} · {a.status}</strong><p>{a.message}</p>
 {c?<div style={muted}>Case {c.case_id} · {c.status} · SLA due {new Date(c.sla_due_at).toLocaleString()} · Escalation level {c.escalation_level} · Owner {c.owner_id??"Unassigned"}</div>:<p style={muted}>No response case opened.</p>}
 {canAct&&<div style={{marginTop:10}}><label style={muted}>Action rationale</label><input style={input} value={form[a.alert_id+":rationale"]??""} onChange={e=>setForm(v=>({...v,[a.alert_id+":rationale"]:e.target.value}))} placeholder="Explain this response action (minimum 10 characters)"/>
 {!c?<button style={button} disabled={busy} onClick={()=>void act(a.alert_id,"open_case")}>Open response case</button>:<div style={{display:"grid",gap:8}}>
 <input style={input} value={form[a.alert_id+":owner"]??""} onChange={e=>setForm(v=>({...v,[a.alert_id+":owner"]:e.target.value}))} placeholder="Owner user UUID for assignment"/>
 <button style={button} disabled={busy} onClick={()=>void act(a.alert_id,"assign_owner")}>Assign owner</button>
 <button style={button} disabled={busy} onClick={()=>void act(a.alert_id,"escalate")}>Escalate incident</button>
 <input style={input} value={form[a.alert_id+":evidence"]??""} onChange={e=>setForm(v=>({...v,[a.alert_id+":evidence"]:e.target.value}))} placeholder="Recovery evidence (minimum 10 characters)"/>
 <button style={button} disabled={busy} onClick={()=>void act(a.alert_id,"verify_recovery")}>Verify recovery</button>
 <button style={button} disabled={busy} onClick={()=>void act(a.alert_id,"request_closure")}>Request closure</button>
 {c.status==="closure_pending"&&<button style={button} disabled={busy} onClick={()=>void act(a.alert_id,"approve_closure")}>Approve closure (different approver)</button>}
 </div>}</div>}
 </article>})}
 {!alerts.some(a=>a.status!=="resolved")&&<p style={muted}>No unresolved security alerts are currently recorded.</p>}</section>
 <section style={panel}><h2>Incident activity and audit history</h2>{events.length?events.map(e=><article key={e.event_id} style={{padding:"10px 0",borderBottom:"1px solid #e8edf1"}}><strong>{e.event_type.replaceAll("_"," ")}</strong><div style={muted}>{e.actor_role} · {new Date(e.created_at).toLocaleString()}</div><p>{e.rationale}</p></article>):<p style={muted}>No response events recorded.</p>}</section>
 {message&&<p role="status" style={panel}>{message}</p>}<footer style={muted}>Automation records and routes response work; it does not automatically disable accounts, block transactions, deny claims or make customer-impacting decisions. Verify identity and evidence through approved procedures.</footer></main>
}