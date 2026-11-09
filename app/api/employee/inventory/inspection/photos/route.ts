import { NextResponse } from "next/server";
import { authenticateAndAuthorizeEmployee } from "@/lib/server/identity-authorization";
import { createHash, randomUUID } from "node:crypto";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const BUCKET = "mme-inspection-evidence";
const MAX_BYTES = 10 * 1024 * 1024;
const MIME_EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
};

async function jsonRequest<T>(
  url: string,
  key: string,
  method: string,
  body?: unknown,
): Promise<{ ok: boolean; status: number; data: T | null }> {
  const response = await fetch(url, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    cache: "no-store",
  });
  const data = response.ok ? await response.json().catch(() => null) as T | null : null;
  return { ok: response.ok, status: response.status, data };
}

export async function POST(request: Request) {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > MAX_BYTES + 128_000) {
    return NextResponse.json({ error: "Photo upload exceeds the 10 MB limit." }, { status: 413 });
  }

  const bearer = request.headers.get("authorization")?.match(/^Bearer ([^\s]+)$/)?.[1];
  if (!bearer) return NextResponse.json({ error: "Employee sign-in is required." }, { status: 401 });

  const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!baseUrl || !anonKey || !serviceKey) {
    return NextResponse.json({ error: "Private photo storage is not configured." }, { status: 503 });
  }

  try {
    const authResponse = await fetch(`${baseUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${bearer}` },
      cache: "no-store",
    });
    if (!authResponse.ok) return NextResponse.json({ error: "Employee session is invalid or expired." }, { status: 401 });
    const authUser = await authResponse.json() as { id?: string };
    if (!authUser.id) return NextResponse.json({ error: "Employee session is invalid." }, { status: 401 });

    const form = await request.formData();
    const file = form.get("file");
    const inspectionId = form.get("inspection_id");
    const caption = form.get("caption");
    if (!(file instanceof File) || typeof inspectionId !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(inspectionId) ||
        typeof caption !== "string" || caption.length > 500) {
      return NextResponse.json({ error: "A valid inspection, photo and caption are required." }, { status: 400 });
    }
    const extension = MIME_EXTENSIONS[file.type];
    if (!extension || file.size < 1 || file.size > MAX_BYTES) {
      return NextResponse.json({ error: "Use a JPEG, PNG, WebP or HEIC photo up to 10 MB." }, { status: 400 });
    }

    const inspectionQuery = new URLSearchParams({
      select: "id,product_id,location_id,inspected_by_identity_id,disposition",
      id: `eq.${inspectionId}`,
      limit: "1",
    });
    const inspection = await jsonRequest<Array<{
      id: string; product_id: string; location_id: string; inspected_by_identity_id: string; disposition: string;
    }>>(`${baseUrl}/rest/v1/mme_inventory_inspections?${inspectionQuery}`, serviceKey, "GET");
    const record = inspection.data?.[0];
    if (!inspection.ok || !record) {
      return NextResponse.json({ error: "Inspection record was not found." }, { status: 404 });
    }

    // Resolve the separate Build 004 person identity from the validated Auth subject.
    const identityQuery = new URLSearchParams({
      select: "id",
      auth_user_id: `eq.${authUser.id}`,
      limit: "2",
    });
    const identityResponse = await jsonRequest<Array<{ id: string }>>(
      `${baseUrl}/rest/v1/mme_person_identities?${identityQuery}`,
      serviceKey,
      "GET",
    );
    if (!identityResponse.ok) {
      return NextResponse.json({ error: "Employee identity could not be verified." }, { status: 503 });
    }
    if (identityResponse.data?.length !== 1) {
      return NextResponse.json({ error: "Employee identity could not be verified." }, { status: 403 });
    }
    const actorIdentityId = identityResponse.data[0].id;

    // Only the submitting employee may attach photos while the inspection is pending.
    if (record.inspected_by_identity_id !== actorIdentityId || record.disposition !== "pending") {
      return NextResponse.json({ error: "Only the submitting employee may attach photos while the inspection is pending." }, { status: 403 });
    }

    const build004 = await authenticateAndAuthorizeEmployee(
      bearer,
      "inventory.inspection",
      "submit",
      { product_id: record.product_id, location_id: record.location_id },
    );
    if (!build004.ok || build004.actorUserId !== authUser.id) {
      return NextResponse.json(
        { error: build004.ok ? "Employee session changed during authorization." : build004.error },
        { status: build004.ok ? 401 : build004.status },
      );
    }

    const authorization = await jsonRequest<boolean>(
      `${baseUrl}/rest/v1/rpc/mme_employee_authorize_inventory_action`,
      serviceKey,
      "POST",
      {
        p_actor_user_id: authUser.id,
        p_permission_key: "inventory.inspection.submit",
        p_target_product_id: record.product_id,
        p_target_location_id: record.location_id,
      },
    );
    if (!authorization.ok) {
      return NextResponse.json({ error: "Inspection evidence authorization is temporarily unavailable." }, { status: 503 });
    }
    if (authorization.data !== true) {
      return NextResponse.json({ error: "Employee is not authorized to attach inspection evidence." }, { status: 403 });
    }

    const bytes = Buffer.from(await file.arrayBuffer());
    const signatureValid =
      (file.type === "image/jpeg" && bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) ||
      (file.type === "image/png" && bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) ||
      (file.type === "image/webp" && bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP") ||
      (file.type === "image/heic" && bytes.length >= 12 && bytes.toString("ascii", 4, 8) === "ftyp");
    if (!signatureValid) return NextResponse.json({ error: "Photo content does not match its declared image type." }, { status: 415 });

    const objectKey = `${inspectionId}/${randomUUID()}.${extension}`;
    const storageResponse = await fetch(
      `${baseUrl}/storage/v1/object/${BUCKET}/${objectKey}`,
      {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": file.type,
          "x-upsert": "false",
          "Cache-Control": "private, max-age=0",
        },
        body: bytes,
        cache: "no-store",
      },
    );
    if (!storageResponse.ok) {
      return NextResponse.json({ error: "Private photo storage rejected the upload." }, { status: 502 });
    }

    const sha256 = createHash("sha256").update(bytes).digest("hex");
    const metadata = await jsonRequest<string>(
      `${baseUrl}/rest/v1/rpc/mme_register_inspection_photo_evidence`,
      serviceKey,
      "POST",
      {
        p_inspection_id: inspectionId,
        p_storage_object_key: objectKey,
        p_mime_type: file.type,
        p_file_size_bytes: file.size,
        p_sha256_hex: sha256,
        p_caption: caption.trim(),
        p_actor_identity_id: actorIdentityId,
      },
    );

    if (!metadata.ok || !metadata.data) {
      await fetch(`${baseUrl}/storage/v1/object/${BUCKET}/${objectKey}`, {
        method: "DELETE",
        headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
        cache: "no-store",
      }).catch(() => undefined);
      return NextResponse.json({ error: "Photo metadata could not be registered; the upload was rolled back where possible." }, { status: 409 });
    }

    return NextResponse.json(
      { evidence_id: metadata.data, uploaded: true },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch {
    return NextResponse.json({ error: "Private photo upload is temporarily unavailable." }, { status: 502 });
  }
}
