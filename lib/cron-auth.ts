import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Authenticates scheduled worker requests.
 * Supports the existing Vercel Bearer secret and timestamped HMAC requests
 * from Supabase Cron. The HMAC keeps the raw secret out of pg_net's queue.
 */
export async function verifyCronRequest(request: Request): Promise<boolean> {
  const secret = process.env.CRON_SECRET;
  if (!secret || secret.length < 32) return false;

  const authorization = request.headers.get("authorization") ?? "";
  if (authorization.startsWith("Bearer ")) {
    const supplied = Buffer.from(authorization.slice(7));
    const expected = Buffer.from(secret);
    if (supplied.length === expected.length && timingSafeEqual(supplied, expected)) return true;
  }

  const timestamp = request.headers.get("x-mme-cron-timestamp") ?? "";
  const signature = request.headers.get("x-mme-cron-signature") ?? "";
  if (!/^\d{10}$/.test(timestamp) || !/^[a-f0-9]{64}$/i.test(signature)) return false;

  const epoch = Number(timestamp);
  if (!Number.isSafeInteger(epoch) || Math.abs(Math.floor(Date.now() / 1000) - epoch) > 300) return false;

  const body = await request.clone().text();
  if (body.length > 2048 || body !== "{}") return false;

  const expected = createHmac("sha256", secret).update(timestamp + "." + body, "utf8").digest();
  const supplied = Buffer.from(signature, "hex");
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}
