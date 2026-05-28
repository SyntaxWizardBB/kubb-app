/* global React, BK */
const { useState } = React;
const { Icon, AppBar } = BK;

// =====================================================================
// Screen: Anonymous Signup (Step 1 — Nickname + Avatar-Preview)
//
// Pre-mnemonic step that converts visitors into low-friction users.
// Three blocks:
//   1. Wizard header (back + close, eyebrow "Anonym anlegen").
//   2. Avatar-initial preview that updates live as the user types.
//      Same gradient ring + meadow disc used on ProfileScreen, so the
//      cue "this is YOU" carries through to the rest of the app.
//   3. Disclaimer block — "Anonyme Sessions können via Recovery-Phrase
//      gerettet werden". Sets expectation before the mnemonic step
//      takes over.
//   4. "Loslegen"-CTA — full-width primary button.
// =====================================================================
function AnonymousSignupScreen({ onBack, onClose, onContinue }) {
  const [name, setName] = useState('');
  const trimmed = name.trim();
  const valid = trimmed.length >= 3 && trimmed.length <= 30 && /^[A-Za-z0-9_-]+$/.test(trimmed);
  const initial = trimmed.length > 0 ? trimmed.charAt(0).toUpperCase() : '?';

  let err = null;
  if (trimmed.length > 0 && trimmed.length < 3) err = 'Mindestens 3 Zeichen.';
  else if (trimmed.length > 30) err = 'Maximal 30 Zeichen.';
  else if (trimmed.length > 0 && !/^[A-Za-z0-9_-]+$/.test(trimmed)) err = "Nur Buchstaben, Zahlen, '-' und '_'.";

  return (
    <div style={a.screen}>
      <AppBar eyebrow="Anonym anlegen" title="Wähle einen Spielnamen" onBack={onBack}
              right={onClose ? <button style={a.iconBtn} onClick={onClose} aria-label="Schliessen"><Icon.Close/></button> : null}/>

      <div style={a.scroll}>
        <div style={a.avatarBlock}>
          <div style={{...a.avatarRing, ...(trimmed.length === 0 ? a.avatarRingMuted : {})}}>
            <div style={a.avatar}>{initial}</div>
          </div>
          <div style={a.avatarCaption}>
            {trimmed.length > 0 ? trimmed : 'Dein Avatar-Buchstabe'}
          </div>
        </div>

        <div style={a.fieldBlock}>
          <label style={a.fieldLbl}>Spielname</label>
          <input
            style={{...a.input, ...(err ? a.inputErr : {})}}
            value={name}
            onChange={e => setName(e.target.value)}
            placeholder="z. B. wiese-marc"
            maxLength={30}
            autoFocus/>
          {err
            ? <span style={a.errHint}>{err}</span>
            : <span style={a.helpHint}>Andere Spielerinnen sehen diesen Namen</span>}
        </div>

        <div style={a.disclaimer}>
          <div style={a.disclaimerHead}>
            <Icon.Lock/>
            <span style={a.disclaimerTitle}>Sichere deinen Account</span>
          </div>
          <div style={a.disclaimerBody}>
            Anonyme Sessions können via <b>Recovery-Phrase</b> auf ein neues Gerät übertragen werden. Schreib die 12 Wörter sicher auf — ohne sie ist dein Account weg.
          </div>
        </div>

        <div style={a.spacer}/>

        <button
          style={{...a.cta, opacity: valid ? 1 : 0.4, pointerEvents: valid ? 'auto' : 'none'}}
          onClick={() => valid && onContinue && onContinue(trimmed)}>
          Loslegen
        </button>
      </div>
    </div>
  );
}

const a = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflow:'hidden' },
  scroll: { flex:1, overflowY:'auto', padding:'4px 20px 24px', display:'flex', flexDirection:'column' },
  iconBtn: { width:44, height:44, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },

  avatarBlock: { display:'flex', flexDirection:'column', alignItems:'center', gap:10, padding:'18px 0 22px' },
  avatarRing: { padding:5, borderRadius:'50%', background:'linear-gradient(135deg, var(--bk-meadow-500), var(--bk-wood-500))' },
  avatarRingMuted: { background:'var(--bk-line)' },
  avatar: { width:96, height:96, borderRadius:'50%', background:'var(--bk-meadow-600)', color:'var(--bk-on-primary)', display:'grid', placeItems:'center', fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:42, letterSpacing:'-0.02em' },
  avatarCaption: { fontSize:12, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },

  fieldBlock: { display:'flex', flexDirection:'column', gap:6, paddingTop:4 },
  fieldLbl: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  input: { minHeight:48, padding:'0 14px', borderRadius:12, border:'1.5px solid var(--bk-line-strong)', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', fontSize:16, fontWeight:600, outline:'none', boxSizing:'border-box', width:'100%' },
  inputErr: { borderColor:'var(--bk-miss)' },
  helpHint: { fontSize:12, color:'var(--bk-fg-muted)', paddingTop:2 },
  errHint: { fontSize:12, color:'var(--bk-miss)', fontWeight:600, paddingTop:2 },

  disclaimer: { marginTop:18, padding:'14px 14px', borderRadius:14, background:'#FBF2D6', border:'1.5px solid #D4AE3B', display:'flex', flexDirection:'column', gap:8, color:'#5A4500' },
  disclaimerHead: { display:'flex', alignItems:'center', gap:8, color:'#5A4500' },
  disclaimerTitle: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:14, letterSpacing:'-0.01em' },
  disclaimerBody: { fontSize:13, lineHeight:1.45, color:'var(--bk-fg)' },

  spacer: { flex:1, minHeight:24 },

  cta: { minHeight:56, padding:'0 22px', borderRadius:16, border:0, background:'var(--bk-meadow-600)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer', marginTop:12, boxShadow:'var(--bk-shadow-1)' },
};

window.AnonymousSignupScreen = AnonymousSignupScreen;
