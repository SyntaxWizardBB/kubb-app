/* global React, BK */
const { useState } = React;
const { Icon, AppBar } = BK;

// =====================================================================
// Screen: Profil — User-Edit
//   - Stamm-Distanz: 4 m / 8 m / beides (Segmented)
//   - Passwort ändern (eigener Flow / Sheet)
// =====================================================================
function ProfileScreen({ onBack }) {
  const [name, setName] = useState('Marc Brosius');
  const [email, setEmail] = useState('marc@brosius.ch');
  const [hand, setHand] = useState('rechts');
  const [stamm, setStamm] = useState('beides');
  const [pwOpen, setPwOpen] = useState(false);
  const [emailOpen, setEmailOpen] = useState(false);
  // Linked auth providers (in real app: from backend)
  const [providers, setProviders] = useState({ google:false, apple:true });
  const toggleProvider = (k) => setProviders(p => ({ ...p, [k]: !p[k] }));

  return (
    <div style={p.screen}>
      <AppBar eyebrow="Account" title="Profil" onBack={onBack}/>

      <div style={p.avatarBlock}>
        <div style={p.avatarRing}>
          <div style={p.avatar}>{name.charAt(0)}</div>
        </div>
        <button style={p.avatarEdit}>Foto ändern</button>
      </div>

      <div style={p.section}>Spielerdaten</div>
      <div style={p.group}>
        <Field label="Anzeigename">
          <input style={p.input} value={name} onChange={e => setName(e.target.value)}/>
        </Field>
        <Field label="Wurfhand">
          <Seg value={hand} options={['links','rechts','beidhändig']} onChange={setHand}/>
        </Field>
        <Field label="Stamm-Distanz">
          <Seg value={stamm} options={['4 m','8 m','beides']} onChange={setStamm}/>
        </Field>
      </div>

      <div style={p.section}>Anmeldung</div>
      <div style={p.group}>
        <button style={p.navRow} onClick={() => setEmailOpen(true)}>
          <span style={p.navIcon}><Icon.Mail/></span>
          <span style={p.navText}>
            <span style={p.navLbl}>E-Mail</span>
            <span style={p.navSub}>{email}</span>
          </span>
          <span style={p.chev}><Icon.ChevronRight/></span>
        </button>
        <ProviderRow icon={<Icon.Google/>} label="Google"
                     connected={providers.google}
                     onClick={() => toggleProvider('google')}/>
        <ProviderRow icon={<Icon.Apple/>} label="Apple"
                     connected={providers.apple}
                     onClick={() => toggleProvider('apple')}
                     last/>
      </div>

      <div style={p.section}>Verein</div>
      <div style={p.group}>
        <Field label="Klub">
          <span style={p.staticVal}>Brosi's Kubb</span>
        </Field>
        <Field label="Mitglied seit">
          <span style={p.staticVal}>Apr 2024</span>
        </Field>
      </div>

      <div style={p.section}>Sicherheit</div>
      <div style={p.group}>
        <button style={p.navRow} onClick={() => setPwOpen(true)}>
          <span style={p.navIcon}><Icon.Lock/></span>
          <span style={p.navText}>
            <span style={p.navLbl}>Passwort ändern</span>
            <span style={p.navSub}>zuletzt geändert vor 3 Monaten</span>
          </span>
          <span style={p.chev}><Icon.ChevronRight/></span>
        </button>
      </div>

      <button style={p.saveBtn} onClick={onBack}>Speichern</button>

      <div style={{height:24}}/>

      {pwOpen && <PasswordChangeSheet onClose={() => setPwOpen(false)}/>}
      {emailOpen && <EmailChangeSheet email={email} setEmail={setEmail} onClose={() => setEmailOpen(false)}/>}
    </div>
  );
}

// =====================================================================
// ProviderRow — Google / Apple verknüpfen oder trennen
// =====================================================================
function ProviderRow({ icon, label, connected, onClick, last }) {
  return (
    <button style={{...p.navRow, ...(last ? { borderBottom:0 } : {})}} onClick={onClick}>
      <span style={p.navIcon}>{icon}</span>
      <span style={p.navText}>
        <span style={p.navLbl}>{label}</span>
        <span style={p.navSub}>{connected ? 'verknüpft' : 'nicht verknüpft'}</span>
      </span>
      <span style={connected ? p.providerOff : p.providerOn}>
        {connected ? 'Trennen' : 'Verknüpfen'}
      </span>
    </button>
  );
}

// =====================================================================
// Sheet: E-Mail ändern
// =====================================================================
function EmailChangeSheet({ email, setEmail, onClose }) {
  const [step, setStep] = useState('form');
  const [next, setNext] = useState(email);
  const [pw, setPw] = useState('');
  const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(next);
  const canSubmit = valid && next !== email && pw.length >= 4;
  const submit = () => { if (!canSubmit) return; setEmail(next); setStep('done'); };
  return (
    <div style={p.sheetBackdrop} onClick={onClose}>
      <div style={p.sheet} onClick={e => e.stopPropagation()}>
        <div style={p.sheetGrabber}/>
        <div style={p.sheetHead}>
          <div>
            <div style={p.topEyebrow}>Account</div>
            <h2 style={p.sheetTitle}>E-Mail ändern</h2>
          </div>
          <button style={p.iconBtn} onClick={onClose} aria-label="Schliessen"><Icon.Close/></button>
        </div>

        {step === 'form' && (
          <>
            <label style={p.pwField}>
              <span style={p.rowLbl}>Aktuelle E-Mail</span>
              <span style={{...p.staticVal, padding:'12px 4px'}}>{email}</span>
            </label>
            <label style={p.pwField}>
              <span style={p.rowLbl}>Neue E-Mail</span>
              <input type="email" style={p.input} value={next} onChange={e => setNext(e.target.value)} autoComplete="off"/>
              {next.length > 0 && !valid && <span style={p.hint}>ungültige Adresse</span>}
            </label>
            <label style={p.pwField}>
              <span style={p.rowLbl}>Aktuelles Passwort</span>
              <input type="password" style={p.input} value={pw} onChange={e => setPw(e.target.value)} autoComplete="off"/>
            </label>
            <div style={{...p.hint, color:'var(--bk-fg-muted)', fontSize:12, padding:'4px 0'}}>
              Du erhältst eine Bestätigung an die neue Adresse.
            </div>
            <div style={p.sheetActions}>
              <button style={p.cancelBtn} onClick={onClose}>Abbrechen</button>
              <button style={{...p.primaryBtn, opacity: canSubmit ? 1 : 0.4, pointerEvents: canSubmit ? 'auto' : 'none'}} onClick={submit}>
                E-Mail ändern
              </button>
            </div>
            <div style={{height:8}}/>
          </>
        )}

        {step === 'done' && (
          <div style={p.doneBlock}>
            <div style={p.doneIcon}><Icon.Check/></div>
            <div style={p.doneTitle}>Bestätigung gesendet</div>
            <div style={p.doneSub}>Öffne die E-Mail an <b>{next}</b> und bestätige den Wechsel.</div>
            <button style={p.primaryBtn} onClick={onClose}>Fertig</button>
            <div style={{height:8}}/>
          </div>
        )}
      </div>
    </div>
  );
}

// =====================================================================
// Sheet: Passwort ändern
// =====================================================================
function PasswordChangeSheet({ onClose }) {
  const [step, setStep] = useState('form');     // form | done
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [show, setShow] = useState(false);

  const minLen = 8;
  const lengthOK = next.length >= minLen;
  const matches = next.length > 0 && next === confirm;
  const differs = current.length > 0 && next.length > 0 && current !== next;
  const canSubmit = current.length >= 4 && lengthOK && matches && differs;

  const submit = () => {
    if (!canSubmit) return;
    setStep('done');
  };

  return (
    <div style={p.sheetBackdrop} onClick={onClose}>
      <div style={p.sheet} onClick={e => e.stopPropagation()}>
        <div style={p.sheetGrabber}/>
        <div style={p.sheetHead}>
          <div>
            <div style={p.topEyebrow}>Sicherheit</div>
            <h2 style={p.sheetTitle}>Passwort ändern</h2>
          </div>
          <button style={p.iconBtn} onClick={onClose} aria-label="Schliessen"><Icon.Close/></button>
        </div>

        {step === 'form' && (
          <>
            <PwField label="Aktuelles Passwort" value={current} setValue={setCurrent} show={show}/>
            <PwField label="Neues Passwort"     value={next}    setValue={setNext}    show={show}
                     hint={lengthOK ? null : `mindestens ${minLen} Zeichen`}/>
            <PwField label="Neues Passwort bestätigen" value={confirm} setValue={setConfirm} show={show}
                     hint={confirm.length > 0 && !matches ? 'stimmt nicht überein' : null}/>

            <button style={p.showRow} onClick={() => setShow(s => !s)}>
              <span style={p.checkbox}>{show ? '✓' : ''}</span>
              <span>Passwörter anzeigen</span>
            </button>

            <div style={p.sheetActions}>
              <button style={p.cancelBtn} onClick={onClose}>Abbrechen</button>
              <button style={{...p.primaryBtn, opacity: canSubmit ? 1 : 0.4, pointerEvents: canSubmit ? 'auto' : 'none'}}
                      onClick={submit}>
                Passwort ändern
              </button>
            </div>
            <div style={{height:8}}/>
          </>
        )}

        {step === 'done' && (
          <div style={p.doneBlock}>
            <div style={p.doneIcon}><Icon.Check/></div>
            <div style={p.doneTitle}>Passwort aktualisiert</div>
            <div style={p.doneSub}>Du wurdest auf allen anderen Geräten abgemeldet.</div>
            <button style={p.primaryBtn} onClick={onClose}>Fertig</button>
            <div style={{height:8}}/>
          </div>
        )}
      </div>
    </div>
  );
}

function PwField({ label, value, setValue, show, hint }) {
  return (
    <label style={p.pwField}>
      <span style={p.rowLbl}>{label}</span>
      <input type={show ? 'text' : 'password'}
             value={value}
             onChange={e => setValue(e.target.value)}
             style={p.input}
             autoComplete="off"/>
      {hint && <span style={p.hint}>{hint}</span>}
    </label>
  );
}

function Field({ label, children }) {
  return (
    <div style={p.row}>
      <span style={p.rowLbl}>{label}</span>
      <div style={p.rowVal}>{children}</div>
    </div>
  );
}

function Seg({ value, options, onChange }) {
  return (
    <div style={p.seg}>
      {options.map(o => (
        <button key={o} style={{...p.segBtn, ...(value===o ? p.segBtnOn : {})}}
                onClick={() => onChange(o)}>{o}</button>
      ))}
    </div>
  );
}

const p = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflowY:'auto', padding:'0 0 32px' },

  avatarBlock: { display:'flex', flexDirection:'column', alignItems:'center', gap:8, padding:'10px 0 18px' },
  avatarRing: { padding:4, borderRadius:'50%', background:'linear-gradient(135deg, var(--bk-meadow-500), var(--bk-wood-500))' },
  avatar: { width:88, height:88, borderRadius:'50%', background:'var(--bk-meadow-600)', color:'var(--bk-on-primary)', display:'grid', placeItems:'center', fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:36 },
  avatarEdit: { background:'transparent', border:0, color:'var(--bk-meadow-600)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:13, cursor:'pointer', textDecoration:'underline', textUnderlineOffset:3 },

  section: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', padding:'14px 18px 8px' },
  group: { background:'var(--bk-bg-raised)', borderRadius:14, margin:'0 16px', padding:'4px 14px' },
  row: { display:'flex', flexDirection:'column', gap:6, padding:'10px 0', borderBottom:'1px solid var(--bk-line)' },
  rowLbl: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  rowVal: { display:'flex' },
  staticVal: { fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:15 },

  navRow: { display:'flex', alignItems:'center', gap:14, padding:'10px 0', minHeight:60, width:'100%', background:'transparent', border:0, borderBottom:'1px solid var(--bk-line)', textAlign:'left', cursor:'pointer', color:'inherit' },
  navIcon: { width:36, height:36, display:'grid', placeItems:'center', background:'var(--bk-bg-sunken)', borderRadius:10, color:'var(--bk-fg-muted)', flexShrink:0 },
  navText: { display:'flex', flexDirection:'column', gap:2, flex:1, minWidth:0 },
  navLbl: { fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:15 },
  navSub: { fontSize:12, color:'var(--bk-fg-muted)', overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' },
  chev: { color:'var(--bk-fg-muted)' },

  providerOn: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:12, letterSpacing:'0.04em', textTransform:'uppercase', color:'var(--bk-meadow-600)', padding:'6px 12px', background:'var(--bk-meadow-100)', borderRadius:999 },
  providerOff: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:12, letterSpacing:'0.04em', textTransform:'uppercase', color:'var(--bk-fg-muted)', padding:'6px 12px', background:'var(--bk-bg-sunken)', borderRadius:999 },

  input: { minHeight:44, padding:'0 12px', borderRadius:10, border:'1.5px solid var(--bk-line-strong)', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', fontSize:15, outline:'none', flex:1, width:'100%', boxSizing:'border-box' },

  seg: { display:'flex', background:'var(--bk-bg-sunken)', borderRadius:999, padding:3, gap:0 },
  segBtn: { flex:1, minHeight:36, padding:'0 10px', border:0, borderRadius:999, background:'transparent', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:13, cursor:'pointer' },
  segBtnOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)' },

  saveBtn: { margin:'18px 16px 0', minHeight:54, borderRadius:14, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer' },

  // Password sheet
  sheetBackdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.55)', display:'flex', alignItems:'flex-end', zIndex:30 },
  sheet: { width:'100%', maxHeight:'92%', overflowY:'auto', background:'var(--bk-bg)', borderTopLeftRadius:24, borderTopRightRadius:24, padding:'10px 18px 32px', display:'flex', flexDirection:'column', gap:10 },
  sheetGrabber: { width:36, height:4, background:'var(--bk-stone-200)', borderRadius:999, alignSelf:'center', marginBottom:6 },
  sheetHead: { display:'flex', alignItems:'flex-start', justifyContent:'space-between', marginBottom:4 },
  sheetTitle: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:22, margin:0, letterSpacing:'-0.02em' },

  pwField: { display:'flex', flexDirection:'column', gap:6, paddingTop:8 },
  hint: { fontSize:12, color:'var(--bk-miss)' },

  showRow: { display:'flex', alignItems:'center', gap:10, padding:'10px 4px', background:'transparent', border:0, color:'var(--bk-fg)', cursor:'pointer', fontSize:13, marginTop:2 },
  checkbox: { width:20, height:20, borderRadius:6, border:'1.5px solid var(--bk-line-strong)', display:'inline-grid', placeItems:'center', fontSize:13, color:'var(--bk-meadow-600)', fontWeight:800 },

  sheetActions: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:10, marginTop:6 },
  cancelBtn: { minHeight:54, borderRadius:14, border:0, background:'var(--bk-bg-sunken)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:16, cursor:'pointer' },
  primaryBtn: { minHeight:54, borderRadius:14, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer' },

  doneBlock: { display:'flex', flexDirection:'column', alignItems:'center', gap:10, padding:'18px 8px 6px' },
  doneIcon: { width:64, height:64, borderRadius:'50%', background:'var(--bk-meadow-500)', color:'#fff', display:'grid', placeItems:'center' },
  doneTitle: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:22, letterSpacing:'-0.02em' },
  doneSub: { fontSize:14, color:'var(--bk-fg-muted)', textAlign:'center', marginBottom:8 },
};

window.ProfileScreen = ProfileScreen;
