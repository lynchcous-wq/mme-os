"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";

type TestStatus = "not_tested" | "pass" | "fail" | "not_applicable";
const checks = [
  ["battery_test", "Battery health"],
  ["screen_test", "Screen and touch"],
  ["camera_test", "Front and rear cameras"],
  ["charging_port_test", "Charging port"],
  ["buttons_audio_test", "Buttons and audio"],
  ["connectivity_test", "Wi-Fi, Bluetooth and cellular"],
  ["imei_serial_verification", "IMEI / serial match"],
  ["activation_lock_status", "Activation lock"],
] as const;

export default function InspectionStationPage() {
  const [unitCode, setUnitCode] = useState("");
  const [battery, setBattery] = useState("");
  const [notes, setNotes] = useState("");
  const [results, setResults] = useState<Record<string, TestStatus>>(
    Object.fromEntries(checks.map(([key]) => [key, "not_tested"])),
  );
  const [photos, setPhotos] = useState<File[]>([]);
  const [draftMessage, setDraftMessage] = useState("");

  const previews = useMemo(() => photos.map(file => ({ file, url: URL.createObjectURL(file) })), [photos]);
  useEffect(() => () => previews.forEach(item => URL.revokeObjectURL(item.url)), [previews]);

  const allChecked = checks.every(([key]) => results[key] !== "not_tested");
  const hasFailure = Object.values(results).some(value => value === "fail");
  const validBattery = battery === "" || (/^\d{1,3}$/.test(battery) && Number(battery) >= 0 && Number(battery) <= 100);

  function addPhotos(files: FileList | null) {
    if (!files) return;
    const accepted = Array.from(files).filter(file =>
      ["image/jpeg", "image/png", "image/webp", "image/heic"].includes(file.type) && file.size <= 10 * 1024 * 1024,
    );
    setPhotos(current => [...current, ...accepted].slice(0, 8));
  }

  function prepareDraft(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setDraftMessage(
      "Draft reviewed locally. It has not been saved or submitted. Secure employee-session verification, inspection authorization and private photo upload must be connected before this station can write inspection records.",
    );
  }

  return (
    <main style={{ minHeight: "100vh", background: "#f5f6f8", color: "#172033" }}>
      <header style={{ background: "#101b32", color: "white", padding: "18px 5vw", display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16 }}>
        <Link href="/" style={{ color: "white", textDecoration: "none", fontWeight: 800, letterSpacing: ".08em" }}>MME · EMPLOYEE OPERATIONS</Link>
        <Link href="/products" style={{ color: "#dce6f7" }}>Storefront ↗</Link>
      </header>
      <section style={{ maxWidth: 980, margin: "0 auto", padding: "42px 20px 80px" }}>
        <p style={{ color: "#526b91", fontSize: 12, fontWeight: 800, letterSpacing: ".14em" }}>BUILD 001 / INVENTORY CONTROL</p>
        <h1 style={{ fontSize: "clamp(30px,5vw,46px)", margin: "8px 0" }}>Device inspection station</h1>
        <p style={{ color: "#586579", lineHeight: 1.6, maxWidth: 720 }}>Prepare an inspection record for one serialized device. Record the identity match, functional checks, condition notes and photo evidence before a manager reviews the unit.</p>
        <div style={{ margin: "24px 0", padding: 16, border: "1px solid #e4c98a", background: "#fff8e8", borderRadius: 12, color: "#704d12" }}>
          <b>Draft workspace — not connected to live submission.</b>
          <p style={{ margin: "6px 0 0", lineHeight: 1.5 }}>This interface does not save records or upload photos yet. Do not enter real customer data or rely on it for inventory decisions until secure employee authentication and server-side submission are enabled.</p>
        </div>
        <form onSubmit={prepareDraft} style={{ display: "grid", gap: 20 }}>
          <section style={{ background: "white", border: "1px solid #e5e9f0", borderRadius: 14, padding: 22 }}>
            <h2 style={{ marginTop: 0 }}>01 · Identify device</h2>
            <label style={{ display: "grid", gap: 8, fontWeight: 650 }}>Scan or enter IMEI / serial / unit barcode
              <input required value={unitCode} onChange={e => setUnitCode(e.target.value.trimStart())} placeholder="Scan barcode or enter device identifier" autoComplete="off" style={{ padding: 14, border: "1px solid #cbd3df", borderRadius: 9, fontSize: 16 }} />
            </label>
            <p style={{ color: "#68758a", fontSize: 13 }}>Use a connected barcode scanner or the device camera’s barcode scanner when that integration is enabled.</p>
          </section>
          <section style={{ background: "white", border: "1px solid #e5e9f0", borderRadius: 14, padding: 22 }}>
            <h2 style={{ marginTop: 0 }}>02 · Functional checklist</h2>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(230px,1fr))", gap: 14 }}>
              {checks.map(([key, title]) => <label key={key} style={{ display: "grid", gap: 7, fontWeight: 650 }}>{title}
                <select value={results[key]} onChange={e => setResults(current => ({ ...current, [key]: e.target.value as TestStatus }))} style={{ padding: 11, border: "1px solid #cbd3df", borderRadius: 8, background: "white" }}>
                  <option value="not_tested">Not tested</option><option value="pass">Pass</option><option value="fail">Fail</option><option value="not_applicable">Not applicable</option>
                </select>
              </label>)}
            </div>
            <label style={{ display: "grid", gap: 8, marginTop: 18, fontWeight: 650 }}>Battery health (%)
              <input inputMode="numeric" value={battery} onChange={e => setBattery(e.target.value)} placeholder="0–100" style={{ padding: 12, border: "1px solid #cbd3df", borderRadius: 8, maxWidth: 220 }} />
            </label>
            {!validBattery && <p role="alert" style={{ color: "#b42318" }}>Enter a whole-number battery percentage from 0 to 100.</p>}
          </section>
          <section style={{ background: "white", border: "1px solid #e5e9f0", borderRadius: 14, padding: 22 }}>
            <h2 style={{ marginTop: 0 }}>03 · Condition and evidence</h2>
            <label style={{ display: "grid", gap: 8, fontWeight: 650 }}>Defects, cosmetic condition and test notes
              <textarea value={notes} onChange={e => setNotes(e.target.value)} maxLength={4000} rows={5} placeholder="Describe scratches, cracks, missing parts, intermittent faults or other findings…" style={{ padding: 12, border: "1px solid #cbd3df", borderRadius: 8, resize: "vertical" }} />
            </label>
            <label style={{ display: "grid", gap: 8, marginTop: 16, fontWeight: 650 }}>Inspection photos (up to 8; 10 MB each)
              <input type="file" accept="image/jpeg,image/png,image/webp,image/heic" capture="environment" multiple onChange={e => addPhotos(e.target.files)} />
            </label>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 10, marginTop: 12 }}>
              {previews.map((item, index) => <figure key={index} style={{ margin: 0, width: 110 }}>
                <img src={item.url} alt={item.file.name} style={{ width: 110, height: 90, objectFit: "cover", borderRadius: 8 }} />
                <figcaption style={{ fontSize: 11, overflowWrap: "anywhere" }}>{item.file.name}</figcaption>
                <button type="button" onClick={() => setPhotos(current => current.filter((_, i) => i !== index))} style={{ border: 0, background: "transparent", color: "#a12b2b", padding: "4px 0" }}>Remove</button>
              </figure>)}
            </div>
            <p style={{ color: "#68758a", fontSize: 13 }}>Only approved image formats are accepted. Photo previews stay in this browser session and are not uploaded.</p>
          </section>
          <section style={{ background: "white", border: "1px solid #e5e9f0", borderRadius: 14, padding: 22 }}>
            <h2 style={{ marginTop: 0 }}>04 · Review disposition</h2>
            <p style={{ color: "#586579" }}>{!allChecked ? "Complete every checklist item before preparing the draft." : hasFailure ? "One or more checks failed. This unit should be routed for manager review and possible quarantine." : "Checklist is complete. A manager must still review the inspection before the device can return to sale inventory."}</p>
            <button disabled={!unitCode.trim() || !allChecked || !validBattery} type="submit" style={{ border: 0, borderRadius: 9, padding: "14px 20px", background: !unitCode.trim() || !allChecked || !validBattery ? "#aeb8c7" : "#173b70", color: "white", fontWeight: 750, cursor: "pointer" }}>Prepare inspection draft</button>
            {draftMessage && <p role="status" style={{ marginTop: 14, padding: 14, background: "#eef3fa", borderRadius: 9, lineHeight: 1.55 }}>{draftMessage}</p>}
          </section>
        </form>
      </section>
    </main>
  );
}
