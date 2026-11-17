import { createHmac } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";

type RateLimitResult = { allowed: boolean; retryAfterSeconds: number };

const RATE_LIMIT_SCRIPT = [
  "local current = redis.call('INCR', KEYS[1])",
  "if current == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end",
  "local ttl = redis.call('TTL', KEYS[1])",
  "return { current, ttl }",
].join("\n");

/**
 * Durable, atomic fixed-window limiter for public authentication endpoints.
 * Fails closed when its private Upstash Redis configuration or trusted client
 * address is unavailable. Never logs or stores the raw client IP.
 */
async function checkRateLimit(
  request: NextRequest,
  bucket: string,
  maximum: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  const redisUrl = process.env.UPSTASH_REDIS_REST_URL;
  const redisToken = process.env.UPSTASH_REDIS_REST_TOKEN;
  const hashSecret = process.env.MME_RATE_LIMIT_HASH_SECRET;

  if (!redisUrl || !redisToken || !hashSecret || hashSecret.length < 32) {
    throw new Error("Authentication rate limiting is not configured.");
  }

  const trustedAddress = request.headers.get("x-real-ip")?.trim()
    || request.headers.get("x-vercel-forwarded-for")?.split(",")[0]?.trim()
    || request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();

  if (!trustedAddress || trustedAddress.length > 128) {
    throw new Error("Trusted client address is unavailable.");
  }

  const digest = createHmac("sha256", hashSecret)
    .update(trustedAddress)
    .digest("hex");

  const key = `mme:auth-rate:v1:${bucket}:${digest}`;
  const endpoint = redisUrl.replace(/\/$/, "");
  const commandUrl = `${endpoint}/eval/${encodeURIComponent(RATE_LIMIT_SCRIPT)}/1/${encodeURIComponent(key)}/${windowSeconds}`;

  const response = await fetch(commandUrl, {
    method: "POST",
    headers: { Authorization: `Bearer ${redisToken}` },
    cache: "no-store",
    signal: AbortSignal.timeout(2500),
  });

  if (!response.ok) throw new Error("Authentication rate-limit service is unavailable.");

  const payload = await response.json() as { result?: unknown; error?: string };
  if (payload.error || !Array.isArray(payload.result) ||
      typeof payload.result[0] !== "number" || typeof payload.result[1] !== "number") {
    throw new Error("Authentication rate-limit response is invalid.");
  }

  const count = payload.result[0];
  const ttl = Math.max(1, payload.result[1]);
  return { allowed: count <= maximum, retryAfterSeconds: ttl };
}

/** Returns null when allowed; otherwise returns a no-store 429/503 response. */
export async function enforceAuthRateLimit(
  request: NextRequest,
  bucket: string,
  maximum: number,
  windowSeconds: number,
): Promise<NextResponse | null> {
  try {
    const result = await checkRateLimit(request, bucket, maximum, windowSeconds);
    if (result.allowed) return null;

    return NextResponse.json(
      { error: "Too many attempts. Please wait before trying again." },
      {
        status: 429,
        headers: {
          "Cache-Control": "no-store",
          "Retry-After": String(result.retryAfterSeconds),
        },
      },
    );
  } catch {
    // Authentication endpoints must not silently run without the durable limiter.
    return NextResponse.json(
      { error: "Authentication is temporarily unavailable. Please try again later." },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }
}
