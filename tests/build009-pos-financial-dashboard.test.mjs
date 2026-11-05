import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const api = await readFile(new URL("../app/api/pos/financial-reports/route.ts", import.meta.url), "utf8");
const page = await readFile(new URL("../app/internal/financial-reports/page.tsx", import.meta.url), "utf8");
const css = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");

test("financial report GET and POST require a verified employee session", () => {
 assert.equal((api.match(/authenticatePosRequest\(request\)/g) || []).length, 2);
 assert.match(api,/Authorization: `Bearer \${context\.serviceKey}`/);
});
test("report reads and report builds require distinct store-scoped permissions", () => {
 assert.match(api, /"pos\.finance\.report\.view"/);
 assert.match(api, /"pos\.finance\.report\.build"/);
 assert.match(api, /p_location_id: input\.location_id/);
});
test("report API validates store UUID, calendar dates, period order and ISO currency", () => {
 assert.match(api,/isUuid\(value\)/);
 assert.match(api,/const validDate/);
 assert.match(api,/periodEnd < periodStart/);
 assert.match(api,/currencyPattern/);
});
test("report API disables caching and returns no-store responses", () => {
 assert.match(api,/export const dynamic = "force-dynamic"/);
 assert.match(api,/export const revalidate = 0/);
 assert.match(api,/Cache-Control.*no-store, private/);
});
test("employee-level financial rows are withheld until a separate permission is available", () => {
 assert.match(api,/row\.grouping_level !== "employee"/);
 assert.match(page,/Employee-level reporting remains hidden|Employee-level financial comparisons remain hidden/);
});
test("dashboard presents net sales, gross profit, contribution profit, COGS and settlement controls", () => {
 for (const phrase of ["Net sales","Gross profit","Contribution profit","Cost of goods sold","Processor net settlement","Matched bank deposits","Cash variance"]) {
  assert.ok(page.includes(phrase), "missing dashboard metric: "+phrase);
 }
});
test("dashboard renders daily sales trend and CSV export", () => {
 assert.match(page,/finance-chart/);
 assert.match(page,/downloadCsv/);
 assert.match(page,/text\/csv/);
 assert.match(page,/Export CSV/);
});
test("dashboard keeps the bearer token in component memory and does not persist it", () => {
 assert.match(page,/useState\(" "\)/);
 assert.match(page,/type="password"/);
 assert.doesNotMatch(page,/localStorage|sessionStorage|document\.cookie/);
});
test("dashboard provides responsive layout and accessible error status", () => {
 assert.match(page,/role="alert"/);
 assert.match(page,/role="status"/);
 assert.match(css,/@media\(max-width:650px\)/);
});
test("dashboard does not present illustrative product catalog data as live financials", () => {
 assert.match(page,/Reports only appear when Build 009\.32 is migrated/);
 assert.match(page,/Management reporting only/);
});
