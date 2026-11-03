"use client";

import { useEffect, useState } from "react";

type ReturnedDraft = {
  id:string; sku:string; name:string; brand:string|null; model_number:string|null; upc_ean:string|null;
  description:string|null; condition:string; tracking_mode:string; specifications:Record<string,unknown>;
  warranty_summary:string|null; correction_notes:string|null; version:number;
};

export default function CorrectionWorkspace() {
  const [items,setItems]=useState<ReturnedDraft[]>([]);
  const [values,setValues]=useState<Record<string,Record<string,string>>>({});
  const [error,setError]=useState("");
  const [message,setMessage]=useState("");
  const [loading,setLoading]=useState(true);
  const [saving,setSaving]=useState("");
  async function load(){
    setLoading(true);setError("");
    try{
      const response=await fetch("/api/employee/catalog/mine",{cache:"no-store"});
      const result=await response.json();if(!response.ok)throw new Error(result.error||"Returned drafts unavailable.");
      const rows:ReturnedDraft[]=result.products??[];setItems(rows);
      setValues(Object.fromEntries(rows.map(item=>[item.id,{
        name:item.name,sku:item.sku,brand:item.brand??"",model_number:item.model_number??"",upc_ean:item.upc_ean??"",
        description:item.description??"",condition:item.condition,tracking_mode:item.tracking_mode,
        specifications:JSON.stringify(item.specifications,null,2),warranty_summary:item.warranty_summary??"",
      }])));
    }catch(cause){setError(cause instanceof Error?cause.message:"Returned drafts unavailable.");}
    finally{setLoading(false);}
  }
  useEffect(()=>{void load();},[]);
  function change(id:string,key:string,value:string){setValues(previous=>({...previous,[id]:{...previous[id],[key]:value}}));}
  async function save(item:ReturnedDraft){
    setSaving(item.id);setError("");setMessage("");
    try{
      const form=values[item.id];let specifications:unknown;
      try{specifications=JSON.parse(form.specifications);}catch{throw new Error("Specifications must be valid JSON.");}
      const response=await fetch("/api/employee/catalog/"+item.id+"/edit",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({
        expected_version:item.version,name:form.name,sku:form.sku,category:"televisions",brand:form.brand||null,
        model_number:form.model_number||null,upc_ean:form.upc_ean||null,description:form.description||null,
        condition:form.condition,tracking_mode:form.tracking_mode,specifications,warranty_summary:form.warranty_summary||null,
      })});
      const result=await response.json();if(!response.ok)throw new Error(result.error||"Revision could not be saved.");
      setMessage("Revision saved as a new version. You can return to the product workspace to submit it again.");
      await load();
    }catch(cause){setError(cause instanceof Error?cause.message:"Revision could not be saved.");}
    finally{setSaving("");}
  }
  const input={width:"100%",padding:9,border:"1px solid #d6d9d3",fontSize:12} as const;
  return <section style={{display:"grid",gap:18}}>
    <div><div className="eyebrow">MME OS · Employee corrections</div><h1 style={{fontSize:32,margin:"8px 0"}}>Returned product drafts</h1><p style={{fontSize:13,color:"var(--muted)"}}>Review the feedback, update your own draft, and save a new version.</p></div>
    {error&&<p role="alert" style={{color:"#a22"}}>{error}</p>}{message&&<p role="status" style={{color:"#17613e"}}>{message}</p>}
    {loading?<p>Loading returned drafts…</p>:items.length===0?<div style={{padding:24,border:"1px solid var(--line)",background:"white"}}>No drafts currently require correction.</div>:
      items.map(item=><article key={item.id} style={{padding:20,border:"1px solid var(--line)",background:"white",display:"grid",gap:12}}>
        <div><div className="eyebrow">{item.sku} · Version {item.version}</div><h2 style={{fontSize:21,margin:"6px 0"}}>{item.name}</h2></div>
        <div style={{padding:14,background:"#f7f2e7",borderLeft:"3px solid #a77a30"}}><b style={{fontSize:12}}>Reviewer correction notes</b><p style={{fontSize:13,lineHeight:1.7,whiteSpace:"pre-wrap"}}>{item.correction_notes||"No notes supplied."}</p></div>
        <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(220px,1fr))",gap:10}}>
          {(["name","sku","brand","model_number","upc_ean","warranty_summary"] as const).map(key=><label key={key} style={{fontSize:11,fontWeight:700,textTransform:"capitalize"}}>{key.replaceAll("_"," ")}<input style={input} value={values[item.id]?.[key]??""} onChange={e=>change(item.id,key,e.target.value)}/></label>)}
          <label style={{fontSize:11,fontWeight:700}}>Condition<select style={input} value={values[item.id]?.condition??item.condition} onChange={e=>change(item.id,"condition",e.target.value)}>{["new","open_box","like_new","refurbished","used_excellent","used_good","used_fair","parts_only","damaged","inspection_required"].map(x=><option key={x} value={x}>{x.replaceAll("_"," ")}</option>)}</select></label>
          <label style={{fontSize:11,fontWeight:700}}>Tracking<select style={input} value={values[item.id]?.tracking_mode??item.tracking_mode} onChange={e=>change(item.id,"tracking_mode",e.target.value)}><option value="quantity">Quantity</option><option value="serialized">Serialized</option></select></label>
        </div>
        <label style={{fontSize:11,fontWeight:700}}>Description<textarea rows={3} style={input} value={values[item.id]?.description??""} onChange={e=>change(item.id,"description",e.target.value)}/></label>
        <label style={{fontSize:11,fontWeight:700}}>Specifications JSON<textarea rows={5} style={{...input,fontFamily:"monospace"}} value={values[item.id]?.specifications??"{}"} onChange={e=>change(item.id,"specifications",e.target.value)}/></label>
        <button disabled={!!saving} onClick={()=>void save(item)} style={{justifySelf:"start",padding:"11px 16px",border:0,background:"#164b3c",color:"white",fontSize:12,fontWeight:700}}>{saving===item.id?"Saving revision…":"Save revised draft"}</button>
      </article>)
    }
  </section>;
}
