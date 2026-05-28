/* global React, BK */
const { Icon, AppBar } = BK;

// =====================================================================
// Screen: Settings (drawer-style; opens from hamburger on Home)
// Lists: Statistik, Profil, App-Einstellungen, CSV-Export, Erfolge.
// =====================================================================
function SettingsScreen({ onBack, onOpen }) {
  return (
    <div style={se.screen}>
      <AppBar eyebrow="Menü" title="Einstellungen" onBack={onBack}/>

      <section style={se.profileBlock}>
        <div style={se.avatar}>M</div>
        <div>
          <div style={se.profileName}>Marc Brosius</div>
          <div style={se.profileMeta}>Profil aktiv · seit Apr 2024</div>
        </div>
      </section>

      <div style={se.group}>
        <SettingsRow icon={<Icon.Stat/>}    label="Statistik"          sub="Trefferquote, Streaks, Verlauf"   onClick={() => onOpen('stats')}/>
        <SettingsRow icon={<Icon.Profile/>} label="Profil"             sub="Name, Wurf-Hand, Stamm-Distanz"   onClick={() => onOpen('profile')}/>
        <SettingsRow icon={<Icon.Gear/>}    label="App-Einstellungen"  sub="Sprache, Vibration, Sonneneinheit" onClick={() => onOpen('app')}/>
      </div>

      <div style={se.section}>Daten</div>
      <div style={se.group}>
        <SettingsRow icon={<Icon.Trophy/>}  label="Erfolge"            sub="Meilensteine"                      onClick={() => onOpen('achievements')}/>
        <SettingsRow icon={<Icon.Download/>} label="CSV-Export"        sub="Sessions als .csv-Datei"           onClick={() => onOpen('export')}/>
        <SettingsRow icon={<Icon.Trash/>}   label="Sessions zurücksetzen" sub="alle gespeicherten Sessions löschen" onClick={() => onOpen('reset')} tone="danger"/>
      </div>

      <div style={se.footer}>
        <div style={se.footerLine}>Kubb Club · v0.1.0</div>
        <div style={se.footerLine}>Für die Wiese gebaut.</div>
      </div>
    </div>
  );
}

function SettingsRow({ icon, label, sub, onClick, tone }) {
  const lblColor = tone === 'danger' ? 'var(--bk-danger)' : 'var(--bk-fg)';
  const iconColor = tone === 'danger' ? 'var(--bk-danger)' : 'var(--bk-fg-muted)';
  return (
    <button style={se.row} onClick={onClick}>
      <span style={{...se.rowIcon, color:iconColor}}>{icon}</span>
      <span style={se.rowText}>
        <span style={{...se.rowLabel, color:lblColor}}>{label}</span>
        {sub && <span style={se.rowSub}>{sub}</span>}
      </span>
      <span style={se.rowChevron}><Icon.ChevronRight/></span>
    </button>
  );
}

const se = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflowY:'auto', padding:'0 0 32px' },

  profileBlock: { display:'flex', alignItems:'center', gap:14, padding:'10px 18px 18px' },
  avatar: { width:56, height:56, borderRadius:'50%', background:'var(--bk-meadow-600)', color:'var(--bk-on-primary)', display:'grid', placeItems:'center', fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:24 },
  profileName: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:18, letterSpacing:'-0.01em' },
  profileMeta: { fontSize:12, color:'var(--bk-fg-muted)', marginTop:2 },

  section: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', padding:'14px 18px 8px' },

  group: { background:'var(--bk-bg-raised)', borderRadius:14, margin:'0 16px', overflow:'hidden' },
  row: { display:'flex', alignItems:'center', gap:14, padding:'14px 16px', minHeight:64, width:'100%', background:'transparent', border:0, borderBottom:'1px solid var(--bk-line)', textAlign:'left', cursor:'pointer', color:'inherit' },
  rowIcon: { width:36, height:36, display:'grid', placeItems:'center', background:'var(--bk-bg-sunken)', borderRadius:10, flexShrink:0 },
  rowText: { display:'flex', flexDirection:'column', gap:2, flex:1, minWidth:0 },
  rowLabel: { fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:16 },
  rowSub: { fontSize:12, color:'var(--bk-fg-muted)' },
  rowChevron: { color:'var(--bk-fg-muted)' },

  footer: { padding:'24px 18px 8px', textAlign:'center' },
  footerLine: { fontSize:12, color:'var(--bk-fg-muted)', lineHeight:1.6 },
};

window.SettingsScreen = SettingsScreen;
