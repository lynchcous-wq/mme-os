import { createClient } from "npm:@supabase/supabase-js@2.49.1";

type Notice = {
  id: string; order_id: string; channel: "email" | "sms"; recipient_snapshot: string;
  template_key: string; idempotency_key: string; template_data: Record<string, unknown>;
  attempt_count: number;
};
const json = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});
function safeEqual(a: string, b: string) {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}
function escapeHtml(value: unknown) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[c]!);
}
function emailContent(row: Notice) {
  const d = row.template_data ?? {};
  const name = escapeHtml(d.customer_name || "there");
  const order = escapeHtml(row.order_id);
  const method = d.fulfillment_method === "pickup" ? "local pickup" : "shipping";
  const tracking = typeof d.tracking_url === "string" && d.tracking_url.startsWith("https://")
    ? d.tracking_url : null;
  const trackingHtml = tracking ? '<p><a href="' + escapeHtml(tracking) + '">Track your shipment</a></p>' : "";
  const map: Record<string, { subject: string; message: string }> = {
    order_paid: { subject: "MME order confirmed", message: "We received your payment and are preparing your order." },
    order_picking: { subject: "MME order is being prepared", message: "Our team has started preparing your order." },
    order_shipped: { subject: "Your MME order has shipped", message: "Your order is on its way." },
    pickup_ready: { subject: "Your MME order is ready for pickup", message: "Your order is ready. Bring your order reference and follow the pickup verification instructions." },
    pickup_reminder: { subject: "MME pickup reminder", message: "Your order is waiting for pickup. Please contact the store if you need assistance." },
    order_delivered: { subject: "Your MME order was delivered", message: "The carrier has marked your order as delivered." },
    order_picked_up: { subject: "MME pickup completed", message: "Your order handoff has been recorded. Thank you for shopping with MME." },
    fulfillment_exception: { subject: "Update about your MME order", message: "There is an update affecting your order. Our team will follow up with you." },
  };
  const item = map[row.template_key];
  if (!item) throw new Error("unsupported_template");
  const total = Number.isSafeInteger(d.total_cents) ? (Number(d.total_cents) / 100).toFixed(2) : null;
  const details = [
    '<p><strong>Order reference:</strong> ' + order + '</p>',
    '<p><strong>Fulfillment:</strong> ' + escapeHtml(method) + '</p>',
    total ? '<p><strong>Total:</strong> $' + total + '</p>' : "",
    d.tracking_number ? '<p><strong>Tracking:</strong> ' + escapeHtml(d.tracking_number) + '</p>' : "",
    trackingHtml,
    d.pickup_location_name ? '<p><strong>Pickup location:</strong> ' + escapeHtml(d.pickup_location_name) + '</p>' : "",
  ].join("");
  const html = '<div style="font-family:Arial,sans-serif;line-height:1.6;color:#172033"><h1>' +
    escapeHtml(item.subject) + '</h1><p>Hello ' + name + ',</p><p>' + escapeHtml(item.message) +
    '</p>' + details + '<p>Thank you,<br>Much More Electronics</p></div>';
  const text = 'Hello ' + String(d.customer_name || "there") + ',\n\n' + item.message +
    '\nOrder reference: ' + row.order_id + '\nFulfillment: ' + method +
    (total ? '\nTotal: $' + total : "") +
    (d.tracking_number ? '\nTracking: ' + String(d.tracking_number) : "") +
    (tracking ? '\nTrack: ' + tracking : "") + '\n\nMuch More Electronics';
  return { subject: item.subject, html, text };
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("MME_CUSTOMER_NOTIFICATION_SECRET") ?? "";
  const supplied = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (secret.length < 32 || !safeEqual(secret, supplied)) return json({ error: "unauthorized" }, 401);
  const url = Deno.env.get("SUPABASE_URL"), serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY"), from = Deno.env.get("MME_EMAIL_FROM");
  if (!url || !serviceKey || !resendKey || !from || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(from)) {
    return json({ error: "notification_service_not_configured" }, 503);
  }
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const workerId = "customer-email-" + crypto.randomUUID();
  const { data: rows, error: claimError } = await admin.rpc("mme_claim_customer_notifications", {
    p_worker_id: workerId, p_batch_size: 25, p_lease_seconds: 120,
  });
  if (claimError) return json({ error: "notification_claim_failed" }, 500);
  const result = { claimed: rows?.length ?? 0, sent: 0, failed: 0, suppressed: 0 };
  for (const row of (rows ?? []) as Notice[]) {
    if (row.channel !== "email") {
      await admin.rpc("mme_fail_customer_notification", {
        p_notification_id: row.id, p_worker_id: workerId, p_error_code: "channel_not_configured", p_retryable: false,
      });
      result.suppressed++;
      continue;
    }
    try {
      const content = emailContent(row);
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: "Bearer " + resendKey,
          "Content-Type": "application/json",
          "Idempotency-Key": row.idempotency_key,
        },
        body: JSON.stringify({
          from, to: [row.recipient_snapshot], subject: content.subject,
          html: content.html, text: content.text,
          tags: [{ name: "mme_order_id", value: row.order_id }],
        }),
        signal: AbortSignal.timeout(10000),
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok || typeof payload.id !== "string") {
        const retryable = response.status === 429 || response.status >= 500 || response.status === 0;
        await admin.rpc("mme_fail_customer_notification", {
          p_notification_id: row.id, p_worker_id: workerId,
          p_error_code: "email_provider_http_" + response.status, p_retryable: retryable,
        });
        result.failed++;
        continue;
      }
      const { data: completed, error: completeError } = await admin.rpc("mme_complete_customer_notification", {
        p_notification_id: row.id, p_worker_id: workerId, p_provider: "resend", p_provider_message_id: payload.id,
      });
      if (completeError || completed !== true) {
        // Resend idempotency key prevents a duplicate send when the lease is retried.
        result.failed++;
        continue;
      }
      result.sent++;
    } catch {
      await admin.rpc("mme_fail_customer_notification", {
        p_notification_id: row.id, p_worker_id: workerId, p_error_code: "email_provider_network_error", p_retryable: true,
      });
      result.failed++;
    }
  }
  return json({ success: true, ...result });
});
