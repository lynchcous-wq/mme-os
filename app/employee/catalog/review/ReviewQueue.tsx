"use client";

import { useEffect, useState } from "react";

type ReviewItem = {
  id: string; sku: string; name: string; brand: string | null; model_number: string | null;
  condition: string; tracking_mode: string; catalog_status: string; specifications: Record<string, unknown>;
  description: string | null; warranty_summary: string | null; submitter_label: string;
  history: Array<{ id: number; event_type: string; actor_label: string; created_at: string; product_version: number }>;
};

export default function ReviewQueue() {
  const [items, setItems] = useState<ReviewItem[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState("");
  const [message, setMessage] = useState("");
  const [notesById, setNotesById] = useState<Record<string,string>>({});

  async function load() {
    setLoading(true); setError("");
    try {
      const response = await fetch("/api/employee/catalog/review", { cache: "no-store" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "Review queue unavailable.");
      setItems(result.products ?? []);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Review queue unavailable.");
    } finally { setLoading(false); }
  }

  useEffect(() => { void load(); }, []);

  async function act(id: string, action: "approve" | "publish" | "return") {
    setWorking(id + action); setError(""); setMessage("");
    try {
      const response = await fetch(`/api/employee/catalog/${id}/${action}`, { method: "POST", ...(action === "return" ? { headers: { "Content-Type": "application/json" }, body: JSON.stringify({ correction_notes: notesById[id] ?? "" }) } : {}) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "Action could not be completed.");
      setMessage(action === "approve" ? "Product approved. Publication requires separate authorization." : action === "publish" ? "Product published." : "Product returned to its submitter with correction notes.");
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Action could not be completed.");
    } finally { setWorking(""); }
  }

  return <section style={{display:"grid",gap:16}}>
    <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:12,flexWrap:"wrap"}}>
      <div><div className="eyebrow">MME OS · Governance</div><h1 style={{fontSize:34,margin:"8px 0"}}>Catalog review center</h1><p style={{fontSize:13,color:"var(--muted)"}}>Pending submissions, submitter identity, product details and audit history.</p></div>
      <button onClick={()=>void load()} style={buttonStyle}>Refresh queue</button>
    </div>
    {error && <p role="alert" style={{color:"#a22",fontSize:13}}>{error}</p>}
    {message && <p role="status" style={{color:"#17613e",fontSize:13}}>{message}</p>}
    {loading ? <p>Loading review queue…</p> : items.length === 0 ? <div style={{padding:28,border:"1px solid var(--line)",background:"white"}}><b>No products awaiting review.</b><p style={{fontSize:12,color:"var(--muted)"}}>New submissions will appear here after an employee submits a saved draft.</p></div> :
      items.map(item=><article key={item.id} style={{padding:22,border:"1px solid var(--line)",background:"white",borderRadius:5,display:"grid",gap:14}}>
        <div style={{display:"flex",justifyContent:"space-between",gap:12,flexWrap:"wrap"}}>
          <div><div className="eyebrow">{item.sku} · {item.condition.replaceAll("_"," ")}</div><h2 style={{fontSize:22,margin:"7px 0"}}>{item.name}</h2><p style={{fontSize:12,color:"var(--muted)"}}>{[item.brand,item.model_number].filter(Boolean).join(" · ") || "Brand/model not supplied"} · Submitted by {item.submitter_label}</p></div>
          <span style={{fontSize:11,padding:"6px 9px",background:"#f4efe3",height:"fit-content"}}>{item.catalog_status.replaceAll("_"," ")}</span>
        </div>
        {item.description && <p style={{fontSize:13,lineHeight:1.7}}>{item.description}</p>}
        <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(160px,1fr))",gap:10,fontSize:12}}>
          <div><b>Tracking</b><p>{item.tracking_mode}</p></div><div><b>Warranty</b><p>{item.warranty_summary || "Not supplied"}</p></div><div><b>Specifications</b><pre style={{whiteSpace:"pre-wrap",fontSize:11}}>{JSON.stringify(item.specifications,null,2)}</pre></div>
        </div>
        <div style={{borderTop:"1px solid var(--line)",paddingTop:12}}><b style={{fontSize:12}}>Audit history</b>
          {item.history.map(event=><p key={event.id} style={{fontSize:11,color:"var(--muted)",margin:"7px 0"}}>{new Date(event.created_at).toLocaleString()} · {event.event_type.replaceAll("_"," ")} · {event.actor_label} · v{event.product_version}</p>)}
        </div>
        <label style={{display:"grid",gap:6,fontSize:12}}>Return for correction — explain exactly what must change<textarea value={notesById[item.id] ?? ""} onChange={event=>setNotesById(previous=>({...previous,[item.id]:event.target.value}))} minLength={10} maxLength={2000} rows={3} placeholder="Example: Confirm the exact model number and add RAM, storage, and screen condition details." style={{width:"100%",padding:10,border:"1px solid var(--line)",fontSize:12}}/></label>
        <div style={{display:"flex",gap:10,flexWrap:"wrap"}}>
          <button disabled={!!working || !!item.history.some(event=>event.event_type==="approved")} onClick={()=>void act(item.id,"approve")} style={buttonStyle}>{working===item.id+"approve"?"Approving…":"Approve product"}</button>\n          <button disabled={!!working || (notesById[item.id] ?? "").trim().length<10} onClick={()=>void act(item.id,"return")} style={buttonStyle}>{working===item.id+"return"?"Returning…":"Return for correction"}</button>
          <button disabled={!!working || !item.history.some(event=>event.event_type==="approved")} onClick={()=>void act(item.id,"publish")} style={{...buttonStyle,background:"#164b3c",color:"#fff"}}>{working===item.id+"publish"?"Publishing…":"Publish product"}</button>
        </div>
      </article>)
    }
  </section>;
}

const buttonStyle = {padding:"10px 14px",border:"1px solid #cdd2cc",borderRadius:3,background:"white",color:"#34413b",fontSize:12,fontWeight:700,cursor:"pointer"} as const;
