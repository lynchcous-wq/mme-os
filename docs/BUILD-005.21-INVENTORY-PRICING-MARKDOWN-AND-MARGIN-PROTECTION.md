# Build 005.21 — Inventory Pricing, Markdown, and Margin Protection

**Status:** Pricing governance and inventory integration design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines the inventory-facing pricing contract, cost and margin safeguards, markdown workflows, price history, and channel synchronization. It does not replace the designated pricing authority or implement prices, code, database objects, tests, or deployments.

## 1. Purpose

Ensure MME can price new, used, refurbished, open-box, and clearance electronics consistently while protecting approved margin rules and keeping website, POS, auction, and promotional prices synchronized.

Inventory Core supplies trusted item, condition, quantity, location, and cost-lineage facts. A designated Pricing service remains authoritative for sell prices and pricing rules.

## 2. Ownership boundaries

- **Build 005 Inventory Core:** SKU/unit/lot identity, condition, location, availability, and approved cost lineage.
- **Build 005.16:** inventory valuation and cost intelligence.
- **Pricing authority:** base prices, price books, markdowns, promotions, margin floors, and price approvals.
- **Build 001 Website:** customer-facing price display and offer presentation.
- **Build 002 POS/Orders:** price quote validation and completed transaction records.
- **Auction engine:** auction-specific bidding, reserve, and unlock rules; consumes approved inventory and pricing references.
- **Build 026 Analytics:** price, margin, sell-through, and markdown reporting.

No channel may create its own independent authoritative price. If the pricing authority is implemented in a separate build, integrations must use its published contract rather than duplicate its rules.

## 3. Price and cost vocabulary

Keep the following values distinct:
- acquisition cost;
- allocated landed cost;
- carrying/valuation cost;
- reference market price;
- comparable retail price;
- current base selling price;
- channel-specific displayed price;
- promotional price;
- approved markdown price;
- final transaction price;
- realized net revenue;
- gross profit and gross margin.

Reference market and retail prices are research inputs, not proof of achievable selling price. Estimates must be labeled, sourced, and timestamped.

Gross profit and gross margin are different:
- Gross profit = net sales revenue minus the approved cost basis.
- Gross margin = gross profit divided by net sales revenue, where revenue is positive.

Discounts, taxes, shipping, payment fees, returns, and other adjustments must follow the designated Finance/accounting reporting definitions.

## 4. Pricing inputs

Pricing recommendations may consider:
- SKU and exact condition grade;
- brand, model, specifications, and included accessories;
- approved item-level landed cost;
- current local and network-wide stock;
- days in inventory and aging band;
- sell-through velocity and demand forecast;
- current comparable market/retail research;
- supplier replacement cost and lead-time risk;
- seasonality, promotions, and channel demand;
- warranty, return, and refurbishment exposure;
- location and fulfillment costs where approved.

Every input must include source and freshness. The engine must distinguish actual MME transactions from third-party asking prices, estimates, and forecasts.

## 5. Price books and channel rules

Support centrally governed price books by:
- product/SKU and condition;
- channel (website, POS, auction, or approved marketplace);
- location or region when justified;
- customer segment or membership eligibility where authorized;
- effective date/time and expiration;
- currency and applicable tax presentation rules.

A channel may format or display an approved price but may not silently override it. Any channel-specific price difference must be explicit, versioned, and authorized.

Customer-facing prices must not expose acquisition cost, internal margin, supplier quote, or restricted valuation data.

## 6. Margin protection

Pricing policy may define:
- target margin;
- minimum gross margin;
- minimum gross profit dollars;
- floor price;
- approval thresholds for below-floor offers;
- separate thresholds by category, condition, and channel.

These values require management and Finance approval; this document does not invent or set MME's actual thresholds.

Safeguards:
1. Use the approved cost basis from Build 005.16.
2. Recalculate the margin check at quote/checkout using current authoritative data.
3. Reject or route below-floor prices for authorized approval.
4. Require a reason and actor for overrides.
5. Prevent client-supplied cost or margin values from influencing authorization.
6. Do not treat estimated cost as actual without an explicit status and policy.
7. If cost is missing or unreliable, apply a configured safe fallback or require review rather than claiming margin protection passed.

A price floor is a control, not a guarantee of profitability. Final realized margin can change due to returns, fees, shipping, discounts, and cost corrections.

## 7. Markdown and aging strategy

Support configurable markdown plans based on:
- days since receipt or first available date;
- days since last sale or price change;
- excess quantity and forecast demand;
- product lifecycle and model replacement;
- condition and cosmetic grade;
- current market evidence;
- seasonal/event calendar;
- approved clearance or liquidation campaign.

Possible stages include:
1. Regular price
2. Review recommended
3. Markdown proposal
4. Approval pending
5. Approved and scheduled
6. Active markdown
7. Expired or superseded
8. Clearance / disposition review

Age alone must not automatically force a price reduction. The policy owner sets triggers and limits.

## 8. Markdown approval and override

Each proposal should record:
- SKU/unit/lot scope;
- current and proposed price;
- approved cost basis and calculated margin impact;
- reason and evidence;
- affected channels and locations;
- effective and expiry time;
- requester and approver;
- policy version and resulting price version.

Below-floor markdowns, high-value items, unusual discounts, and broad campaign changes may require elevated or dual approval.

An override must never erase the original price or approval record. Expired promotions must not remain active because a channel failed to refresh.

## 9. Serialized and condition-sensitive pricing

For serialized electronics:
- price the exact unit or approved unit group when condition/accessories materially differ;
- preserve unit identity and inspection grade;
- recalculate after an authorized inspection or refurbishment status change;
- prevent a used/refurbished unit from inheriting a new-condition price by default;
- retain the price decision and evidence history.

For quantity lots, ensure a price applies only to the correct SKU, lot, condition, and effective scope.

## 10. Quote, checkout, and price integrity

At quote and checkout:
- resolve the item and condition from authoritative records;
- retrieve the active approved price;
- validate promotion eligibility and effective dates;
- verify inventory availability separately from price;
- recheck price version and required approval before order commitment;
- preserve the quoted price snapshot on the order;
- handle expired or changed quotes with clear customer and employee messaging.

A price quote is not a reservation unless the order/reservation workflow explicitly creates one. A barcode scan or client-side displayed amount is not proof of the authorized transaction price.

## 11. Channel synchronization

Publish versioned price-change events to approved channels. Each event should include:
- SKU/unit scope;
- price book and channel;
- amount and currency;
- effective/expiry time;
- price version;
- policy/approval reference;
- event ID and correlation reference.

Consumers must be idempotent and detect stale/out-of-order updates. Failed synchronization creates a visible exception and retry task.

Checkout must validate against the pricing authority even if a cached display is stale. Website and POS must not silently sell at an obsolete price.

## 12. Automation and alerts

Integrate with Build 005.12:
- aged inventory price review;
- projected margin below target;
- actual proposed price below floor;
- market reference stale;
- cost basis missing or changed;
- price update not synchronized;
- promotion approaching expiry;
- repeated manual overrides;
- unusual price changes or unauthorized attempts.

Automation may recommend and prepare a price change. It may publish only after the required policy approval. It must not autonomously approve below-floor prices or invent market evidence.

## 13. Reporting

Proposed reports:
- inventory aging by SKU, condition, and location;
- price change and markdown history;
- current price versus approved cost basis;
- projected versus realized gross profit/margin;
- below-floor proposal and override audit;
- sell-through before/after markdown;
- channel price consistency and synchronization lag;
- stale market references;
- clearance inventory and recovery value.

Clearly distinguish actual transaction results from forecasts and modeled markdown outcomes. Restrict cost and margin reports by role.

## 14. Security, audit, and permissions

Proposed permissions, mapped through Build 004:
- view public/current selling price;
- view restricted cost and margin;
- create price/markdown proposal;
- approve standard price changes;
- approve below-floor overrides;
- publish price changes;
- manage price books and policy versions;
- export restricted pricing reports.

Audit price creation, edits, approvals, overrides, publication, failed sync, and checkout validation. Server-side authorization is mandatory. Build 004 application-side session/actor enforcement remains unverified and is a production prerequisite.

## 15. Acceptance criteria

- [ ] Inventory Core and Pricing have distinct, documented authority boundaries.
- [ ] Price, cost, valuation, market reference, and transaction revenue remain separate.
- [ ] Cost basis is traceable to approved Build 005.16 lineage.
- [ ] Price books support product condition, channel, scope, and effective dates.
- [ ] Margin floors and override thresholds are configurable and approved externally.
- [ ] Missing or estimated costs cannot be misrepresented as verified actuals.
- [ ] Markdown proposals retain evidence, approvals, and version history.
- [ ] Serialized units retain condition-specific pricing controls.
- [ ] Checkout validates current authoritative price and approval state.
- [ ] Website, POS, and auction consumers handle stale and duplicate events safely.
- [ ] Expired promotions cannot remain active silently.
- [ ] Restricted cost/margin data is not exposed to customers or unauthorized staff.
- [ ] Tests cover below-floor overrides, stale price versions, concurrent updates, event replay, and channel failure.

## 16. Completion boundary and next gate

This is a design specification only. No prices, margin floors, markdown schedules, promotions, or channel updates have been configured. No code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve pricing authority ownership, margin/floor policy, below-floor approval matrix, markdown cadence, market-data sources, and channel conflict behavior before implementation.
