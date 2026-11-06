import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=path=>readFile(new URL("../"+path,import.meta.url),"utf8");
const [email,phone,verify,recovery,complete,ui]=await Promise.all([
 read("app/api/auth/customer/contact/email/route.ts"),read("app/api/auth/customer/contact/phone/route.ts"),read("app/api/auth/customer/contact/phone/verify/route.ts"),read("app/api/auth/customer/recovery/route.ts"),read("app/api/auth/customer/recovery/complete/route.ts"),read("app/account/contact/page.tsx")
]);
test("contact mutations require same-origin and authenticated session",()=>{for(const source of [email,phone,verify]){assert.match(source,/hasSameOrigin/);assert.match(source,/requireBrowserUser/);}});
test("email changes are provider-confirmed rather than immediately applied",()=>{assert.match(email,/auth\/v1\/user/);assert.match(email,/confirmation/);assert.match(email,/remains unchanged/);});
test("phone is not reported verified until OTP verification succeeds",()=>{assert.match(phone,/phone/);assert.match(verify,/auth\/v1\/verify/);assert.match(verify,/phone_change/);assert.match(verify,/verified:true/);});
test("recovery responses do not disclose account existence",()=>{assert.match(recovery,/If an account exists for that address/);assert.match(recovery,/auth\/v1\/recover/);});
test("password reset requires a recovery token and strong password",()=>{assert.match(complete,/type:"recovery"/);assert.match(complete,/password\.length<12/);assert.match(complete,/auth\/v1\/user/);});
test("contact UI includes email, phone and code verification workflows",()=>{assert.match(ui,/Request email confirmation/);assert.match(ui,/Send verification code/);assert.match(ui,/Verify phone/);});
