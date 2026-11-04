"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/browser";

type TestStatus = "not_tested" | "pass" | "fail" | "not_applicable";
const checks = [
  ["battery_test", "Battery health"],
  ["screen_test", "Screen and touch"],
  ["camera_test", "Front and rear cameras"],
  ["charging_port_test", "Charging port"],
  ["buttons_audio_test", "Buttons and audio"],
  ["connectivity_test", "Wi-Fi, Bluetooth and cellular"],
  ["imei_serial_verification", "IMEI / serial match"],
] as const;

const inspectionTypes = [
  ["quality_check", "Quality check"],
  ["customer_return", "Customer return"],
  ["receiving_damage", "Receiving damage"],
  ["warehouse_damage", "Warehouse damage"],
  ["repair_intake", "Repair intake"],
  ["warranty_return", "Warranty return"],
];

export default function InspectionStationPage() {
  const [unitCode, setUnitCode] = useState("");
  const [battery, setBattery] = useState("");
  const [notes, setNotes] = useState("");
  const [reason, setReason] = useState("");
  const [inspectionType, setInspectionType] = useState("quality_check");
  const [activationLock, setActivationLock] = useState("not_tested");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [sessionEmail, setSessionEmail] = useState("");
  const [authMessage, setAuthMessage] = useState("");
  const [message, setMessage] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [results, setResults] = useState<Record<string, TestStatus>>(
    Object.fromEntries(checks.map(([key]) => [key, "not_tested"])),
  );
  const [photos, setPhotos] = useState<File[]>([]);
  const [pendingPhotoInspectionId, setPendingPhotoInspectionId] = useState("");
  const [history, setHistory] = useState<Array<Record<string, unknown>>>([]);
  const [historyMessage, setHistoryMessage] = useState("");
  const [historyLoading, setHistoryLoading] = useState(false);

  const previews = useMemo(
    () => photos.map(file => ({ file, url: URL.createObjectURL(file) })),
    [photos],
  );
  useEffect(() => () => previews.forEach(item => URL.revokeObjectURL(item.url)), [previews]);

  useEffect(() => {
    try {
      const supabase = getSupabaseBrowserClient();
      void supabase.auth.getSession().then(({ data, error }) => {
        if (error) setAuthMessage(error.message);
        setSessionEmail(data.session?.user.email ?? "");
      });
      const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
        setSessionEmail(session?.user.email ?? "");
      });
      return () => listener.subscription.unsubscribe();
    } catch (error) {
      setAuthMessage(error instanceof Error ? error.message : "Authentication is not configured.");
    }
  }, []);

  const allChecked =
    checks.every(([key]) => results[key] !== "not_tested") &&
    activationLock !== "not_tested";
  const hasFailure =
    Object.values(results).some(value => value === "fail") ||
    activationLock === "locked";
  const validBattery =
    battery === "" ||
    (/^\d{1,3}$/.test(battery) && Number(battery) >= 0 && Number(battery) <= 100);

  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setAuthMessage("");
    try {
      const supabase = getSupabaseBrowserClient();
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
      setPassword("");
    } catch (error) {
      setAuthMessage(error instanceof Error ? error.message : "Employee sign-in failed.");
    }
  }

  async function loadHistory() {
    setHistoryLoading(true);
    setHistoryMessage("");
    try {
      const { data, error } = await getSupabaseBrowserClient().auth.getSession();
      const token = data.session?.access_token;
      if (error || !token) throw new Error("Sign in again to view inspection history.");
      const response = await fetch("/api/employee/inventory/inspection/history", {
        headers: { Authorization: `Bearer ${token}` }, cache: "no-store",
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error ?? "Could not load inspection history.");
      setHistory(Array.isArray(result.inspections) ? result.inspections : []);
    } catch (error) {
      setHistoryMessage(error instanceof Error ? error.message : "Inspection history unavailable.");
    } finally {
      setHistoryLoading(false);
    }
  }

  async function signOut() {
    try {
      const { error } = await getSupabaseBrowserClient().auth.signOut();
      if (error) throw error;
      setAuthMessage("Signed out.");
    } catch (error) {
      setAuthMessage(error instanceof Error ? error.message : "Sign-out failed.");
    }
  }

  function addPhotos(files: FileList | null) {
    if (!files) return;
    const accepted = Array.from(files).filter(file =>
      ["image/jpeg", "image/png", "image/webp", "image/heic"].includes(file.type) &&
      file.size > 0 &&
      file.size <= 10 * 1024 * 1024,
    );
    setPhotos(current => [...current, ...accepted].slice(0, 8));
  }

  async function uploadInspectionPhotos(accessToken: string, inspectionId: string, selected: File[]) {
    const failed: File[] = [];
    for (const file of selected) {
      const form = new FormData();
      form.append("inspection_id", inspectionId);
      form.append("caption", file.name.slice(0, 500));
      form.append("file", file);
      try {
        const response = await fetch("/api/employee/inventory/inspection/photos", {
          method: "POST",
          headers: { Authorization: `Bearer ${accessToken}` },
          body: form,
        });
        if (!response.ok) failed.push(file);
      } catch {
        failed.push(file);
      }
    }
    return failed;
  }

  async function retryPhotoUploads() {
    if (!pendingPhotoInspectionId || photos.length === 0) return;
    setSubmitting(true);
    try {
      const { data, error } = await getSupabaseBrowserClient().auth.getSession();
      const accessToken = data.session?.access_token;
      if (error || !accessToken) throw new Error("Your employee session has expired. Sign in again.");
      const failed = await uploadInspectionPhotos(accessToken, pendingPhotoInspectionId, photos);
      setPhotos(failed);
      if (failed.length === 0) {
        setPendingPhotoInspectionId("");
        setMessage("All inspection photos were uploaded to private storage.");
      } else {
        setMessage(`${failed.length} photo(s) could not be uploaded. You can retry the remaining photos.`);
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Photo upload failed.");
    } finally {
      setSubmitting(false);
    }
  }

  async function submitInspection(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");
    if (!sessionEmail) {
      setMessage("Sign in with your employee account before submitting.");
      return;
    }
    if (reason.trim().length < 5 || !allChecked || !validBattery) {
      setMessage("Complete the required reason, checklist and battery fields.");
      return;
    }

    setSubmitting(true);
    try {
      const { data, error } = await getSupabaseBrowserClient().auth.getSession();
      const accessToken = data.session?.access_token;
      if (error || !accessToken) {
        throw new Error("Your employee session has expired. Sign in again.");
      }

      const response = await fetch("/api/employee/inventory/inspection", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          reference: unitCode.trim(),
          inspection_type: inspectionType,
          reason: reason.trim(),
          findings: {
            checklist: results,
            activation_lock_status: activationLock,
            has_failed_test: hasFailure,
          },
          battery_health_percent: battery === "" ? null : Number(battery),
          battery_test: results.battery_test,
          screen_test: results.screen_test,
          camera_test: results.camera_test,
          charging_port_test: results.charging_port_test,
          buttons_audio_test: results.buttons_audio_test,
          connectivity_test: results.connectivity_test,
          imei_serial_verification: results.imei_serial_verification,
          activation_lock_status: activationLock,
          notes,
        }),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error ?? "Inspection submission failed.");

      const failedPhotos = photos.length > 0
        ? await uploadInspectionPhotos(accessToken, result.inspection_id, photos)
        : [];
      setPhotos(failedPhotos);
      setPendingPhotoInspectionId(failedPhotos.length > 0 ? result.inspection_id : "");
      setMessage(
        `Inspection submitted. Record ID: ${result.inspection_id}. Device quarantined pending manager review. ` +
        (photos.length === 0 ? "No photos were attached." :
          failedPhotos.length === 0 ? `${photos.length} photo(s) uploaded to private storage.` :
          `${failedPhotos.length} photo(s) still need upload; retry below.`)
      );
      setUnitCode("");
      setBattery("");
      setNotes("");
      setReason("");
      setResults(Object.fromEntries(checks.map(([key]) => [key, "not_tested"])));
      setActivationLock("not_tested");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Inspection submission failed.");
    } finally {
      setSubmitting(false);
    }
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
        <p style={{ color: "#586579", lineHeight: 1.6, maxWidth: 720 }}>Submit a serialized-device inspection. Successful submissions are checked by the server and place the unit in quarantine pending manager review.</p>

        <section style={{ background: "white", border: "1px solid #e5e9f0", borderRadius: 14, padding: 22, margin: "24px 0" }}>
          <h2 style={{ marginTop: 0 }}>Employee sign-in</h2>
          {sessionEmail ? (
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
              <span>Signed in as <b>{sessionEmail}</b></span>
              <button type="button" onClick={signOut} style={{ padding: "9px 14px", borderRadius: 8 }}>Sign out</button>
            </div>
          ) : (
            <form onSubmit={signIn} style={{ display: "grid", gap: 10, maxWidth: 420 }}>
              <input required type="email" autoComplete="username" value={email} onChange={e => setEmail(e.target.value)} placeholder="Employee email" style={{ padding: 12, border: "1px solid #cbd3df", borderRadius: 8 }} />
              <input required type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} placeholder="Password" style={{ padding: 12, border: "1px solid #cbd3df", borderRadius: 8 }} />
              <button type="submit" style={{ padding: 12, border: 0, borderRadius: 8, background: "#173b70", color: "white", fontWeight: 700 }}>Sign in</button>
            </form>
          )}
          {authMessage && <p role="status">{authMessage}</p>}
        </section>

        <div style={{ margin: "20px 0", padding: 16, border: "1px solid #e4c98a", background: "#fff8e8", borderRadius: 12, color: "#704d12" }}>
          <b>Photo upload is not enabled.</b>
          <p style={{ margin: "6px 0 0", lineHeight: 1.5 }}>Photos selected below remain local to this browser and are not attached to the submitted inspection. Do not treat local previews as stored evidence.</p>
        </div>

        <section style={{ background: "white", border: "1px solid #e5e9f0", borderRadius: 14, padding: 22, marginBottom: 20 }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
            <div><h2 style={{ margin: 0 }}>Inspection history</h2><p style={{ margin: "6px 0 0", color: "#586579" }}>Authorized records available to your employee account, newest first.</p></div>
            <button type="button" onClick={loadHistory} disabled={!sessionEmail || historyLoading} style={{ padding: "10px 14px", border: 0, borderRadius: 8, background: "#173b70", color: "white", fontWeight: 700 }}>{historyLoading ? "Loading…" : "Refresh history"}</button>
          </div>
          {historyMessage && <p role="status">{historyMessage}</p>}
          {!history.length && !historyMessage && <p style={{ color: "#586579" }}>Select Refresh history to view records.</p>}
          <div style={{ display: "grid", gap: 10, marginTop: 14 }}>
            {history.map(item => <article key={String(item.id)} style={{ border: "1px solid #e5e9f0", borderRadius: 10, padding: 14 }}>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                <b>{String(item.inspection_reference ?? item.id)}</b>
                <span style={{ textTransform: "capitalize" }}>{String(item.disposition ?? "unknown").replaceAll("_", " ")}</span>
              </div>
              <p style={{ margin: "7px 0", color: "#586579" }}>{String(item.inspection_type ?? "").replaceAll("_", " ")} · {String(item.reason ?? "")}</p>
              <small style={{ color: "#586579" }}>Created {item.created_at ? new Date(String(item.created_at)).toLocaleString() : "date unavailable"}</small>
            </article>)}
          </div>
        </section>

        <form onSubmit={submitInspection} style={{ display: "grid", gap: 20 }}>
          <section style={{ background: "white", border: "1px solid #e5e9f0", borderRadius: 14, padding: 22 }}>
            <h2 style={{ marginTop: 0 }}>01 · Identify device</h2>
            <label style={{ display: "grid", gap: 8, fontWeight: 650, marginBottom: 14 }}>Inspection type
              <select value={inspectionType} onChange={e => setInspectionType(e.target.value)} style={{ padding: 12, border: "1px solid #cbd3df", borderRadius: 8 }}>
                {inspectionTypes.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>
            <label style={{ display: "grid", gap: 8, fontWeight: 650 }}>Scan or enter IMEI / serial / unit barcode
              <input required value={unitCode} onChange={e => setUnitCode(e.target.value.trimStart())} placeholder="Device identifier" autoComplete="off" style={{ padding: 14, border: "1px solid #cbd3df", borderRadius: 9, fontSize: 16 }} />
            </label>
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
            <label style={{ display: "grid", gap: 8, marginTop: 18, fontWeight: 650 }}>Activation lock status
              <select value={activationLock} onChange={e => setActivationLock(e.target.value)} style={{ padding: 12, border: "1px solid #cbd3df", borderRadius: 8, maxWidth: 260 }}>
                <option value="not_tested">Not tested</option><option value="clear">Clear</option><option value="locked">Locked</option><option value="not_applicable">Not applicable</option>
              </select>
            </label>
            <label style={{ display: "grid", gap: 8, marginTop: 18, fontWeight: 650 }}>Battery health (%)
              <input inputMode="numeric" value={battery} onChange={e => setBattery(e.target.value)} placeholder="0–100" style={{ padding: 12, border: "1px solid #cbd3df", borderRadius: 8, maxWidth: 220 }} />
            </label>
            {!validBattery && <p role="alert" style={{ color: "#b42318" }}>Enter a whole-number battery percentage from 0 to 100.</p>}
          </section>

          <section style={{ background: "white", border: "1px solid #e5e9f0", borderRadius: 14, padding: 22 }}>
            <h2 style={{ marginTop: 0 }}>03 · Condition and evidence</h2>
            <label style={{ display: "grid", gap: 8, fontWeight: 650 }}>Inspection reason (required)
              <textarea required minLength={5} maxLength={4000} value={reason} onChange={e => setReason(e.target.value)} rows={2} placeholder="Why is this device being inspected?" style={{ padding: 12, border: "1px solid #cbd3df", borderRadius: 8, resize: "vertical" }} />
            </label>
            <label style={{ display: "grid", gap: 8, marginTop: 14, fontWeight: 650 }}>Defects, cosmetic condition and test notes
              <textarea value={notes} onChange={e => setNotes(e.target.value)} maxLength={4000} rows={5} placeholder="Describe scratches, cracks, missing parts or faults…" style={{ padding: 12, border: "1px solid #cbd3df", borderRadius: 8, resize: "vertical" }} />
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
          </section>

          <section style={{ background: "white", border: "1px solid #e5e9f0", borderRadius: 14, padding: 22 }}>
            <h2 style={{ marginTop: 0 }}>04 · Review and submit</h2>
            <p style={{ color: "#586579" }}>{!allChecked ? "Complete every functional test and activation-lock status." : hasFailure ? "One or more checks failed or the device is locked. Submission will quarantine the unit for manager review." : "Submission will quarantine the unit pending manager review; it cannot return to sale inventory through this form."}</p>
            <button disabled={!sessionEmail || submitting || !unitCode.trim() || !allChecked || !validBattery || reason.trim().length < 5} type="submit" style={{ border: 0, borderRadius: 9, padding: "14px 20px", background: !sessionEmail || submitting || !unitCode.trim() || !allChecked || !validBattery || reason.trim().length < 5 ? "#aeb8c7" : "#173b70", color: "white", fontWeight: 750, cursor: "pointer" }}>
              {submitting ? "Submitting…" : "Submit inspection and quarantine device"}
            </button>
            {message && <p role="status" style={{ marginTop: 14, padding: 14, background: "#eef3fa", borderRadius: 9, lineHeight: 1.55 }}>{message}</p>}
            {pendingPhotoInspectionId && photos.length > 0 && (
              <button type="button" onClick={retryPhotoUploads} disabled={submitting} style={{ marginTop: 12, border: 0, borderRadius: 9, padding: "12px 16px", background: "#8a5a12", color: "white", fontWeight: 700 }}>
                {submitting ? "Uploading…" : `Retry ${photos.length} remaining photo(s)`}
              </button>
            )}
          </section>
        </form>
      </section>
    </main>
  );
}
