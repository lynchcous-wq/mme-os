import test from 'node:test'; import assert from 'node:assert/strict'; import {readFile} from 'node:fs/promises';
const page=await readFile(new URL('../app/account/warranty/page.tsx',import.meta.url),'utf8');
const css=await readFile(new URL('../app/globals.css',import.meta.url),'utf8');
test('customer warranty portal route and account navigation exist',()=>{assert.match(page,/Warranty care/);assert.match(page,/href="\/account"/);});
test('portal explains claim steps without inventing customer claim records',()=>{for(const x of ['Submit your claim','Verify coverage','Review evidence','Track the resolution'])assert.ok(page.includes(x));assert.match(page,/no personal claim records are shown/);});
test('sensitive serial, IMEI and receipt data are not collected by the presentation-only release',()=>{assert.match(page,/does not request or store those details/);assert.doesNotMatch(page,/name="(?:imei|serial_number|receipt_upload)"/);});
test('page uses responsive customer warranty styles',()=>{assert.match(css,/\.customer-warranty/);assert.match(css,/@media\(max-width:760px\)/);});
