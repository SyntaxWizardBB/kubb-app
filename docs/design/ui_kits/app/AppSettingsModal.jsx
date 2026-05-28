/* global React, BK */
const { useState } = React;
const { Icon } = BK;

// =====================================================================
// Modal: App-Einstellungen (öffnet via Hamburger auf Home)
// Slides up from bottom as a modal sheet.
// =====================================================================
function AppSettingsModal({ onClose, onOpenStats, onOpenAchievements, onOpenExport, onOpenReset }) {
  const [language, setLanguage] = useState('de-CH');
  const [vibrate, setVibrate] = useState(true);
  const [unit, setUnit] = useState('m');
  const [theme, setTheme] = useState('hell');

  return (
    <div style={a.backdrop} onClick={onClose}>
      <div style={a.sheet} onClick={e => e.stopPropagation()}>
        <div style={a.grabber}/>
        <div style={a.head}>
          <div>
            <div style={a.eyebrow}>Menü</div>
            <h2 style={a.title}>App-Einstellungen</h2>
          </div>
          <button style={a.iconBtn} onClick={onClose} aria-label="Schliessen"><Icon.Close/></button>
        </div>

        <div style={a.section}>App</div>
        <div style={a.group}>
          <Row label="Sprache">
            <Seg value={language} options={['de-CH','de-DE','en']} onChange={setLanguage}/>
          </Row>
          <Row label="Distanz-Einheit">
            <Seg value={unit} options={['m','ft']} onChange={setUnit}/>
          </Row>
          <Row label="Vibration beim Tippen">
            <Toggle on={vibrate} onChange={setVibrate}/>
          </Row>
          <Row label="Theme">
            <Seg value={theme} options={['hell','dunkel','auto']} onChange={setTheme}/>
          </Row>
        </div>

        <div style={a.section}>Daten</div>
        <div style={a.group}>
          <NavRow icon={<Icon.Stat/>}     label="Statistik"               sub="Trefferquote, Streaks, Verlauf"     onClick={onOpenStats}/>
          <NavRow icon={<Icon.Trophy/>}   label="Erfolge"                 sub="Meilensteine"                       onClick={onOpenAchievements}/>
          <NavRow icon={<Icon.Download/>} label="CSV-Export"              sub="Sessions als .csv-Datei"            onClick={onOpenExport}/>
          <NavRow icon={<Icon.Trash/>}    label="Userdaten löschen"       sub="alle gespeicherten Sessions & Statistiken" tone="danger" onClick={onOpenReset}/>
          <NavRow icon={<Icon.Trash/>}    label="Profil löschen"          sub="Account & alle Daten unwiderruflich entfernen" tone="danger" onClick={onOpenReset}/>
        </div>

        <div style={a.footer}>
          <span>Kubb Club · v0.1.0</span>
          <span>Für die Wiese gebaut.</span>
        </div>
      </div>
    </div>
  );
}

function Row({ label, children }) {
  return (
    <div style={a.row}>
      <span style={a.rowLbl}>{label}</span>
      <div style={a.rowVal}>{children}</div>
    </div>
  );
}
function NavRow({ icon, label, sub, onClick, tone }) {
  const lblColor = tone === 'danger' ? 'var(--bk-danger)' : 'var(--bk-fg)';
  const iconColor = tone === 'danger' ? 'var(--bk-danger)' : 'var(--bk-fg-muted)';
  return (
    <button style={a.navRow} onClick={onClick}>
      <span style={{...a.navIcon, color:iconColor}}>{icon}</span>
      <span style={a.navText}>
        <span style={{...a.navLbl, color:lblColor}}>{label}</span>
        {sub && <span style={a.navSub}>{sub}</span>}
      </span>
      <span style={a.chev}><Icon.ChevronRight/></span>
    </button>
  );
}
function Seg({ value, options, onChange }) {
  return (
    <div style={a.seg}>
      {options.map(o => (
        <button key={o} style={{...a.segBtn, ...(value===o ? a.segBtnOn : {})}}
                onClick={() => onChange(o)}>{o}</button>
      ))}
    </div>
  );
}
function Toggle({ on, onChange }) {
  return (
    <button style={{...a.toggle, background: on ? 'var(--bk-meadow-500)' : 'var(--bk-stone-200)'}}
            onClick={() => onChange(!on)}>
      <span style={{...a.toggleKnob, transform: on ? 'translateX(20px)' : 'translateX(0)'}}/>
    </button>
  );
}

const a = {
  backdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.55)', display:'flex', alignItems:'flex-end', zIndex:20 },
  sheet: { width:'100%', maxHeight:'92%', overflowY:'auto', background:'var(--bk-bg)', borderTopLeftRadius:24, borderTopRightRadius:24, padding:'10px 0 40px', display:'flex', flexDirection:'column' },
  grabber: { width:36, height:4, background:'var(--bk-stone-200)', borderRadius:999, alignSelf:'center', marginBottom:6 },
  head: { display:'flex', alignItems:'flex-start', justifyContent:'space-between', padding:'4px 18px 12px' },
  eyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  title: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:24, margin:0, letterSpacing:'-0.02em' },
  iconBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },

  section: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', padding:'8px 18px 6px' },
  group: { background:'var(--bk-bg-raised)', borderRadius:14, margin:'0 16px 6px', padding:'4px 14px' },

  row: { display:'flex', flexDirection:'column', gap:6, padding:'10px 0', borderBottom:'1px solid var(--bk-line)' },
  rowLbl: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  rowVal: { display:'flex' },

  navRow: { display:'flex', alignItems:'center', gap:14, padding:'12px 0', minHeight:60, width:'100%', background:'transparent', border:0, borderBottom:'1px solid var(--bk-line)', textAlign:'left', cursor:'pointer', color:'inherit' },
  navIcon: { width:36, height:36, display:'grid', placeItems:'center', background:'var(--bk-bg-sunken)', borderRadius:10, flexShrink:0 },
  navText: { display:'flex', flexDirection:'column', gap:2, flex:1, minWidth:0 },
  navLbl: { fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:15 },
  navSub: { fontSize:12, color:'var(--bk-fg-muted)' },
  chev: { color:'var(--bk-fg-muted)' },

  seg: { display:'flex', background:'var(--bk-bg-sunken)', borderRadius:999, padding:3, gap:0 },
  segBtn: { flex:1, minHeight:34, padding:'0 12px', border:0, borderRadius:999, background:'transparent', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:13, cursor:'pointer' },
  segBtnOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)' },

  toggle: { width:48, height:28, borderRadius:999, border:0, padding:2, cursor:'pointer', display:'flex', alignItems:'center', transition:'background 120ms ease' },
  toggleKnob: { display:'block', width:24, height:24, borderRadius:'50%', background:'#fff', boxShadow:'0 1px 3px rgba(0,0,0,0.2)', transition:'transform 120ms ease' },

  footer: { padding:'14px 18px 6px', textAlign:'center', display:'flex', flexDirection:'column', gap:4, fontSize:11, color:'var(--bk-fg-muted)' },
};

window.AppSettingsModal = AppSettingsModal;
