import { readFileSync } from "node:fs";
import { join } from "node:path";

const routes = [
  { path: "app/api/employee/catalog/route.ts", bodyLimit: "24_000" },
  { path: "app/api/employee/catalog/[productId]/edit/route.ts", bodyLimit: "24_000" },
  { path: "app/api/employee/catalog/[productId]/return/route.ts", bodyLimit: "4_000" },
  { path: "app/api/employee/catalog/[productId]/submit/route.ts" },
  { path: "app/api/employee/catalog/[productId]/approve/route.ts" },
  { path: "app/api/employee/catalog/[productId]/publish/route.ts" },
];
const failures = [];
for (const route of routes) {
  let source;
  try { source = readFileSync(join(process.cwd(), route.path), "utf8"); }
  catch { failures.push(\`Missing catalog API route: \${route.path}\`); continue; }
  if (!source.includes("session.auth.getUser()")) failures.push(\`Missing validated session identity: \${route.path}\`);
  if (!/p_actor_user_id\s*:\s*user\.id/.test(source)) failures.push(\`Missing server-derived actor argument: \${route.path}\`);
  if (/request\.json\s*\(|request\.text\s*\(/.test(source)) failures.push(\`Unbounded body parsing detected: \${route.path}\`);
  if (route.bodyLimit) {
    if (!source.includes('import { readJsonObject } from "@/lib/http/read-json-object"')) failures.push(\`Missing bounded reader import: \${route.path}\`);
    if (!source.includes(\`readJsonObject(request, \${route.bodyLimit})\`)) failures.push(\`Incorrect body limit: \${route.path}\`);
  }
}
if (failures.length) { for (const failure of failures) console.error("FAIL: " + failure); process.exit(1); }
console.log(\`Catalog API security checks passed for \${routes.length} mutation routes.\`);
