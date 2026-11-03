import { readFileSync } from "node:fs";
import { join } from "node:path";
const routes = [
  { path: "app/api/employee/catalog/route.ts", bodyLimit: "24_000" },
  { path: "app/api/employee/catalog/[productId]/edit/route.ts", bodyLimit: "24_000" },
  { path: "app/api/employee/catalog/[productId]/return/route.ts", bodyLimit: "4_000" },
  { path: "app/api/employee/catalog/[productId]/submit/route.ts" },
  { path: "app/api/employee/catalog/[productId]/approve/route.ts" },
  { path: "app/api/employee/catalog/[productId]/publish/route.ts" },
  { path: "app/api/employee/catalog/review/route.ts", reviewQueue: true },
];
const failures = [];
for (const route of routes) {
  let source;
  try { source = readFileSync(join(process.cwd(), route.path), "utf8"); }
  catch { failures.push("Missing route: " + route.path); continue; }
  if (!source.includes("session.auth.getUser()")) failures.push("Missing validated session identity: " + route.path);
  if (!source.includes("p_actor_user_id:user.id") && !source.includes("p_actor_user_id: user.id")) failures.push("Missing server-derived actor argument: " + route.path);
  if (/request\.json\s*\(|request\.text\s*\(/.test(source)) failures.push("Unbounded body parsing detected: " + route.path);
  if (route.reviewQueue) {
    if (!source.includes('"catalog.review"')) failures.push("Missing catalog.review permission check: " + route.path);
    if (!source.includes('admin.rpc("mme_employee_authorize_catalog_action"')) failures.push("Missing server authorization RPC: " + route.path);
    const authorizationIndex = source.indexOf('admin.rpc("mme_employee_authorize_catalog_action"');
    const productQueryIndex = source.indexOf('.from("products")');
    if (authorizationIndex < 0 || productQueryIndex < 0 || authorizationIndex > productQueryIndex) {
      failures.push("Review queue must authorize before querying product data: " + route.path);
    }
  }
  if (route.bodyLimit) {
    if (!source.includes('import { readJsonObject } from "@/lib/http/read-json-object"')) failures.push("Missing bounded reader import: " + route.path);
    if (!source.includes("readJsonObject(request, " + route.bodyLimit + ")")) failures.push("Incorrect body limit: " + route.path);
  }
}
if (failures.length) { for (const failure of failures) console.error("FAIL: " + failure); process.exit(1); }
console.log("Catalog API security checks passed for " + routes.length + " catalog API routes.");
