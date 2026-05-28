/* global React, DIcon, TopBar, PrimaryBtn, SecondaryBtn, Card, CardHeader */
// =====================================================================
// Profile — User-Edit Screen für Desktop.
//   Linke Spalte (360): Avatar, Identity, Spielerdaten
//   Rechte Spalte (flex): Anmeldung (Mail/OAuth), Verein, Sicherheit
//   Modals: Passwort-Änderung, E-Mail-Änderung
// =====================================================================

const { useState: useProfState } = React;

function ProfileScreen({ onRoute }) {
  const [name, setName]     = useProfState('Marc Brosius');
  const [email, setEmail]   = useProfState('marc@brosius.ch');
  const [hand, setHand]     = useProfState('rechts');
  const [stamm, setStamm]   = useProfState('beides');
  const [club, setClub]     = useProfState('Brosi\u2019s Kubb · BKC');
  const [providers, setProviders] = useProfState({ google:false, apple:true });
  const [pwOpen, setPwOpen] = useProfState(false);
  const [emailOpen, setEmailOpen] = useProfState(false);

  const toggleProvider = k => setProviders(p => ({ ...p, [k]: !p[k] }));

  return (
    <>
      <TopBar
        eyebrow="Account · Profil"
        title="Dein Profil"
        subtitle="Anzeigename, Spielergewohnheiten und Anmeldungs-Verknüpfungen — sichtbar für deinen Club."
        right={<>
          <SecondaryBtn tone="ghost" onClick={() => onRoute && onRoute('dashboard')}>Verwerfen</SecondaryBtn>
          <PrimaryBtn onClick={() => onRoute && onRoute('dashboard')}>Speichern</PrimaryBtn>
        </>}
      />

      <div style={pf.body}>
        <div style={pf.split}>
          {/* LEFT — identity */}
          <aside style={pf.aside}>
            <Card padding={22}>
              <div style={pf.avatarBlock}>
                <div style={pf.avatarRing}>
                  <div style={pf.avatar}>M</div>
                </div>
                <div style={pf.avatarMeta}>
                  <div style={pf.avatarName}>{name}</div>
                  <div style={pf.avatarSub}>Mitglied seit Apr 2024 · 1283 ELO</div>
                </div>
                <button style={pf.avatarEdit}>Foto ändern</button>
              </div>
            </Card>

            <Card padding={22}>
              <CardHeader eyebrow="Spielerdaten" title="Identität"/>
              <Field label="Anzeigename">
                <input style={pf.input} value={name} onChange={e => setName(e.target.value)}/>
              </Field>
              <Field label="Wurfhand">
                <Seg value={hand} options={['links','rechts','beidhändig']} onChange={setHand}/>
              </Field>
              <Field label="Stamm-Distanz">
                <Seg value={stamm} options={['4 m','8 m','beides']} onChange={setStamm}/>
              </Field>
            </Card>

            <Card padding={22}>
              <CardHeader eyebrow="Verein" title="Mitgliedschaft"/>
              <Field label="Klub">
                <input style={pf.input} value={club} onChange={e => setClub(e.target.value)}/>
              </Field>
              <div style={pf.rowStatic}>
                <span style={pf.rowLbl}>Mitglied seit</span>
                <span style={pf.rowVal}>Apr 2024</span>
              </div>
              <div style={pf.rowStatic}>
                <span style={pf.rowLbl}>Liga-Punkte</span>
                <span style={pf.rowVal}>12 · Saison '25</span>
              </div>
            </Card>
          </aside>

          {/* RIGHT — auth & security */}
          <main style={pf.main}>
            <Card padding={22}>
              <CardHeader eyebrow="Anmeldung" title="E-Mail & Verknüpfungen"
                          right={<SecondaryBtn size="sm" tone="ghost" onClick={() => setEmailOpen(true)} icon={<DIcon.Chevron/>}>E-Mail ändern</SecondaryBtn>}/>
              <div style={pf.authList}>
                <AuthRow
                  icon={<MailIcon/>}
                  label="E-Mail"
                  value={email}
                  status="primär"
                  action="ändern"
                  onAction={() => setEmailOpen(true)}/>
                <AuthRow
                  icon={<GoogleIcon/>}
                  label="Google"
                  value={providers.google ? 'm.brosius@gmail.com · verknüpft' : 'noch nicht verknüpft'}
                  status={providers.google ? 'aktiv' : null}
                  action={providers.google ? 'trennen' : 'verknüpfen'}
                  onAction={() => toggleProvider('google')}/>
                <AuthRow
                  icon={<AppleIcon/>}
                  label="Apple"
                  value={providers.apple ? 'mb@privaterelay.appleid.com · verknüpft' : 'noch nicht verknüpft'}
                  status={providers.apple ? 'aktiv' : null}
                  action={providers.apple ? 'trennen' : 'verknüpfen'}
                  onAction={() => toggleProvider('apple')}/>
              </div>
            </Card>

            <Card padding={22}>
              <CardHeader eyebrow="Sicherheit" title="Passwort & Sessions"/>
              <div style={pf.secList}>
                <SecRow
                  icon={<LockIcon/>}
                  label="Passwort"
                  sub="zuletzt geändert vor 3 Monaten · 12 Zeichen"
                  action="Passwort ändern"
                  onAction={() => setPwOpen(true)}/>
                <SecRow
                  icon={<DIcon.Bell/>}
                  label="Zwei-Faktor (2FA)"
                  sub="nicht aktiviert · empfohlen für Liga-Spieler"
                  action="Einrichten"
                  onAction={() => {}}/>
                <SecRow
                  icon={<DIcon.Users/>}
                  label="Aktive Sessions"
                  sub="3 Geräte · iPhone (jetzt), MacBook, iPad"
                  action="Alle abmelden"
                  tone="danger"
                  onAction={() => {}}/>
              </div>
            </Card>

            <Card padding={22}>
              <CardHeader eyebrow="Sichtbarkeit" title="Was sieht dein Club?"/>
              <div style={pf.visGrid}>
                <Vis label="Trefferquote in Liga sichtbar" defaultOn/>
                <Vis label="Trainings-Sessions teilen" defaultOn/>
                <Vis label="ELO öffentlich anzeigen"/>
                <Vis label="Standort beim Spiel"/>
              </div>
            </Card>

            <Card padding={22}>
              <CardHeader eyebrow="Konto" title="Gefahrenzone"/>
              <p style={pf.dangerNote}>
                Profil löschen entfernt alle Sessions, ELO-Verlauf und Liga-Anmeldungen. Daten können <b>nicht</b> wiederhergestellt werden.
              </p>
              <SecondaryBtn tone="ink">Profil unwiderruflich löschen</SecondaryBtn>
            </Card>
          </main>
        </div>
      </div>

      {pwOpen     && <PasswordModal onClose={() => setPwOpen(false)}/>}
      {emailOpen  && <EmailModal email={email} setEmail={setEmail} onClose={() => setEmailOpen(false)}/>}
    </>
  );
}

// ---------- Sub Rows ----------
function Field({ label, children }) {
  return (
    <div style={pf.field}>
      <span style={pf.rowLbl}>{label}</span>
      <div style={pf.fieldVal}>{children}</div>
    </div>
  );
}
function Seg({ value, options, onChange }) {
  return (
    <div style={pf.seg}>
      {options.map(o => (
        <button key={o} style={{...pf.segBtn, ...(value === o ? pf.segBtnOn : {})}}
                onClick={() => onChange(o)}>{o}</button>
      ))}
    </div>
  );
}
function AuthRow({ icon, label, value, status, action, onAction }) {
  return (
    <div style={pf.authRow}>
      <span style={pf.authIcon}>{icon}</span>
      <div style={pf.authText}>
        <div style={pf.authLbl}>{label}</div>
        <div style={pf.authVal}>{value}</div>
      </div>
      {status && <span style={pf.authStatus}>{status}</span>}
      <button style={pf.authAction} onClick={onAction}>{action}</button>
    </div>
  );
}
function SecRow({ icon, label, sub, action, onAction, tone }) {
  return (
    <div style={pf.secRow}>
      <span style={pf.authIcon}>{icon}</span>
      <div style={pf.authText}>
        <div style={pf.authLbl}>{label}</div>
        <div style={pf.authVal}>{sub}</div>
      </div>
      <button style={{...pf.authAction, color: tone === 'danger' ? 'var(--kc-miss)' : 'var(--kc-fg)', boxShadow: `inset 0 0 0 1.5px ${tone === 'danger' ? 'var(--kc-miss)' : 'var(--kc-stone-200)'}`}} onClick={onAction}>{action}</button>
    </div>
  );
}
function Vis({ label, defaultOn }) {
  const [on, setOn] = useProfState(!!defaultOn);
  return (
    <button style={{...pf.visRow, ...(on ? pf.visRowOn : {})}} onClick={() => setOn(v => !v)}>
      <span style={{...pf.visBox, ...(on ? pf.visBoxOn : {})}}>{on ? '✓' : ''}</span>
      <span style={pf.visLbl}>{label}</span>
    </button>
  );
}

// ---------- Modals ----------
function ModalBackdrop({ children, onClose }) {
  return (
    <div style={pf.backdrop} onClick={onClose}>
      <div style={pf.modal} onClick={e => e.stopPropagation()}>{children}</div>
    </div>
  );
}

function EmailModal({ email, setEmail, onClose }) {
  const [next, setNext] = useProfState(email);
  const [pw, setPw] = useProfState('');
  const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(next);
  const ok = valid && next !== email && pw.length >= 4;
  return (
    <ModalBackdrop onClose={onClose}>
      <div style={pf.modalHead}>
        <div>
          <div style={pf.modalEyebrow}>Account</div>
          <h2 style={pf.modalTitle}>E-Mail ändern</h2>
        </div>
        <button style={pf.closeBtn} onClick={onClose} aria-label="Schliessen">×</button>
      </div>
      <div style={pf.modalBody}>
        <Field label="Aktuelle E-Mail"><div style={pf.staticEmail}>{email}</div></Field>
        <Field label="Neue E-Mail">
          <input type="email" style={pf.input} value={next} onChange={e => setNext(e.target.value)} autoFocus/>
          {next.length > 0 && !valid && <div style={pf.hintError}>ungültige Adresse</div>}
        </Field>
        <Field label="Aktuelles Passwort">
          <input type="password" style={pf.input} value={pw} onChange={e => setPw(e.target.value)}/>
        </Field>
        <p style={pf.modalNote}>Du erhältst eine Bestätigung an die neue Adresse. Bis dahin bleibt die alte aktiv.</p>
      </div>
      <div style={pf.modalActions}>
        <SecondaryBtn tone="ghost" onClick={onClose}>Abbrechen</SecondaryBtn>
        <PrimaryBtn onClick={() => { if (ok) { setEmail(next); onClose(); } }}>E-Mail ändern</PrimaryBtn>
      </div>
    </ModalBackdrop>
  );
}

function PasswordModal({ onClose }) {
  const [cur, setCur] = useProfState('');
  const [n1,  setN1]  = useProfState('');
  const [n2,  setN2]  = useProfState('');
  const [show, setShow] = useProfState(false);
  const lengthOK = n1.length >= 8;
  const matches  = n1.length > 0 && n1 === n2;
  const differs  = cur.length > 0 && n1.length > 0 && cur !== n1;
  const ok = cur.length >= 4 && lengthOK && matches && differs;
  return (
    <ModalBackdrop onClose={onClose}>
      <div style={pf.modalHead}>
        <div>
          <div style={pf.modalEyebrow}>Sicherheit</div>
          <h2 style={pf.modalTitle}>Passwort ändern</h2>
        </div>
        <button style={pf.closeBtn} onClick={onClose} aria-label="Schliessen">×</button>
      </div>
      <div style={pf.modalBody}>
        <Field label="Aktuelles Passwort">
          <input type={show ? 'text' : 'password'} style={pf.input} value={cur} onChange={e => setCur(e.target.value)}/>
        </Field>
        <Field label="Neues Passwort">
          <input type={show ? 'text' : 'password'} style={pf.input} value={n1} onChange={e => setN1(e.target.value)}/>
          {n1.length > 0 && !lengthOK && <div style={pf.hintError}>mindestens 8 Zeichen</div>}
        </Field>
        <Field label="Bestätigen">
          <input type={show ? 'text' : 'password'} style={pf.input} value={n2} onChange={e => setN2(e.target.value)}/>
          {n2.length > 0 && !matches && <div style={pf.hintError}>stimmt nicht überein</div>}
        </Field>
        <button style={pf.showRow} onClick={() => setShow(s => !s)}>
          <span style={pf.checkBoxMini}>{show ? '✓' : ''}</span>
          <span>Passwörter anzeigen</span>
        </button>
      </div>
      <div style={pf.modalActions}>
        <SecondaryBtn tone="ghost" onClick={onClose}>Abbrechen</SecondaryBtn>
        <PrimaryBtn onClick={() => ok && onClose()}>Passwort ändern</PrimaryBtn>
      </div>
    </ModalBackdrop>
  );
}

// ---------- Inline brand icons ----------
function MailIcon()   { return <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/></svg>; }
function LockIcon()   { return <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>; }
function GoogleIcon() { return <svg viewBox="0 0 24 24" width="20" height="20"><path fill="#EA4335" d="M12 10.2v3.7h5.2c-.2 1.4-1.6 4-5.2 4a5.9 5.9 0 1 1 0-11.8c1.9 0 3.1.8 3.8 1.4l2.6-2.5C16.7 3.4 14.6 2.5 12 2.5a9.5 9.5 0 1 0 0 19c5.5 0 9.1-3.9 9.1-9.3 0-.6-.1-1.2-.2-1.7z"/></svg>; }
function AppleIcon()  { return <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor"><path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.5-.2-2.8.8-3.6.8-.7 0-1.9-.8-3.1-.8-1.6 0-3.1.9-3.9 2.4-1.7 2.9-.4 7.1 1.2 9.5.8 1.1 1.7 2.4 2.9 2.4 1.2 0 1.6-.7 3.1-.7 1.4 0 1.8.7 3.1.7 1.3 0 2.1-1.1 2.9-2.3.9-1.3 1.3-2.6 1.3-2.6-.1 0-2.5-1-2.5-3.7zM14.2 6c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1.1.1 2.1-.5 2.7-1.3z"/></svg>; }

// ---------- Styles ----------
const pf = {
  body: { padding:'24px 40px 48px', maxWidth:1280 },
  split: { display:'grid', gridTemplateColumns:'360px 1fr', gap:20 },
  aside: { display:'flex', flexDirection:'column', gap:16 },
  main:  { display:'flex', flexDirection:'column', gap:16 },

  avatarBlock: { display:'flex', flexDirection:'column', alignItems:'center', gap:10 },
  avatarRing: { padding:5, borderRadius:'50%', background:'linear-gradient(135deg, var(--kc-meadow-500), var(--kc-wood-500))' },
  avatar: { width:112, height:112, borderRadius:'50%', background:'var(--kc-meadow-600)', color:'var(--kc-on-primary)', display:'grid', placeItems:'center', fontFamily:'var(--kc-font-display)', fontWeight:800, fontSize:48, fontVariationSettings:'"opsz" 96' },
  avatarMeta: { textAlign:'center', marginTop:4 },
  avatarName: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:22, letterSpacing:'-0.02em', fontVariationSettings:'"opsz" 36' },
  avatarSub: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.04em', marginTop:2 },
  avatarEdit: { background:'transparent', border:0, color:'var(--kc-meadow-700)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer', textDecoration:'underline', textUnderlineOffset:3 },

  field: { display:'flex', flexDirection:'column', gap:6, padding:'10px 0', borderTop:'1px solid var(--kc-line)' },
  fieldVal: { display:'flex' },
  rowLbl: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  rowVal: { fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:14 },
  rowStatic: { display:'flex', justifyContent:'space-between', alignItems:'baseline', padding:'10px 0', borderTop:'1px solid var(--kc-line)' },

  input: { minHeight:44, padding:'0 14px', borderRadius:10, border:'1.5px solid var(--kc-stone-200)', background:'var(--kc-bg)', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontSize:15, outline:'none', flex:1, width:'100%', boxSizing:'border-box' },

  seg: { display:'flex', background:'var(--kc-bg-sunken)', borderRadius:999, padding:3, gap:0, flex:1 },
  segBtn: { flex:1, minHeight:36, padding:'0 12px', border:0, borderRadius:999, background:'transparent', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer' },
  segBtnOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  // Auth rows
  authList: { display:'flex', flexDirection:'column', gap:8, marginTop:8 },
  authRow: { display:'grid', gridTemplateColumns:'40px 1fr auto auto', gap:14, alignItems:'center', padding:'12px 14px', borderRadius:12, background:'var(--kc-bg-sunken)' },
  authIcon: { width:40, height:40, borderRadius:10, background:'var(--kc-bg-raised)', display:'grid', placeItems:'center', color:'var(--kc-fg-muted)' },
  authText: { minWidth:0 },
  authLbl: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14 },
  authVal: { fontSize:12, color:'var(--kc-fg-muted)', overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap', maxWidth:380 },
  authStatus: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-meadow-700)', background:'var(--kc-meadow-100)', padding:'4px 8px', borderRadius:4 },
  authAction: { padding:'8px 14px', borderRadius:8, border:0, background:'var(--kc-bg-raised)', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-200)', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:12, cursor:'pointer' },

  secList: { display:'flex', flexDirection:'column', gap:8, marginTop:8 },
  secRow: { display:'grid', gridTemplateColumns:'40px 1fr auto', gap:14, alignItems:'center', padding:'12px 14px', borderRadius:12, background:'var(--kc-bg-sunken)' },

  visGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:8, marginTop:8 },
  visRow: { display:'flex', alignItems:'center', gap:10, padding:'10px 12px', borderRadius:10, background:'var(--kc-bg-sunken)', border:0, cursor:'pointer', color:'var(--kc-fg)', textAlign:'left', boxShadow:'inset 0 0 0 1.5px transparent' },
  visRowOn: { boxShadow:'inset 0 0 0 1.5px var(--kc-meadow-500)' },
  visBox: { width:20, height:20, borderRadius:5, background:'transparent', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-300)', display:'grid', placeItems:'center', fontSize:12, fontWeight:800, color:'#fff' },
  visBoxOn: { background:'var(--kc-meadow-500)', boxShadow:'none' },
  visLbl: { fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13 },

  dangerNote: { color:'var(--kc-fg-muted)', fontSize:13, lineHeight:1.5, margin:'8px 0 12px' },

  // Modals
  backdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.55)', display:'grid', placeItems:'center', zIndex:30 },
  modal: { width:480, maxWidth:'90vw', background:'var(--kc-bg-raised)', borderRadius:18, boxShadow:'var(--kc-shadow-3)', display:'flex', flexDirection:'column' },
  modalHead: { display:'flex', alignItems:'flex-start', justifyContent:'space-between', padding:'20px 24px 8px' },
  modalEyebrow: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  modalTitle: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:24, letterSpacing:'-0.02em', margin:'2px 0 0', fontVariationSettings:'"opsz" 72' },
  closeBtn: { width:36, height:36, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontSize:24, cursor:'pointer', lineHeight:1 },
  modalBody: { padding:'4px 24px 20px', display:'flex', flexDirection:'column', gap:0 },
  modalNote: { fontSize:12, color:'var(--kc-fg-muted)', margin:'10px 0 0' },
  modalActions: { display:'flex', justifyContent:'flex-end', gap:10, padding:'16px 24px 22px', borderTop:'1px solid var(--kc-line)' },
  staticEmail: { fontFamily:'var(--kc-font-mono)', fontWeight:600, fontSize:14, color:'var(--kc-fg-muted)', padding:'10px 0' },
  hintError: { color:'var(--kc-miss)', fontSize:12, fontFamily:'var(--kc-font-mono)', marginTop:6 },
  showRow: { display:'inline-flex', alignItems:'center', gap:10, padding:'10px 0', background:'transparent', border:0, color:'var(--kc-fg)', cursor:'pointer', fontSize:13, marginTop:4 },
  checkBoxMini: { width:20, height:20, borderRadius:5, border:'1.5px solid var(--kc-stone-200)', display:'inline-grid', placeItems:'center', fontSize:12, color:'var(--kc-meadow-700)', fontWeight:800 },
};

window.ProfileScreen = ProfileScreen;
