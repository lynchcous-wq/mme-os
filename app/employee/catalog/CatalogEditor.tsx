"use client";

import { useMemo, useState } from "react";
import type { CSSProperties } from "react";

const categories = [["televisions","Televisions"],["laptops","Laptops"],["tablets","Tablets"],["cellphones","Cellphones"],["smartwatches","Smartwatches"],["accessories","Accessories"],["audio","Audio"],["gaming","Gaming"],["smart-home","Smart Home"],["services-subscriptions","Services and Subscriptions"]];
const conditions = [
  ["new","New"],["open_box","Open Box"],["like_new","Like New"],["refurbished","Refurbished"],
  ["used_excellent","Used — Excellent"],["used_good","Used — Good"],["used_fair","Used — Fair"],
  ["parts_only","Parts Only"],["damaged","Damaged"],["inspection_required","Inspection Required"]
];

export default function CatalogEditor() {
  const [name,setName] = useState("");
  const [sku,setSku] = useState("");
  const [category,setCategory] = useState("televisions");
  const [brand,setBrand] = useState("");
  const [model,setModel] = useState("");
  const [upc,setUpc] = useState("");
  const [condition,setCondition] = useState("inspection_required");
  const [tracking,setTracking] = useState("quantity");
  const [description,setDescription] = useState("");
  const [specs,setSpecs] = useState("{}");
  const [warranty,setWarranty] = useState("");
  const [media,setMedia] = useState("");
  const [error,setError] = useState("");
  const [preview,setPreview] = useState(false);
  const [saving,setSaving] = useState(false);
  const [saveMessage,setSaveMessage] = useState("");
  const [savedProductId,setSavedProductId] = useState("");
  const [submitting,setSubmitting] = useState(false);

  const parsedSpecs = useMemo(() => {
    try {
      const value = JSON.parse(specs);
      return value && typeof value === "object" && !Array.isArray(value) ? value : null;
    } catch { return null; }
  },[specs]);

  function validate() {
    if (!name.trim() || !sku.trim()) return "Product name and SKU are required.";
    if (!parsedSpecs) return "Specifications must be a valid JSON object, for example { \"ram\": \"16GB\" }.";
    if (media.trim() && !/^https:\/\//i.test(media.trim())) return "Media link must use HTTPS.";
    return "";
  }

  const payload = {
    name:name.trim(), sku:sku.trim(), category, brand:brand.trim() || null,
    model_number:model.trim() || null, upc_ean:upc.trim() || null,
    condition, tracking_mode:tracking, description:description.trim() || null,
    specifications:parsedSpecs, warranty_summary:warranty.trim() || null,
    media_url:media.trim() || null, catalog_status:"draft"
  };

  return <div className="catalog-layout" style={{display:"grid",gridTemplateColumns:"minmax(0,1.3fr) minmax(260px,.7fr)",gap:22,alignItems:"start"}}>
    <form onSubmit={async (event)=>{event.preventDefault();const message=validate();setError(message);setSaveMessage("");setPreview(false);if(message)return;setSaving(true);try{const response=await fetch("/api/employee/catalog",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(payload)});const result=await response.json();if(!response.ok)throw new Error(result.error || "Draft could not be saved.");setSavedProductId(result.product.id);setSaveMessage("Draft saved. Submit it for approval when ready.");setName("");setSku("");setBrand("");setModel("");setUpc("");setDescription("");setSpecs("{}");setWarranty("");setMedia("");}catch(cause){setError(cause instanceof Error ? cause.message : "Draft could not be saved.");}finally{setSaving(false);}}} style={{background:"white",border:"1px solid var(--line)",padding:22,borderRadius:5,display:"grid",gridTemplateColumns:"1fr 1fr",gap:14}}>
      <label style={field}>Product name *<input required value={name} onChange={e=>setName(e.target.value)} placeholder="e.g. 55-inch 4K Smart TV" style={input}/></label>
      <label style={field}>MME SKU *<input required value={sku} onChange={e=>setSku(e.target.value)} placeholder="MME-TV-0001" style={input}/></label>
      <label style={field}>Category<select value={category} onChange={e=>setCategory(e.target.value)} style={input}>{categories.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>
      <label style={field}>Condition<select value={condition} onChange={e=>setCondition(e.target.value)} style={input}>{conditions.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label>
      <label style={field}>Brand<input value={brand} onChange={e=>setBrand(e.target.value)} placeholder="Manufacturer brand" style={input}/></label>
      <label style={field}>Model number<input value={model} onChange={e=>setModel(e.target.value)} placeholder="Model / part number" style={input}/></label>
      <label style={field}>UPC / EAN<input value={upc} onChange={e=>setUpc(e.target.value)} placeholder="Barcode identifier" style={input}/></label>
      <label style={field}>Tracking method<select value={tracking} onChange={e=>setTracking(e.target.value)} style={input}><option value="quantity">Quantity managed</option><option value="serialized">Serialized unit tracking</option></select></label>
      <label style={{...field,gridColumn:"1 / -1"}}>Product description<textarea value={description} onChange={e=>setDescription(e.target.value)} rows={3} placeholder="Customer-facing product description" style={{...input,resize:"vertical"}}/></label>
      <label style={{...field,gridColumn:"1 / -1"}}>Specifications (JSON)<textarea value={specs} onChange={e=>setSpecs(e.target.value)} rows={4} style={{...input,fontFamily:"monospace",resize:"vertical"}}/></label>
      <label style={field}>Warranty summary<input value={warranty} onChange={e=>setWarranty(e.target.value)} placeholder="e.g. 90-day limited warranty" style={input}/></label>
      <label style={field}>Image / demo video HTTPS link<input value={media} onChange={e=>setMedia(e.target.value)} placeholder="https://..." style={input}/></label>
      {error && <p role="alert" style={{gridColumn:"1 / -1",color:"#a33",fontSize:12,margin:0}}>{error}</p>}
      {saveMessage && <p role="status" style={{gridColumn:"1 / -1",color:"#17613e",fontSize:12,margin:0}}>{saveMessage}</p>}
      {savedProductId && <button type="button" disabled={submitting} onClick={async()=>{setSubmitting(true);setError("");try{const response=await fetch("/api/employee/catalog/"+savedProductId+"/submit",{method:"POST"});const result=await response.json();if(!response.ok)throw new Error(result.error||"Submission failed.");setSaveMessage("Draft submitted for review: "+result.product.name);setSavedProductId("");}catch(cause){setError(cause instanceof Error?cause.message:"Submission failed.");}finally{setSubmitting(false);}}} style={{gridColumn:"1 / -1",padding:11,border:0,borderRadius:3,background:"#164b3c",color:"white",fontSize:11,fontWeight:700}}>{submitting?"Submitting…":"Submit saved draft for approval"}</button>}
      <div style={{gridColumn:"1 / -1",display:"flex",gap:10,alignItems:"center",flexWrap:"wrap"}}>
        <button type="submit" style={primary} disabled={saving}>{saving ? "Saving draft…" : "Save draft"}</button>
        <button type="button" onClick={()=>{const message=validate();setError(message);setPreview(!message);}} style={secondary}>Preview JSON</button>
        <button type="button" onClick={()=>{setName("");setSku("");setBrand("");setModel("");setUpc("");setDescription("");setSpecs("{}");setWarranty("");setMedia("");setError("");setPreview(false);}} style={secondary}>Clear form</button>
        <span style={{fontSize:10,color:"var(--muted)"}}>Drafts save to MME catalog · not published</span>
      </div>
    </form>
    <aside style={{background:"#f3f0e9",border:"1px solid var(--line)",padding:20,borderRadius:5}}>
      <div className="eyebrow">Workflow controls</div>
      <h2 style={{fontFamily:"Manrope,sans-serif",fontSize:22,margin:"10px 0"}}>Draft → review → publish</h2>
      <ol style={{paddingLeft:18,color:"#56615a",fontSize:12,lineHeight:2}}>
        <li>Employee prepares product information.</li><li>System validates required fields.</li><li>Authorized reviewer checks accuracy.</li><li>Approved product can be published.</li>
      </ol>
      <div style={{paddingTop:14,borderTop:"1px solid var(--line)",fontSize:11,color:"var(--muted)",lineHeight:1.8}}>No stock quantity, acquisition cost, landed cost, selling price, IMEI or full serial number belongs in this form.</div>
      {preview && <div style={{marginTop:18,paddingTop:14,borderTop:"1px solid var(--line)"}}><b style={{fontSize:12}}>Validated draft preview</b><pre style={{whiteSpace:"pre-wrap",overflowWrap:"anywhere",fontSize:10,lineHeight:1.6,background:"white",padding:12,borderRadius:3}}>{JSON.stringify(payload,null,2)}</pre></div>}
    </aside>
    <style jsx>{`
      @media(max-width:760px){.catalog-layout{grid-template-columns:1fr!important}}
    `}</style>
  </div>;
}

const field: CSSProperties = {display:"flex",flexDirection:"column",gap:6,fontSize:11,fontWeight:600,color:"#34413b"};
const input: CSSProperties = {width:"100%",minWidth:0,padding:"11px 10px",border:"1px solid #dcded8",borderRadius:3,background:"#fff",font:"12px 'DM Sans',sans-serif",color:"#17211f"};
const primary: CSSProperties = {padding:"11px 14px",border:0,borderRadius:3,background:"#164b3c",color:"white",fontSize:11,fontWeight:700,cursor:"pointer"};
const secondary: CSSProperties = {padding:"10px 13px",border:"1px solid #cdd2cc",borderRadius:3,background:"white",color:"#34413b",fontSize:11,cursor:"pointer"};
