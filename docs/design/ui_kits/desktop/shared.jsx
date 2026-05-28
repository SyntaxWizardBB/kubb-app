/* global React */
// Kubb Club — Desktop UI Kit · shared components & icons.
// All scripts share scope via window.* exports at the bottom.

const { useState, useMemo, useCallback } = React;

// ---------- Stroke icons (24 px, currentColor) ----------
const DIcon = {
  Home:    (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M3 11l9-8 9 8v9a2 2 0 0 1-2 2h-4v-7H9v7H5a2 2 0 0 1-2-2z"/></svg>,
  Target:  (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.4" fill="currentColor"/></svg>,
  Stat:    (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M3 20h18"/><rect x="5" y="12" width="3" height="6"/><rect x="11" y="6" width="3" height="12"/><rect x="17" y="9" width="3" height="9"/></svg>,
  Cup:     (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M5 4h14v3a5 5 0 0 1-5 5h-4a5 5 0 0 1-5-5V4z"/><path d="M5 6H3v2a3 3 0 0 0 3 3M19 6h2v2a3 3 0 0 1-3 3"/><path d="M12 12v4M9 20h6M10 16h4l1 4H9z"/></svg>,
  Users:   (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><circle cx="9" cy="8" r="3.5"/><path d="M2 21a7 7 0 0 1 14 0"/><path d="M16 5a3 3 0 0 1 0 6M22 21a6 6 0 0 0-4-5.7"/></svg>,
  Profile: (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>,
  Gear:    (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9c.3.6.9 1 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>,
  Inbox:   (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M3 13l3-9h12l3 9"/><path d="M3 13v6a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-6h-6a3 3 0 0 1-6 0z"/></svg>,
  Plus:    (p) => <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" {...p}><path d="M12 5v14M5 12h14"/></svg>,
  Plus2:   (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" {...p}><path d="M12 5v14M5 12h14"/></svg>,
  Minus:   (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" {...p}><path d="M5 12h14"/></svg>,
  Search:  (p) => <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>,
  Chevron: (p) => <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M9 6l6 6-6 6"/></svg>,
  King:    (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M3 18h18M5 18l-1-9 4 4 4-7 4 7 4-4-1 9"/></svg>,
  Flame:   (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4-.5 2 .5 3 1 3 0-3 1-6 2-9z"/></svg>,
  Heli:    (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M3 8h18M5 12h14M7 16h10"/><path d="M12 4v16"/></svg>,
  Bell:    (p) => <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M6 18V11a6 6 0 0 1 12 0v7l2 2H4z"/><path d="M10 22a2 2 0 0 0 4 0"/></svg>,
  Pause:   (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" {...p}><path d="M9 5v14M15 5v14"/></svg>,
  Stop:    (p) => <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" {...p}><rect x="6" y="6" width="12" height="12" rx="2"/></svg>,
  Undo:    (p) => <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><path d="M9 14l-4-4 4-4"/><path d="M5 10h9a5 5 0 0 1 0 10h-3"/></svg>,
  Calendar:(p) => <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...p}><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 9h18M8 3v4M16 3v4"/></svg>,
};

// =====================================================================
// Sidebar — primary navigation. Pinned 240 px wide.
// =====================================================================
function Sidebar({ route, onRoute, badges = {} }) {
  const items = [
    { key:'dashboard',  label:'Dashboard',    icon:DIcon.Home,    section:'main' },
    { key:'training',   label:'Training',     icon:DIcon.Target,  section:'main' },
    { key:'stats',      label:'Statistik',    icon:DIcon.Stat,    section:'main' },
    { key:'tournament', label:'Turniere',     icon:DIcon.Cup,     section:'main', badge: badges.tournament },
    { key:'match',      label:'Match',        icon:DIcon.Flame,   section:'main' },
    { key:'club',       label:'Club & Freunde', icon:DIcon.Users, section:'community' },
    { key:'inbox',      label:'Inbox',        icon:DIcon.Inbox,   section:'community', badge: badges.inbox },
    { key:'profile',    label:'Profil',       icon:DIcon.Profile, section:'account' },
    { key:'settings',   label:'Einstellungen', icon:DIcon.Gear,   section:'account' },
  ];

  return (
    <aside style={sb.aside}>
      <a href="#" style={sb.brand} onClick={(e)=>{e.preventDefault(); onRoute('dashboard');}}>
        <img src="../../assets/logo-mark.svg" width="36" height="36" alt=""/>
        <div>
          <div style={sb.brandName}>Kubb Club</div>
          <div style={sb.brandTag}>Saison '25 · DACH</div>
        </div>
      </a>

      <nav style={sb.nav}>
        {['main','community','account'].map(section => (
          <div key={section} style={sb.section}>
            {items.filter(i => i.section === section).map(it => {
              const active = route === it.key;
              return (
                <button key={it.key}
                        style={{...sb.item, ...(active ? sb.itemActive : {})}}
                        onClick={() => onRoute(it.key)}>
                  <it.icon/>
                  <span style={{flex:1, textAlign:'left'}}>{it.label}</span>
                  {it.badge ? <span style={sb.badge}>{it.badge}</span> : null}
                </button>
              );
            })}
          </div>
        ))}
      </nav>

      <a href="#" style={sb.profile} onClick={(e)=>{e.preventDefault(); onRoute('profile');}}>
        <div style={sb.avatar}>MB</div>
        <div style={{flex:1, minWidth:0}}>
          <div style={sb.profileName}>Marc B.</div>
          <div style={sb.profileSub}>BKC · 1283 ELO</div>
        </div>
        <DIcon.Chevron/>
      </a>
    </aside>
  );
}

const sb = {
  aside: { width:240, minHeight:'100%', background:'var(--kc-bg-raised)', borderRight:'1px solid var(--kc-line)', padding:'20px 14px 14px', display:'flex', flexDirection:'column', gap:8, position:'sticky', top:0 },
  brand: { display:'flex', alignItems:'center', gap:12, padding:'4px 6px 14px', textDecoration:'none', color:'inherit' },
  brandName: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:18, letterSpacing:'-0.02em', color:'var(--kc-fg)', fontVariationSettings:'"opsz" 36' },
  brandTag: { fontFamily:'var(--kc-font-mono)', fontSize:10, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)', marginTop:2, whiteSpace:'nowrap' },
  nav: { display:'flex', flexDirection:'column', gap:14, flex:1 },
  section: { display:'flex', flexDirection:'column', gap:2 },
  item: { display:'flex', alignItems:'center', gap:12, padding:'10px 12px', minHeight:40, borderRadius:10, background:'transparent', border:0, color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:14, cursor:'pointer', textAlign:'left', width:'100%' },
  itemActive: { background:'var(--kc-meadow-50)', color:'var(--kc-meadow-700)' },
  badge: { minWidth:20, height:20, borderRadius:999, background:'var(--kc-miss)', color:'#fff', fontSize:11, fontWeight:700, display:'grid', placeItems:'center', padding:'0 6px' },
  profile: { display:'flex', alignItems:'center', gap:10, padding:'10px 8px', borderRadius:12, background:'var(--kc-bg-sunken)', color:'var(--kc-fg)', textDecoration:'none' },
  avatar: { width:36, height:36, borderRadius:999, background:'var(--kc-meadow-500)', color:'#fff', fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14, display:'grid', placeItems:'center', flexShrink:0 },
  profileName: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14, color:'var(--kc-fg)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' },
  profileSub: { fontFamily:'var(--kc-font-mono)', fontSize:10, letterSpacing:'0.06em', color:'var(--kc-fg-muted)' },
};

// =====================================================================
// TopBar — sits above page content. Page title + search + actions.
// =====================================================================
function TopBar({ eyebrow, title, subtitle, right }) {
  return (
    <div style={tb.row}>
      <div>
        {eyebrow && <div style={tb.eyebrow}>{eyebrow}</div>}
        <h1 style={tb.title}>{title}</h1>
        {subtitle && <div style={tb.sub}>{subtitle}</div>}
      </div>
      <div style={tb.right}>{right}</div>
    </div>
  );
}

const tb = {
  row: { display:'flex', alignItems:'flex-end', justifyContent:'space-between', gap:24, padding:'32px 40px 24px', borderBottom:'1px solid var(--kc-line)' },
  eyebrow: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.1em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  title: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:44, lineHeight:1.05, letterSpacing:'-0.025em', margin:'4px 0 0', fontVariationSettings:'"opsz" 72' },
  sub: { fontSize:15, color:'var(--kc-fg-muted)', marginTop:8, maxWidth:560 },
  right: { display:'flex', gap:10, alignItems:'center', flexShrink:0 },
};

// =====================================================================
// Buttons — reused across screens.
// =====================================================================
function PrimaryBtn({ children, onClick, icon, size='md' }) {
  const sizes = {
    sm: { height:36, padding:'0 14px', fontSize:13 },
    md: { height:44, padding:'0 18px', fontSize:14 },
    lg: { height:52, padding:'0 22px', fontSize:16 },
  }[size];
  return (
    <button onClick={onClick} style={{display:'inline-flex', alignItems:'center', gap:8, borderRadius:12, border:0, background:'var(--kc-meadow-600)', color:'var(--kc-on-primary)', fontFamily:'var(--kc-font-ui)', fontWeight:700, cursor:'pointer', boxShadow:'var(--kc-shadow-1)', letterSpacing:'-0.01em', whiteSpace:'nowrap', ...sizes}}>
      {icon}{children}
    </button>
  );
}

function SecondaryBtn({ children, onClick, icon, tone='default', size='md' }) {
  const sizes = {
    sm: { height:36, padding:'0 14px', fontSize:13 },
    md: { height:44, padding:'0 16px', fontSize:14 },
  }[size];
  const tones = {
    default: { background:'var(--kc-bg-raised)', color:'var(--kc-fg)', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-200)' },
    ink:     { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },
    ghost:   { background:'transparent', color:'var(--kc-fg)' },
  }[tone];
  return (
    <button onClick={onClick} style={{display:'inline-flex', alignItems:'center', gap:8, borderRadius:12, border:0, fontFamily:'var(--kc-font-ui)', fontWeight:600, cursor:'pointer', letterSpacing:'-0.01em', whiteSpace:'nowrap', ...sizes, ...tones}}>
      {icon}{children}
    </button>
  );
}

// =====================================================================
// Card — base raised card with optional eyebrow + title.
// =====================================================================
function Card({ children, padding=20, raised=true, style={} }) {
  return (
    <section style={{
      background:'var(--kc-bg-raised)',
      borderRadius:16,
      padding,
      boxShadow: raised ? 'var(--kc-shadow-1)' : 'none',
      border: raised ? 'none' : '1px solid var(--kc-line)',
      ...style,
    }}>{children}</section>
  );
}

function CardHeader({ eyebrow, title, right }) {
  return (
    <header style={{display:'flex', justifyContent:'space-between', alignItems:'flex-end', gap:12, marginBottom:14}}>
      <div>
        {eyebrow && <div style={{fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)'}}>{eyebrow}</div>}
        <h3 style={{fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:18, letterSpacing:'-0.01em', margin:'2px 0 0'}}>{title}</h3>
      </div>
      {right}
    </header>
  );
}

// =====================================================================
// Shell — sidebar + main area. Used by every screen.
// =====================================================================
function Shell({ route, onRoute, children, badges }) {
  return (
    <div style={shell.root}>
      <Sidebar route={route} onRoute={onRoute} badges={badges}/>
      <main style={shell.main}>{children}</main>
    </div>
  );
}

const shell = {
  root: { display:'flex', minHeight:'100vh', background:'var(--kc-bg)', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)' },
  main: { flex:1, minWidth:0 },
};

// Expose everything to the global scope for sibling Babel scripts.
Object.assign(window, { DIcon, Sidebar, TopBar, PrimaryBtn, SecondaryBtn, Card, CardHeader, Shell });
