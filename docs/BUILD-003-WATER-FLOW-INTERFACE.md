# Build 003 — Water-Flow Interface, Light & Dark Modes

**Platform:** Much More Electronics Operating System  
**Status:** Specification for implementation review; no production implementation claim  
**Dependencies:** Builds 001 and 002  
**Repository:** `lynchcous-wq/mme-os`  
**Authority:** CEO retains enterprise design-governance authority; user display preferences remain separate from company standards and security policy.

## 1. Purpose and scope

Build 003 specifies a unified visual system for MME OS: water-flow-inspired styling, light/dark/system themes, full-screen workspace presentation, safe sleep/wake behavior, consistent role-aware navigation, and responsive associate, management, and executive experiences.

The visual system is a presentation layer. Theme, animation, full-screen, and sleep preferences must never alter business data, authorization, security policy, or workflow state. A visual effect must not be required to complete an action or understand its outcome.

## 2. Current-state audit and implementation boundary

The existing repository was inspected before preparing this specification:

- `app/layout.tsx` provides the shared document wrapper and metadata.
- `app/globals.css` contains global storefront styling and responsive rules.
- `app/page.tsx` contains the storefront homepage.
- `app/products/page.tsx` and `app/account/page.tsx` are placeholder routes.
- `package.json` includes Next.js, React, and TypeScript; no theme, animation, identity, persistence, or component-library package is currently declared.
- The current routes do not implement authenticated workspaces, role-aware module navigation, centralized design settings, persistent preferences, full-screen mode, or secure sleep/wake behavior.

This Build 003 document is a design/requirements artifact only. The existing storefront is not to be replaced. Future implementation should first establish shared design tokens additively, then migrate existing components in small reviewable steps. Role-specific and executive navigation depend on the IAM/Identity Matrix from Builds 001/002 and must not be simulated as secure using client-only visibility controls.

## 3. Experience principles and water-flow design language

- **Premium, calm, legible:** use considered spacing, typography, blue/teal water-flow accents, subdued translucent surfaces where contrast remains sufficient, and clear content hierarchy.
- **Motion is optional decoration:** restrained ripple/flow transitions may reinforce navigation and state changes but cannot delay or obscure content, controls, errors, focus, or transaction confirmation.
- **No false state:** a glow, ripple, or animation must not suggest a business operation succeeded. Business success is communicated through explicit accessible text and server-confirmed state.
- **Consistent foundations:** spacing, typography, radii, elevation, focus, icons, and semantic colors use shared tokens, not module-specific conflicting overrides.
- **Responsive and resilient:** reduced-motion, low-power, narrow viewport, slow network, and unsupported Fullscreen API must have usable static alternatives.

### Motion rules

- Honor `prefers-reduced-motion: reduce` and provide an in-app motion setting if approved. Reduced motion disables non-essential transitions, ripple effects, background animation, and sleep animation.
- Keep transition duration short and consistent for normal UI feedback; sleep ambience, if enabled, moves slowly and consumes minimal resources. Avoid autoplay sound, flashing, parallax, rapid scaling, and continuous work while hidden.
- Do not use motion to convey unique information. Every animated state has a static equivalent.
- Stop or pause decorative animation when the document is hidden, the user requests reduced motion, or the device/browser indicates reduced activity is appropriate.
- Use CSS transforms/opacity where appropriate, avoid layout-thrashing animation and heavy canvas/WebGL effects, and measure performance on target devices.

## 4. Theme and design tokens

### Theme modes

The user-selectable preference is one of `system`, `light`, or `dark`. `system` follows the operating-system preference. The app resolves this to an effective theme at render time and updates when system preference changes. Avoid a flash of the wrong theme during page initialization; any implementation must not introduce unsafe inline script or hydration inconsistencies.

Light theme baseline: white and soft-neutral surfaces, dark readable text, restrained blue/teal accents, subtle borders/shadows, and high-contrast controls.

Dark theme baseline: deep charcoal/navy surfaces, readable light text, differentiated panels/navigation, controlled blue illumination, and no excessively bright large-area surfaces.

### Token requirements

Use semantic tokens for at least:

- Page, surface, elevated surface, overlay, and inverse surface.
- Primary, secondary, muted, and disabled text.
- Border and divider.
- Primary/secondary accent and water-flow gradient.
- Success, warning, error, and informational status (each not distinguished by color alone).
- Focus ring, hover, pressed, selected, and active navigation.
- Shadow/elevation and animation timing/intensity.

Token names should express purpose (for example `--surface`, `--text-primary`, `--border-subtle`, `--accent-primary`, `--focus-ring`), not hard-coded color values. Preserve current storefront visual identity while moving styles incrementally to tokens. Avoid blanket color inversion or filters.

### Preference and company-default precedence

1. Security and accessibility requirements always take precedence.
2. An authorized administrator may set the company default theme and approved accent palette through controlled design settings.
3. A user may select `system`, `light`, or `dark` within permitted company standards.
4. The user can preview a selection, save it, or reset to the company default.
5. Individual preferences cannot overwrite company defaults or alter role permissions.

Preference storage must be scoped to the authenticated user when identity is available. For an unauthenticated storefront, any local preference mechanism must be limited to display settings and must not be treated as identity, permission, or security state. Persistence technology and server synchronization are decisions for implementation after IAM is available.

## 5. Full-screen workspace mode

Full-screen mode is an optional presentation/workspace mode implemented using the browser's supported Fullscreen API when possible, with a graceful expanded-layout fallback. It must:

- Provide an obvious, keyboard-accessible enter and exit control and respond to `Escape`/browser exit.
- Preserve the current route, active workspace, form state, and unsaved work; never reload or discard data merely to change layout.
- Keep authorized controls, essential status, emergency exit, and required navigation reachable. A presentation layout may minimize chrome but cannot suppress mandatory warnings or security controls.
- Respect browser restrictions, user gestures, device differences, and permission policy. Explain if native full-screen is unavailable and use the fallback without claiming browser full-screen.
- Recalculate layout on viewport/orientation changes and remain usable on supported desktop/tablet/mobile sizes.
- Never grant access, extend session lifetime, bypass reauthentication, or change authorization.

If a sensitive workspace is opened, permission checks continue as normal. If access is revoked or the session expires while full-screen, hide/lock the protected content and direct the user through the approved reauthentication flow.

## 6. Sleep and wake behavior

Sleep display is an optional, low-distraction visual cover after an approved inactivity threshold; it is not a session lock, authentication mechanism, or security boundary.

### Sleep entry

- Show only a generic, non-sensitive display and optional centrally approved MME logo; no customer names, order/product records, financial data, notifications, or active tasks.
- Do not stop or alter business transactions. Any in-progress work remains in its normal state; unsaved form data should be preserved according to the module's data policy.
- Do not expose protected content through accessibility trees, browser page titles, notifications, thumbnails, or background canvases while sleep is active; use a proper cover/visibility strategy and test it.
- Reduce processing: pause decorative movement when backgrounded, prefer CSS-only low-cost effects, and make animation intensity configurable within approved bounds.
- Session expiry and screen-lock policies remain independently enforced.

### Wake and restore

1. User interaction initiates a gentle transition or static reveal.
2. System checks session validity and current authorization before revealing the protected workspace.
3. If the session is valid, restore the previous authorized route/workspace and current work state.
4. If reauthentication is required, show the authentication/lock experience; reveal no protected content before successful authentication.
5. If access was revoked, display a safe access-denied/next-step state instead of restoring the module.

Use a documented timeout source and avoid collecting unnecessary behavioral data. User presence or wake gestures must not be treated as authentication proof. Sleep/wake should be disabled or reduced when motion preferences require it.

## 7. Navigation and role experiences

### Shared navigation framework

Provide consistent, accessible components for main navigation, module navigation, breadcrumbs, search/quick access, notifications, user profile/preferences, and CEO command navigation. Navigation items are generated from authorized module/action metadata where available. Server-side/API permission checks remain authoritative; hiding a link is not access control.

- Clearly indicate current location and focus; support keyboard navigation and meaningful accessible names.
- Breadcrumbs reflect hierarchy without exposing unauthorized resource names.
- Search and quick access return only permitted records/modules and audit sensitive searches as required by policy.
- Notifications respect authorization and consent, avoid sensitive content on locked/sleep displays, and link only to currently authorized destinations.
- CEO links and controls are visually distinct where useful but require authenticated CEO grants and server-side authorization.

### Associate experience

Prioritize daily tasks, customer/sales workflows, training and employee resources, and role-appropriate notifications. Keep navigation simple and avoid exposing other department or executive data.

### Management experience

Offer department-level dashboards, comparisons, operational queues, and team controls limited by assigned department/location and access grants.

### CEO experience

Support enterprise command dashboards, intelligence, cross-department reporting, and authorized configuration/module sequence controls. Report views must respect field/record permissions and data lineage; executive presentation mode does not imply unrestricted access to restricted records.

All experiences use the same token/component system. Role-specific views are configured by permission and approved information architecture rather than disconnected designs.

## 8. Central design administration and brand assets

An eventual centralized design settings module may allow authorized administrators to manage company defaults, approved accent colors, motion intensity bounds, sleep presentation, logo placement, and approved role-specific configurations. Changes require server authorization, validation against contrast/accessibility constraints, version history, and audit records. Ordinary employees can adjust personal display preferences only within policy.

Logo management is a centrally governed brand capability from the earlier MME specifications. The logo must be an approved asset reference reusable by website, marketing, and document workflows. It is not implemented by this document. The written business name “Much More Electronics” remains an optional format for important documents and barcode printing; do not inject it automatically into ordinary body copy.

## 9. Accessibility and performance requirements

- Meet WCAG 2.2 AA as the target for supported experiences, subject to formal accessibility review; text and controls must meet applicable contrast requirements in both themes.
- All interactive controls are keyboard-operable, with visible focus that is not obscured. Use semantic landmarks, heading order, labels, status announcements and accessible names.
- Theme, sleep, and full-screen controls expose their state and action to assistive technology.
- Do not rely on color, animation, hover, or sound alone to communicate information.
- Respect operating-system and in-app reduced-motion preferences. Provide static content with animation disabled.
- Ensure content zoom/reflow, touch target size, error identification, and responsive layouts on supported screen widths.
- Lazy-load nonessential imagery and avoid expensive always-running effects. Test Largest Contentful Paint, interaction responsiveness, layout shift, memory, CPU/battery impact, and reduced-motion behavior using agreed targets in Build 003 implementation review.
- Provide fallback rendering if a theme preference cannot load, Fullscreen API is unavailable, or an animation resource fails.

## 10. Security and privacy requirements

- Authenticate before restoring protected workspace content; sleep is not a substitute for lock, session timeout, or reauthentication.
- Do not show sensitive data in sleep state, lock overlay, page previews, unauthorized notification banners, or cached navigation suggestions.
- Theme preferences are presentation preferences only. They cannot modify roles, permissions, session policy, or authorization.
- Protect administrator design settings and logo uploads with server-side permissions, input/file validation, safe storage, and audit events.
- Audit privileged changes to company defaults, approved palettes, motion bounds, sleep presentation, and brand assets.
- Avoid logging user interaction detail beyond what is necessary for product operation, security, and approved analytics; follow consent and retention policies.
- Re-check authorization on wake and on route/API access. Session expiration/revocation is independently enforced.

## 11. Implementation plan and change safety

1. **Baseline review:** document current routes, global styles, responsive behavior, accessibility gaps, and existing working flows. Preserve the existing MME storefront.
2. **Design tokens:** introduce semantic light/dark tokens in shared CSS with conservative defaults matching the existing palette; replace hard-coded values incrementally.
3. **Theme control:** implement `system`/`light`/`dark`, accessible toggle and preview, hydration-safe theme initialization, and documented preference persistence. Do not imply account synchronization before IAM/storage exists.
4. **Shared shell:** add reusable navigation, breadcrumbs, profile/preferences, and notification affordances only where functionality and permissions are backed; placeholder items must be marked/unavailable rather than presented as working integrations.
5. **Motion:** implement a small set of optional transitions/ripple accents; honor reduced motion and visibility state; add performance checks.
6. **Full-screen:** add enter/exit behavior with native API and fallback; preserve route/forms and security checks.
7. **Sleep/wake:** add only after session lifecycle and reauthentication policy are integrated; until then, do not portray a visual overlay as secure screen lock.
8. **Administration:** implement company design settings and centrally managed logo only with IAM, validation, audit, and version history.
9. **Verification:** test existing storefront plus every supported module, theme, viewport, role, reduced-motion state, full-screen capability, session expiry, and sleep/wake boundary.

All code changes should be additive and version-controlled. Record dependencies, decision records, visual change log, known limitations, and rollback instructions. Do not rebuild existing pages from scratch or claim themes/secure wake work across modules that do not yet exist.

## 12. Acceptance criteria

Build 003 is ready for implementation review when evidence demonstrates:

- [ ] Light, dark, and system themes render consistently across all implemented and supported routes/modules.
- [ ] Theme preference selection, preview, persistence scope, and reset-to-company-default work without affecting permissions or business data.
- [ ] Shared semantic tokens and approved accent colors pass contrast/accessibility checks in both themes.
- [ ] Water-flow motion is restrained, optional, performant, and disabled/reduced for reduced-motion preferences and background state.
- [ ] Full-screen enters/exits safely, handles browser/API fallback, keeps essential authorized controls, and preserves route/form state.
- [ ] Sleep hides sensitive content from visual and assistive-technology exposure; wake checks session and authorization before revealing the workspace.
- [ ] Sleep is clearly not a replacement for session expiration, screen lock, or reauthentication.
- [ ] Main/module navigation, breadcrumbs, search, notification and profile controls expose only authorized destinations and retain server-side enforcement.
- [ ] Associate, manager and CEO experiences use a consistent design system while respecting record/module boundaries.
- [ ] Existing storefront layouts and functionality remain intact; changes are additive and regression-tested.
- [ ] Keyboard, screen-reader, zoom/reflow, contrast, reduced-motion, responsive, performance and session-expiry tests are recorded.
- [ ] Central design settings/logo changes are authorized, validated, versioned and audited before being represented as available.
- [ ] Each completion statement is tied to a commit, test result, environment and reviewer; unsupported features are reported as incomplete.

## 13. Implementation dependencies and open decisions

Build 003 implementation depends on the identity/session, authorization, audit, configuration, and module registry foundations in Builds 001/002. Sleep/wake requires a defined session-expiry and reauthentication design. Role-aware navigation requires authoritative module permission metadata. Preference synchronization requires an identity and persistence decision. Company design settings and centrally managed logo depend on secure settings, storage, and audit services.

Review before implementation:

1. Supported browsers, devices, screen sizes, and any native/installed application requirements.
2. Company default theme, initial palette, contrast thresholds, and whether accent customization is limited to a curated set.
3. User preference storage/synchronization and behavior for unauthenticated public storefront visitors.
4. Approved inactivity/sleep threshold and relationship to the separately governed screen-lock/session-expiration policy.
5. Full-screen fallback behavior and presentation-mode restrictions by module/role.
6. Exact motion/performance budgets and accessibility verification process.
7. Logo asset formats, dimensions, approved uploaders, versioning, and use/retention policy.
8. Navigation taxonomy and authoritative module/action permission metadata.

## 14. Current completion boundary

This file records the Build 003 visual-system specification and acceptance requirements. The inspected repository contains a storefront shell with global CSS but no theme provider/toggle, persisted preference, authenticated role navigation, native full-screen control, sleep/wake implementation, centralized design settings, or cross-module experience. Those capabilities have not been implemented or tested. Do not declare Build 003 complete until implementation evidence covers the acceptance criteria across the actual supported modules and environments.
