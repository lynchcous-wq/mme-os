const samplePeople = [
  { initials: "JL", name: "Jordan Lee", email: "jordan.lee@example.test", customer: "Active", employee: "Active", role: "General Manager", access: "12 grants" },
  { initials: "AM", name: "Alex Morgan", email: "alex.morgan@example.test", customer: "Active", employee: "Active", role: "Sales Associate", access: "5 grants" },
  { initials: "TS", name: "Taylor Smith", email: "taylor.smith@example.test", customer: "Frozen", employee: "Active", role: "Inventory Specialist", access: "4 grants" },
  { initials: "RK", name: "Riley Kim", email: "riley.kim@example.test", customer: "Active", employee: "Terminated", role: "Former Associate", access: "0 grants" },
];

const roles = [
  ["CEO", "Executive", "Identity governance · privileged approvals", "Restricted"],
  ["General Manager", "Management", "Store operations · team oversight", "Scoped"],
  ["Sales Associate", "Sales", "POS · CRM · assigned customer records", "Scoped"],
  ["Inventory Specialist", "Warehouse", "Receiving · stock · fulfillment", "Scoped"],
];

export default function IdentityMatrixPage() {
  return <main className="identity-page">
    <header className="identity-topbar">
      <a className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br/><b>ELECTRONICS</b></span></a>
      <div className="identity-top-actions"><span className="preview-pill">PREVIEW · DEMO DATA</span><a href="/">Storefront ↗</a></div>
    </header>
    <section className="identity-hero">
      <div><div className="eyebrow">BUILD 004 · IDENTITY & ACCESS</div><h1>Identity <em>Matrix.</em></h1><p>One trusted identity. Separate customer and employee relationships. Access granted only by explicit, scoped permission.</p></div>
      <div className="identity-hero-mark"><span>MME</span><b>IDENTITY<br/>GOVERNANCE</b></div>
    </section>
    <section className="identity-content">
      <div className="identity-heading-row"><div><div className="eyebrow">CONTROL CENTER</div><h2>People & relationships</h2></div><span className="demo-note">Illustrative records · no live accounts connected</span></div>
      <div className="identity-stats">
        <article><small>PERSON IDENTITIES</small><strong>248</strong><span>Unique login identities</span></article>
        <article><small>CUSTOMER RELATIONSHIPS</small><strong>231</strong><span>Independent customer status</span></article>
        <article><small>EMPLOYEE RELATIONSHIPS</small><strong>17</strong><span>Managed by HR lifecycle</span></article>
        <article><small>PRIVILEGED ACCESS</small><strong>3</strong><span>Requires elevated review</span></article>
      </div>
      <div className="identity-panel">
        <div className="identity-panel-head"><div><h3>Identity directory</h3><p>Customer and employee states are managed independently.</p></div><span className="directory-count">4 SAMPLE RECORDS</span></div>
        <div className="identity-table-wrap"><table className="identity-table"><thead><tr><th>PERSON / LOGIN</th><th>CUSTOMER</th><th>EMPLOYEE</th><th>ASSIGNED ROLE</th><th>ACCESS</th></tr></thead><tbody>{samplePeople.map(person => <tr key={person.email}><td><div className="person-cell"><span className="person-avatar">{person.initials}</span><span><b>{person.name}</b><small>{person.email}</small></span></div></td><td><span className={`state-tag ${person.customer.toLowerCase()}`}>{person.customer}</span></td><td><span className={`state-tag ${person.employee.toLowerCase()}`}>{person.employee}</span></td><td>{person.role}</td><td>{person.access}</td></tr>)}</tbody></table></div>
        <div className="identity-panel-foot">Example: terminating an employee does not automatically close that person’s customer account.</div>
      </div>
      <div className="identity-lower-grid">
        <div className="identity-panel"><div className="identity-panel-head"><div><h3>Organizational roles</h3><p>Titles describe positions; permissions authorize actions.</p></div></div><div className="role-list">{roles.map(([name, dept, detail, level]) => <div className="role-row" key={name}><span className="role-swatch"/><div><b>{name}</b><small>{dept} · {detail}</small></div><span className="role-level">{level}</span></div>)}</div></div>
        <div className="identity-panel security-panel"><div className="eyebrow">SECURITY MODEL</div><h3>Deny by default.</h3><p>Every protected action must be checked on the server against the current identity, relationship, permission, scope and session state.</p><ul><li>Explicit permission grants</li><li>Separate customer / employee lifecycle</li><li>Audited privileged changes</li><li>Session lock independent of employment</li></ul><span className="security-foot">Authentication alone does not grant MME OS access.</span></div>
      </div>
      <div className="identity-boundary"><b>Implementation boundary</b><p>This screen is a preview prototype using fictional sample data. It is not connected to Supabase, does not authenticate users, and does not enforce permissions. The separate Build 004 database foundation remains under review and has not been applied to a live database.</p></div>
    </section>
    <footer className="identity-footer"><span>MUCH MORE ELECTRONICS · MME OS</span><span>BUILD 004 · IDENTITY MATRIX</span></footer>
  </main>;
}
