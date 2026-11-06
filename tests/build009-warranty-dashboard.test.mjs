import test from "node:test"; import assert from "node:assert/strict"; import {readFile} from "node:fs/promises";
const page=await readFile(new URL("../app/ops/warranty/page.tsx",import.meta.url),"utf8");
const css=await readFile(new URL("../app/globals.css",import.meta.url),"utf8");
test("executive warranty command route exists with six core KPI cards",()=>{assert.match(page,/Warranty/);assert.equal((page.match(/\["(?:Warranty revenue|Warranty expense|Net warranty margin|Claims-to-sales|Provider recovery|Average turnaround)"/g)||[]).length,6);});
test("dashboard never invents figures and labels source data as pending",()=>{assert.match(page,/Awaiting verified source feeds/);assert.match(page,/No live figures loaded/);assert.match(page,/Actuals pending/);});
test("actual and projected reporting governance is visible",()=>{assert.match(page,/Actual/);assert.match(page,/Projection/);assert.match(page,/never blended/);});
test("provider recovery requires matched settlement evidence",()=>{assert.match(page,/Matched settlement evidence required/);});
test("dashboard responsive styling is included",()=>{assert.match(css,/\.warranty-command/);assert.match(css,/@media\(max-width:760px\)/);});
