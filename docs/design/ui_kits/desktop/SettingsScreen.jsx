/* global React, DIcon, TopBar, PrimaryBtn, SecondaryBtn, Card, CardHeader, AppSettingsModal, CsvExportModal */
// =====================================================================
// Settings — Hauptseite, parallel zur mobile Drawer-Variante.
//   Drei-Spalten-Layout:
//     Left  (260): Side-Nav für Settings-Sektionen (sticky)
//     Center (flex): Inhalt der aktiven Sektion
//     Right (300): Quick-Actions (Export, Reset, App-Version)
// =====================================================================

const { useState: useSetState } = React;

const SECTIONS = [
  { id:'account',    label:'Konto',           icon:DIcon.Profile },
  { id:'app',        label:'App-Einstellungen', icon:DIcon.Gear  },
  { id:'play',       label:'Spielregeln',     icon:DIcon.Target  },
  { id:'notifications', label:'Benachrichtigungen', icon:DIcon.Bell },
  { id:'data',       label:'Daten & Export',  icon:DIcon.Inbox   },
  { id:'integrations', label:'Integrationen', icon:DIcon.Users   },
  { id:'about',      label:'Über · v0.1.0',   icon:DIcon.Chevron },
];

function SettingsScreen({ onRoute }) {
  const [section, setSection] = useSetState('app');
  const [openModal, setOpenModal] = useSetState(null);   // 'app' | 'export' | 'reset'
  const sec = SECTIONS.find(s => s.id === section) || SECTIONS[0];

  return (
    <>
      <TopBar
        eyebrow="Menü · Einstellungen"
        title="Einstellungen"
        subtitle="Sprache, Vibration, Theme, Datenexport und Spielregeln — alle Optionen an einem Ort."
        right={<>
          <SecondaryBtn tone="ghost" onClick={() => setOpenModal('export')} icon={<DIcon.Inbox/>}>CSV-Export…</SecondaryBtn>
          <SecondaryBtn tone="default" onClick={() => setOpenModal('app')} icon={<DIcon.Gear/>}>Schnell-Einstellungen…</SecondaryBtn>
        </>}
      />

      <div style={ss.split}>
        {/* LEFT — section nav */}
        <aside style={ss.aside}>
          <div style={ss.userCard}>
            <div style={ss.userAvatar}>MB</div>
            <div style={{flex:1, minWidth:0}}>
              <div style={ss.userName}>Marc Brosius</div>
              <div style={ss.userSub}>Profil aktiv · seit Apr 2024</div>
            </div>
            <button style={ss.userEdit} onClick={() => onRoute && onRoute('profile')}>Profil</button>
          </div>
          <nav style={ss.nav}>
            {SECTIONS.map(s => {
              const active = section === s.id;
              return (
                <button key={s.id}
                        style={{...ss.navItem, ...(active ? ss.navItemActive : {})}}
                        onClick={() => setSection(s.id)}>
                  <s.icon/>
                  <span style={{flex:1, textAlign:'left'}}>{s.label}</span>
                  {active && <span style={ss.navDot}/>}
                </button>
              );
            })}
          </nav>
        </aside>

        {/* CENTER — content */}
        <main style={ss.main}>
          <Card padding={26}>
            <div style={ss.sectionHead}>
              <div>
                <div style={ss.eyebrow}>Sektion</div>
                <h2 style={ss.sectionTitle}>{sec.label}</h2>
              </div>
            </div>

            {section === 'account'     && <AccountSection onRoute={onRoute}/>}
            {section === 'app'         && <AppSection/>}
            {section === 'play'        && <PlaySection/>}
            {section === 'notifications' && <NotifSection/>}
            {section === 'data'        && <DataSection openModal={setOpenModal}/>}
            {section === 'integrations' && <IntegrationsSection/>}
            {section === 'about'       && <AboutSection/>}
          </Card>
        </main>

        {/* RIGHT — quick actions / status */}
        <aside style={ss.rightCol}>
          <Card padding={18}>
            <div style={ss.eyebrow}>Schnellzugriff</div>
            <div style={ss.quickList}>
              <button style={ss.quick} onClick={() => onRoute && onRoute('stats')}>
                <DIcon.Stat/>
                <span style={{flex:1, textAlign:'left'}}>Zur Statistik</span>
                <DIcon.Chevron/>
              </button>
              <button style={ss.quick} onClick={() => setOpenModal('export')}>
                <DIcon.Inbox/>
                <span style={{flex:1, textAlign:'left'}}>CSV-Export…</span>
                <DIcon.Chevron/>
              </button>
              <button style={ss.quick} onClick={() => onRoute && onRoute('profile')}>
                <DIcon.Profile/>
                <span style={{flex:1, textAlign:'left'}}>Profil bearbeiten</span>
                <DIcon.Chevron/>
              </button>
              <button style={ss.quick}>
                <DIcon.Cup/>
                <span style={{flex:1, textAlign:'left'}}>Erfolge ansehen</span>
                <DIcon.Chevron/>
              </button>
              <button style={{...ss.quick, color:'var(--kc-miss)'}} onClick={() => setOpenModal('reset')}>
                <DIcon.Undo/>
                <span style={{flex:1, textAlign:'left'}}>Sessions zurücksetzen…</span>
                <DIcon.Chevron/>
              </button>
            </div>
          </Card>

          <Card padding={18}>
            <div style={ss.eyebrow}>Status</div>
            <div style={ss.statusList}>
              <Status label="Speicherplatz" value="38 MB · 612 Sessions"/>
              <Status label="Synchronisiert" value="vor 2 Min" tone="ok"/>
              <Status label="Cloud-Backup" value="aktiviert" tone="ok"/>
              <Status label="App-Version" value="v0.1.0 (build 184)" mono/>
            </div>
          </Card>

          <div style={ss.footer}>
            <div>Kubb Club · für die Wiese gebaut.</div>
            <div>© 2025 BKC · made in Bern, CH</div>
          </div>
        </aside>
      </div>

      {openModal === 'app'    && <AppSettingsModal onClose={() => setOpenModal(null)} onOpenExport={() => setOpenModal('export')} onOpenReset={() => setOpenModal('reset')}/>}
      {openModal === 'export' && <CsvExportModal onClose={() => setOpenModal(null)}/>}
      {openModal === 'reset'  && <ResetModal onClose={() => setOpenModal(null)}/>}
    </>
  );
}

// ---------- Sections ----------
function AccountSection({ onRoute }) {
  return (
    <div style={ss.cont}>
      <SettingRow label="Anzeigename" value="Marc Brosius" action="ändern" onAction={() => onRoute && onRoute('profile')}/>
      <SettingRow label="E-Mail" value="marc@brosius.ch" action="ändern" onAction={() => onRoute && onRoute('profile')}/>
      <SettingRow label="Passwort" value="zuletzt vor 3 Monaten" action="ändern" onAction={() => onRoute && onRoute('profile')}/>
      <SettingRow label="Anmeldungen" value="Apple · verknüpft" action="verwalten" onAction={() => onRoute && onRoute('profile')}/>
      <SettingRow label="Profil löschen" value="alle Daten unwiderruflich entfernen" action="löschen" tone="danger"/>
    </div>
  );
}

function AppSection() {
  const [lang, setLang]   = useSetState('de-CH');
  const [unit, setUnit]   = useSetState('m');
  const [theme, setTheme] = useSetState('hell');
  const [vibrate, setVibrate] = useSetState(true);
  const [autosave, setAutosave] = useSetState(true);
  const [bigType, setBigType] = useSetState(false);
  return (
    <div style={ss.cont}>
      <RowSeg label="Sprache" value={lang} options={['de-CH','de-DE','en','fr']} onChange={setLang}/>
      <RowSeg label="Distanz-Einheit" value={unit} options={['m','ft']} onChange={setUnit}/>
      <RowSeg label="Theme" value={theme} options={['hell','dunkel','auto']} onChange={setTheme}/>
      <RowToggle label="Vibration beim Tippen" sub="haptisches Feedback bei jeder Wurfaufzeichnung" on={vibrate} onChange={setVibrate}/>
      <RowToggle label="Auto-Speichern" sub="Sessions werden nach jedem Wurf gesichert" on={autosave} onChange={setAutosave}/>
      <RowToggle label="Grosse Outdoor-Schrift" sub="optimiert für direkte Sonneneinstrahlung" on={bigType} onChange={setBigType}/>
    </div>
  );
}

function PlaySection() {
  const [bestOf, setBestOf]     = useSetState('5');
  const [sticks, setSticks]     = useSetState('6');
  const [helitrack, setHelitrack] = useSetState(true);
  const [penalty, setPenalty]   = useSetState('schwedisch');
  return (
    <div style={ss.cont}>
      <RowSeg label="Standard-Format" value={bestOf} options={['3','5','7']} onChange={setBestOf}/>
      <RowSeg label="Stöcke pro Halbsatz" value={sticks} options={['4','5','6','8']} onChange={setSticks}/>
      <RowSeg label="Strafkubb-Regel" value={penalty} options={['schwedisch','schweiz','strikt']} onChange={setPenalty}/>
      <RowToggle label="Helikopter-Tracking" sub="Heli-Würfe werden in Statistik gezählt" on={helitrack} onChange={setHelitrack}/>
      <RowStatic label="Königs-Standard" value="280 × 80 mm · Schweizer Mass"/>
      <RowStatic label="Pitch-Mass" value="5 m × 8 m"/>
    </div>
  );
}

function NotifSection() {
  const [matches, setMatches]   = useSetState(true);
  const [tournaments, setTour] = useSetState(true);
  const [club, setClub]         = useSetState(false);
  const [weekly, setWeekly]     = useSetState(true);
  return (
    <div style={ss.cont}>
      <RowToggle label="Match-Einladungen" sub="Push wenn jemand dich zu einem Match einlädt" on={matches} onChange={setMatches}/>
      <RowToggle label="Turnier-Erinnerungen" sub="Tag vor Anpfiff & Spielplan-Updates" on={tournaments} onChange={setTour}/>
      <RowToggle label="Club-Aktivität" sub="neue Mitglieder, Trainings, Streaks im Club" on={club} onChange={setClub}/>
      <RowToggle label="Wöchentliche Auswertung" sub="Sonntags: Trefferquote & Vergleich zur Vorwoche" on={weekly} onChange={setWeekly}/>
    </div>
  );
}

function DataSection({ openModal }) {
  return (
    <div style={ss.cont}>
      <RowAction label="CSV-Export" sub="alle Sessions als .csv-Datei (Tabellenkalkulation)" action="exportieren" onAction={() => openModal('export')}/>
      <RowAction label="Cloud-Backup" sub="612 Sessions · 38 MB · zuletzt: vor 2 Min" action="jetzt sichern"/>
      <RowAction label="Wiederherstellen" sub="aus einem früheren Backup zurückrollen" action="wählen…"/>
      <RowAction label="Sessions zurücksetzen" sub="alle Trainings & Match-Daten löschen" action="zurücksetzen" tone="danger" onAction={() => openModal('reset')}/>
    </div>
  );
}

function IntegrationsSection() {
  const items = [
    { name:'Kubbtour.ch', sub:'Turniere automatisch importieren', on:true },
    { name:'Apple Health', sub:'Trainings als Workouts speichern', on:false },
    { name:'Strava', sub:'Sessions als Aktivität teilen', on:false },
    { name:'Discord (BKC)', sub:'Ergebnisse in #scores posten', on:true },
  ];
  return (
    <div style={ss.cont}>
      {items.map((it, i) => (
        <div key={i} style={ss.row}>
          <div>
            <div style={ss.rowLbl}>{it.name}</div>
            <div style={ss.rowSub}>{it.sub}</div>
          </div>
          <ToggleSwitch on={it.on}/>
        </div>
      ))}
    </div>
  );
}

function AboutSection() {
  return (
    <div style={ss.cont}>
      <div style={ss.aboutHero}>
        <img src="../../assets/logo-mark.svg" width="56" height="56" alt=""/>
        <div>
          <div style={ss.aboutName}>Kubb Club</div>
          <div style={ss.aboutSub}>v0.1.0 · build 184 · für die Wiese gebaut</div>
        </div>
      </div>
      <RowAction label="Was ist neu" sub="Release-Notes & geplante Features" action="öffnen"/>
      <RowAction label="Lizenzen" sub="Open-Source-Komponenten" action="ansehen"/>
      <RowAction label="Datenschutz" sub="Was wird wo gespeichert" action="lesen"/>
      <RowAction label="Feedback senden" sub="Direkt an das BKC-Team" action="schreiben"/>
    </div>
  );
}

// ---------- Row primitives ----------
function SettingRow({ label, value, action, onAction, tone }) {
  return (
    <div style={ss.row}>
      <div style={{minWidth:0}}>
        <div style={ss.rowLbl}>{label}</div>
        <div style={ss.rowSub}>{value}</div>
      </div>
      <button style={{...ss.rowAction, color: tone==='danger' ? 'var(--kc-miss)' : 'var(--kc-fg)', boxShadow:`inset 0 0 0 1.5px ${tone==='danger' ? 'var(--kc-miss)' : 'var(--kc-stone-200)'}`}} onClick={onAction}>{action}</button>
    </div>
  );
}
function RowSeg({ label, value, options, onChange }) {
  return (
    <div style={ss.row}>
      <div style={ss.rowLbl}>{label}</div>
      <div style={ss.segWrap}>
        {options.map(o => (
          <button key={o} style={{...ss.segBtn, ...(value === o ? ss.segBtnOn : {})}}
                  onClick={() => onChange(o)}>{o}</button>
        ))}
      </div>
    </div>
  );
}
function RowToggle({ label, sub, on, onChange }) {
  return (
    <div style={ss.row}>
      <div style={{minWidth:0}}>
        <div style={ss.rowLbl}>{label}</div>
        {sub && <div style={ss.rowSub}>{sub}</div>}
      </div>
      <ToggleSwitch on={on} onChange={onChange}/>
    </div>
  );
}
function RowStatic({ label, value }) {
  return (
    <div style={ss.row}>
      <div style={ss.rowLbl}>{label}</div>
      <div style={ss.rowVal}>{value}</div>
    </div>
  );
}
function RowAction({ label, sub, action, onAction, tone }) {
  return (
    <div style={ss.row}>
      <div style={{minWidth:0}}>
        <div style={ss.rowLbl}>{label}</div>
        <div style={ss.rowSub}>{sub}</div>
      </div>
      <button style={{...ss.rowAction, color: tone==='danger' ? 'var(--kc-miss)' : 'var(--kc-fg)', boxShadow:`inset 0 0 0 1.5px ${tone==='danger' ? 'var(--kc-miss)' : 'var(--kc-stone-200)'}`}} onClick={onAction}>{action}</button>
    </div>
  );
}
function ToggleSwitch({ on, onChange }) {
  const [local, setLocal] = useSetState(!!on);
  const live = onChange ? on : local;
  const flip = () => onChange ? onChange(!on) : setLocal(v => !v);
  return (
    <button style={{...ss.switch, background: live ? 'var(--kc-meadow-500)' : 'var(--kc-stone-200)'}} onClick={flip}>
      <span style={{...ss.switchKnob, transform: live ? 'translateX(20px)' : 'translateX(0)'}}/>
    </button>
  );
}

function Status({ label, value, tone, mono }) {
  return (
    <div style={ss.statusRow}>
      <span style={ss.rowSub}>{label}</span>
      <span style={{
        ...(mono ? ss.statusValMono : ss.statusVal),
        color: tone === 'ok' ? 'var(--kc-meadow-700)' : 'var(--kc-fg)',
      }}>
        {tone === 'ok' && <span style={ss.statusDot}/>}
        {value}
      </span>
    </div>
  );
}

// ---------- Reset modal (small) ----------
function ResetModal({ onClose }) {
  const [step, setStep] = useSetState('warn');
  const [type, setType] = useSetState('');
  const can = type === 'ZURÜCKSETZEN';
  return (
    <div style={ss.backdrop} onClick={onClose}>
      <div style={ss.modal} onClick={e => e.stopPropagation()}>
        {step === 'warn' && (
          <>
            <div style={ss.modalHead}>
              <div>
                <div style={ss.eyebrow}>Warnung</div>
                <h2 style={ss.modalTitle}>Sessions zurücksetzen?</h2>
              </div>
              <button style={ss.closeBtn} onClick={onClose}>×</button>
            </div>
            <div style={ss.modalBody}>
              <p style={ss.warnText}>
                Alle <b>612 gespeicherten Sessions</b> werden unwiderruflich gelöscht. Statistik, ELO-Verlauf und Streaks gehen verloren. Profil & Anmeldungen bleiben.
              </p>
              <div style={ss.field}>
                <span style={ss.rowSub}>Tippe <b>ZURÜCKSETZEN</b> zum Bestätigen</span>
                <input type="text" style={ss.input} value={type} onChange={e => setType(e.target.value.toUpperCase())} autoFocus/>
              </div>
            </div>
            <div style={ss.modalActions}>
              <SecondaryBtn tone="ghost" onClick={onClose}>Abbrechen</SecondaryBtn>
              <button onClick={() => can && setStep('done')}
                      style={{...ss.dangerBtn, opacity: can ? 1 : 0.4, pointerEvents: can ? 'auto' : 'none'}}>
                Endgültig zurücksetzen
              </button>
            </div>
          </>
        )}
        {step === 'done' && (
          <div style={ss.doneBody}>
            <div style={ss.doneIcon}>✓</div>
            <div style={ss.modalTitle}>Zurückgesetzt</div>
            <p style={ss.warnText}>Sessions wurden gelöscht. Du startest jetzt mit einem leeren Verlauf.</p>
            <PrimaryBtn onClick={onClose}>Fertig</PrimaryBtn>
          </div>
        )}
      </div>
    </div>
  );
}

// ---------- Styles ----------
const ss = {
  split: { display:'grid', gridTemplateColumns:'260px 1fr 300px', gap:18, padding:'24px 32px 32px', minHeight:0 },
  aside: { display:'flex', flexDirection:'column', gap:14, minWidth:0 },
  main:  { display:'flex', flexDirection:'column', gap:14, minWidth:0 },
  rightCol: { display:'flex', flexDirection:'column', gap:14, minWidth:0 },

  userCard: { display:'flex', alignItems:'center', gap:10, padding:'10px 12px', borderRadius:14, background:'var(--kc-bg-raised)', boxShadow:'var(--kc-shadow-1)' },
  userAvatar: { width:40, height:40, borderRadius:999, background:'var(--kc-meadow-600)', color:'#fff', display:'grid', placeItems:'center', fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:13 },
  userName: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' },
  userSub: { fontFamily:'var(--kc-font-mono)', fontSize:10, color:'var(--kc-fg-muted)', letterSpacing:'0.04em' },
  userEdit: { padding:'6px 10px', borderRadius:8, border:0, background:'var(--kc-bg-sunken)', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:12, cursor:'pointer' },

  nav: { display:'flex', flexDirection:'column', gap:2, padding:'6px 0' },
  navItem: { display:'flex', alignItems:'center', gap:12, padding:'10px 12px', minHeight:44, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:14, cursor:'pointer', borderRadius:10, width:'100%', textAlign:'left' },
  navItemActive: { background:'var(--kc-bg-sunken)', color:'var(--kc-fg)', boxShadow:'inset 2px 0 0 0 var(--kc-meadow-500)' },
  navDot: { width:6, height:6, borderRadius:999, background:'var(--kc-meadow-500)' },

  sectionHead: { display:'flex', justifyContent:'space-between', alignItems:'flex-end', marginBottom:18, paddingBottom:14, borderBottom:'1px solid var(--kc-line)' },
  eyebrow: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  sectionTitle: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:30, letterSpacing:'-0.025em', margin:'4px 0 0', fontVariationSettings:'"opsz" 72' },

  cont: { display:'flex', flexDirection:'column' },
  row: { display:'flex', justifyContent:'space-between', alignItems:'center', gap:18, padding:'16px 0', borderTop:'1px solid var(--kc-line)' },
  rowLbl: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14, letterSpacing:'-0.01em' },
  rowSub: { fontSize:12, color:'var(--kc-fg-muted)', marginTop:2 },
  rowVal: { fontFamily:'var(--kc-font-mono)', fontSize:13, color:'var(--kc-fg)' },
  rowAction: { padding:'8px 14px', borderRadius:8, border:0, background:'transparent', color:'var(--kc-fg)', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-200)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:12, cursor:'pointer' },

  segWrap: { display:'flex', background:'var(--kc-bg-sunken)', borderRadius:999, padding:3, gap:0 },
  segBtn: { minHeight:34, padding:'0 14px', border:0, borderRadius:999, background:'transparent', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer' },
  segBtnOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  switch: { width:48, height:28, borderRadius:999, border:0, padding:2, cursor:'pointer', display:'flex', alignItems:'center', transition:'background 120ms ease', flexShrink:0 },
  switchKnob: { display:'block', width:24, height:24, borderRadius:999, background:'#fff', boxShadow:'0 1px 3px rgba(0,0,0,0.2)', transition:'transform 120ms ease' },

  aboutHero: { display:'flex', alignItems:'center', gap:14, padding:'4px 0 14px', borderBottom:'1px solid var(--kc-line)' },
  aboutName: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:22, letterSpacing:'-0.02em', fontVariationSettings:'"opsz" 36' },
  aboutSub: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)' },

  // Quick / status
  quickList: { display:'flex', flexDirection:'column', gap:4, marginTop:8 },
  quick: { display:'flex', alignItems:'center', gap:10, padding:'10px 10px', border:0, background:'transparent', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer', borderRadius:8 },

  statusList: { display:'flex', flexDirection:'column', marginTop:8 },
  statusRow: { display:'flex', justifyContent:'space-between', alignItems:'baseline', padding:'8px 0', borderTop:'1px solid var(--kc-line)' },
  statusVal: { fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, display:'inline-flex', alignItems:'center', gap:6 },
  statusValMono: { fontFamily:'var(--kc-font-mono)', fontSize:12, color:'var(--kc-fg)' },
  statusDot: { width:6, height:6, borderRadius:999, background:'currentColor' },

  footer: { padding:'16px 4px', fontSize:11, color:'var(--kc-fg-muted)', textAlign:'center', lineHeight:1.7 },

  // Modal
  backdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.55)', display:'grid', placeItems:'center', zIndex:30 },
  modal: { width:480, maxWidth:'90vw', background:'var(--kc-bg-raised)', borderRadius:18, boxShadow:'var(--kc-shadow-3)', display:'flex', flexDirection:'column' },
  modalHead: { display:'flex', alignItems:'flex-start', justifyContent:'space-between', padding:'20px 24px 8px' },
  modalTitle: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:22, letterSpacing:'-0.02em', margin:'2px 0 0', fontVariationSettings:'"opsz" 72' },
  closeBtn: { width:36, height:36, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontSize:24, cursor:'pointer', lineHeight:1 },
  modalBody: { padding:'4px 24px 20px' },
  modalActions: { display:'flex', justifyContent:'flex-end', gap:10, padding:'16px 24px 22px', borderTop:'1px solid var(--kc-line)' },
  warnText: { color:'var(--kc-fg-muted)', fontSize:14, lineHeight:1.5, margin:'8px 0 14px' },
  field: { display:'flex', flexDirection:'column', gap:6 },
  input: { minHeight:44, padding:'0 14px', borderRadius:10, border:'1.5px solid var(--kc-stone-200)', background:'var(--kc-bg)', color:'var(--kc-fg)', fontFamily:'var(--kc-font-mono)', fontSize:14, outline:'none', letterSpacing:'0.04em' },
  dangerBtn: { display:'inline-flex', alignItems:'center', gap:8, borderRadius:12, border:0, background:'var(--kc-miss)', color:'#fff', fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14, height:44, padding:'0 18px', cursor:'pointer' },
  doneBody: { padding:'32px 24px', textAlign:'center', display:'flex', flexDirection:'column', alignItems:'center', gap:14 },
  doneIcon: { width:64, height:64, borderRadius:'50%', background:'var(--kc-meadow-500)', color:'#fff', display:'grid', placeItems:'center', fontSize:32, fontWeight:800 },
};

window.SettingsScreen = SettingsScreen;
