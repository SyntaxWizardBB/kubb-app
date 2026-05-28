/* global React */
// =====================================================================
// AppSettingsModal — Schnell-Einstellungen für Desktop.
//   Modal-Panel (480px breit) mit App-Preferences als Quick-Edit.
//   Pendant zur mobilen AppSettingsModal (Bottom-Sheet).
// =====================================================================

const { useState: useAppModState } = React;

function AppSettingsModal({ onClose, onOpenExport, onOpenReset }) {
  const [lang, setLang]       = useAppModState('de-CH');
  const [unit, setUnit]       = useAppModState('m');
  const [theme, setTheme]     = useAppModState('hell');
  const [vibrate, setVibrate] = useAppModState(true);
  const [autosave, setAutosave] = useAppModState(true);

  return (
    <div style={am.backdrop} onClick={onClose}>
      <div style={am.modal} onClick={e => e.stopPropagation()}>
        <header style={am.head}>
          <div>
            <div style={am.eyebrow}>Menü</div>
            <h2 style={am.title}>Schnell-Einstellungen</h2>
          </div>
          <button style={am.close} onClick={onClose} aria-label="Schliessen">×</button>
        </header>

        <div style={am.body}>
          <div style={am.section}>App</div>
          <div style={am.group}>
            <Row label="Sprache"><Seg value={lang} options={['de-CH','de-DE','en']} onChange={setLang}/></Row>
            <Row label="Distanz-Einheit"><Seg value={unit} options={['m','ft']} onChange={setUnit}/></Row>
            <Row label="Theme"><Seg value={theme} options={['hell','dunkel','auto']} onChange={setTheme}/></Row>
            <Row label="Vibration beim Tippen"><Toggle on={vibrate} onChange={setVibrate}/></Row>
            <Row label="Auto-Speichern"><Toggle on={autosave} onChange={setAutosave}/></Row>
          </div>

          <div style={am.section}>Daten</div>
          <div style={am.group}>
            <NavRow icon="📊" label="Statistik" sub="Trefferquote, Streaks, Verlauf"/>
            <NavRow icon="🏆" label="Erfolge" sub="Meilensteine"/>
            <NavRow icon="⬇" label="CSV-Export" sub="Sessions als .csv-Datei" onClick={onOpenExport}/>
            <NavRow icon="↺" label="Userdaten löschen" sub="alle Sessions & Statistik" tone="danger" onClick={onOpenReset}/>
            <NavRow icon="✕" label="Profil löschen" sub="Account & alle Daten unwiderruflich" tone="danger"/>
          </div>

          <div style={am.footer}>
            <div>Kubb Club · v0.1.0</div>
            <div>Für die Wiese gebaut.</div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Row({ label, children }) {
  return (
    <div style={am.row}>
      <span style={am.rowLbl}>{label}</span>
      <div style={am.rowVal}>{children}</div>
    </div>
  );
}
function NavRow({ icon, label, sub, onClick, tone }) {
  return (
    <button style={am.nav} onClick={onClick}>
      <span style={am.navIcon}>{icon}</span>
      <span style={am.navText}>
        <span style={{...am.navLbl, color: tone === 'danger' ? 'var(--kc-miss)' : 'var(--kc-fg)'}}>{label}</span>
        <span style={am.navSub}>{sub}</span>
      </span>
      <span style={am.navChev}>›</span>
    </button>
  );
}
function Seg({ value, options, onChange }) {
  return (
    <div style={am.seg}>
      {options.map(o => (
        <button key={o} style={{...am.segBtn, ...(value === o ? am.segBtnOn : {})}}
                onClick={() => onChange(o)}>{o}</button>
      ))}
    </div>
  );
}
function Toggle({ on, onChange }) {
  return (
    <button style={{...am.toggle, background: on ? 'var(--kc-meadow-500)' : 'var(--kc-stone-200)'}}
            onClick={() => onChange(!on)}>
      <span style={{...am.toggleKnob, transform: on ? 'translateX(20px)' : 'translateX(0)'}}/>
    </button>
  );
}

const am = {
  backdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.55)', display:'grid', placeItems:'center', zIndex:40 },
  modal: { width:520, maxWidth:'92vw', maxHeight:'92vh', background:'var(--kc-bg-raised)', borderRadius:18, boxShadow:'var(--kc-shadow-4)', display:'flex', flexDirection:'column', overflow:'hidden' },
  head: { display:'flex', alignItems:'flex-start', justifyContent:'space-between', padding:'22px 24px 12px', borderBottom:'1px solid var(--kc-line)' },
  eyebrow: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  title: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:24, letterSpacing:'-0.02em', margin:'2px 0 0', fontVariationSettings:'"opsz" 72' },
  close: { width:36, height:36, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontSize:24, cursor:'pointer', lineHeight:1 },

  body: { padding:'8px 16px 18px', overflowY:'auto' },
  section: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)', padding:'14px 8px 8px' },
  group: { background:'var(--kc-bg-sunken)', borderRadius:14, padding:'4px 14px' },

  row: { display:'flex', justifyContent:'space-between', alignItems:'center', gap:12, padding:'12px 0', borderBottom:'1px solid var(--kc-line)' },
  rowLbl: { fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:14 },
  rowVal: { display:'flex' },

  nav: { display:'flex', alignItems:'center', gap:14, padding:'12px 0', minHeight:56, width:'100%', background:'transparent', border:0, borderBottom:'1px solid var(--kc-line)', textAlign:'left', cursor:'pointer', color:'inherit' },
  navIcon: { width:36, height:36, display:'grid', placeItems:'center', background:'var(--kc-bg-raised)', borderRadius:10, color:'var(--kc-fg-muted)', fontSize:16, flexShrink:0 },
  navText: { display:'flex', flexDirection:'column', gap:1, flex:1, minWidth:0 },
  navLbl: { fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:14 },
  navSub: { fontSize:12, color:'var(--kc-fg-muted)' },
  navChev: { color:'var(--kc-fg-muted)', fontSize:18 },

  seg: { display:'flex', background:'var(--kc-bg-raised)', borderRadius:999, padding:3 },
  segBtn: { minHeight:32, padding:'0 12px', border:0, borderRadius:999, background:'transparent', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:12, cursor:'pointer' },
  segBtnOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  toggle: { width:48, height:28, borderRadius:999, border:0, padding:2, cursor:'pointer', display:'flex', alignItems:'center', transition:'background 120ms ease' },
  toggleKnob: { display:'block', width:24, height:24, borderRadius:999, background:'#fff', boxShadow:'0 1px 3px rgba(0,0,0,0.2)', transition:'transform 120ms ease' },

  footer: { padding:'18px 8px 4px', textAlign:'center', display:'flex', flexDirection:'column', gap:2, fontSize:11, color:'var(--kc-fg-muted)' },
};

window.AppSettingsModal = AppSettingsModal;
