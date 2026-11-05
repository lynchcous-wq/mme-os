import {createHash} from "node:crypto";
export type StripeBalanceTransaction={
 id:string;type:string;reporting_category?:string;amount:number;fee:number;currency:string;created:number;
 source?:string|null;description?:string|null;
};
export type NormalizedFinancialRecord={
 source_line_reference:string;fact_type:string;business_date:string;occurred_at:string;business_timezone:string;
 currency:string;amount_minor:number;quantity_milli?:number|null;product_category?:string|null;
 sku_reference?:string|null;register_reference?:string|null;employee_person_id?:string|null;
 source_transaction_reference:string;source_digest_sha256:string;
};
export type StripePage={data:StripeBalanceTransaction[];has_more:boolean};
export async function fetchStripeBalanceTransactions(input:{
 secretKey:string;accountId?:string;createdGte:number;startingAfter?:string|null;
}):Promise<StripePage>{
 const url=new URL("https://api.stripe.com/v1/balance_transactions");
 url.searchParams.set("limit","100");url.searchParams.set("created[gte]",String(input.createdGte));
 if(input.startingAfter)url.searchParams.set("starting_after",input.startingAfter);
 const requestHeaders:Record<string,string>={Authorization:"Bearer "+input.secretKey,Accept:"application/json"};
 if(input.accountId)requestHeaders["Stripe-Account"]=input.accountId;
 const response=await fetch(url,{headers:requestHeaders,cache:"no-store"});
 if(!response.ok)throw new Error("STRIPE_BALANCE_TRANSACTION_FETCH_FAILED");
 const body=await response.json() as StripePage;
 if(!Array.isArray(body.data)||typeof body.has_more!=="boolean")throw new Error("STRIPE_BALANCE_TRANSACTION_RESPONSE_INVALID");
 return body;
}
function localBusinessDate(date:Date,timezone:string){
 const parts=new Intl.DateTimeFormat("en-US",{timeZone:timezone,year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(date);
 const part=(type:string)=>parts.find(p=>p.type===type)?.value||"";
 return part("year")+"-"+part("month")+"-"+part("day");
}
export function normalizeStripeBalanceTransactions(input:{
 data:StripeBalanceTransaction[];timezone:string;
}):{records:NormalizedFinancialRecord[];ignored:number}{
 const records:NormalizedFinancialRecord[]=[];let ignored=0;
 for(const tx of input.data){
  if(!tx.id||!Number.isSafeInteger(tx.amount)||!Number.isSafeInteger(tx.fee)||!Number.isSafeInteger(tx.created)||
   !/^[a-z]{3}$/.test(tx.currency)){ignored++;continue;}
  const category=tx.reporting_category||tx.type;
  let factType:string|null=null;
  if(category==="charge"||category==="payment")factType="gross_sale";
  else if(category==="refund")factType="refund";
  else if(category==="dispute"||category==="dispute_reversal")factType="chargeback";
  if(!factType){ignored++;continue;}
  const occurred=new Date(tx.created*1000);
  const common={business_date:localBusinessDate(occurred,input.timezone),occurred_at:occurred.toISOString(),
   business_timezone:input.timezone,currency:tx.currency.toUpperCase(),quantity_milli:null,product_category:null,
   sku_reference:null,register_reference:null,employee_person_id:null,source_transaction_reference:tx.source||tx.id,
   source_digest_sha256:createHash("sha256").update(JSON.stringify(tx)).digest("hex")};
  records.push({...common,source_line_reference:tx.id+":"+factType,fact_type:factType,amount_minor:tx.amount});
  if(tx.fee!==0)records.push({...common,source_line_reference:tx.id+":processor_fee",fact_type:"processor_fee",amount_minor:-Math.abs(tx.fee)});
 }
 return {records,ignored};
}
