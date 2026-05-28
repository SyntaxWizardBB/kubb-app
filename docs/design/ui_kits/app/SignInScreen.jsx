/* global React, BK */
const { Icon } = BK;

// =====================================================================
// Screen: Sign-In Hub
//
// Cold-start entry. Three primary surfaces:
//   - Google OAuth (white surface, multi-color G)
//   - Apple OAuth  (black surface, white glyph)  — iOS only in Flutter,
//     always shown in the mocks so reviewers see the full hub
//   - Anonymous    (chalky outline button, Lock icon)
//
// Layout: Wordmark + Kubb-Mark vignette top, inset card with buttons
// bottom-centered, "EST. 2025 · DACH" tagline at the very bottom.
// Mirrors the inset-card spacing language from HomeScreen.jsx.
// =====================================================================
function SignInScreen({ onPickGoogle, onPickApple, onPickAnonymous, onPickRestore, offline = false, error = false }) {
  return (
    <div style={s.screen}>
      <div style={s.scroll}>
        <div style={s.brandBlock}>
          <div style={s.markFrame} aria-hidden="true">
            <KubbMark size={56}/>
          </div>
          <div style={s.eyebrow}>Kubb Club</div>
          <div style={s.wordmark}>Servus, Kubber.</div>
          <div style={s.tagline}>Trainings-Tracker für die Wiese</div>
        </div>

        <div style={s.cardWrap}>
          {offline && (
            <div style={s.offlineBanner} role="status">
              <span style={s.offlineDot}/>
              <span>Du bist offline. Provider-Anmeldung wird nicht funktionieren — Anonym-Account legt offline an.</span>
            </div>
          )}

          {error && (
            <div style={s.errorBanner} role="alert">
              <Icon.Close/>
              <span>Anmeldung fehlgeschlagen. Versuch es nochmals.</span>
            </div>
          )}

          <button style={s.googleBtn} onClick={onPickGoogle} disabled={offline}>
            <span style={s.googleGlyph}>G</span>
            <span style={s.googleLbl}>Mit Google anmelden</span>
          </button>

          <button style={s.appleBtn} onClick={onPickApple} disabled={offline}>
            <span style={s.appleGlyph}><Icon.Apple/></span>
            <span style={s.appleLbl}>Mit Apple anmelden</span>
          </button>

          <div style={s.divider}>
            <span style={s.dividerLine}/>
            <span style={s.dividerLbl}>oder</span>
            <span style={s.dividerLine}/>
          </div>

          <button style={s.anonBtn} onClick={onPickAnonymous}>
            <span style={s.anonGlyph}><Icon.Lock/></span>
            <span style={s.anonLbl}>Ohne Konto starten (anonym)</span>
          </button>

          <button style={s.restoreBtn} onClick={onPickRestore}>
            Konto auf neuem Gerät wiederherstellen
          </button>
        </div>

        <div style={s.foot}>EST. 2025 · DACH</div>
      </div>
    </div>
  );
}

// =====================================================================
// KubbMark — two-block wordless logo (wood block + meadow block + ground
// shadow). Matches `_KubbLogoPainter` in lib/features/auth so the mock
// and the Flutter screen render visually identical marks.
// =====================================================================
function KubbMark({ size = 64 }) {
  return (
    <svg viewBox="0 0 64 64" width={size} height={size} aria-hidden="true">
      <rect x="10" y="20" width="18" height="34" rx="2" fill="var(--bk-wood-500)"/>
      <rect x="10" y="20" width="18" height="6"  rx="2" fill="var(--bk-wood-700, #6b4f25)"/>
      <rect x="36" y="10" width="18" height="44" rx="2" fill="var(--bk-meadow-500)"/>
      <rect x="36" y="10" width="18" height="6"  rx="2" fill="var(--bk-meadow-700, #2f5b2c)"/>
      <rect x="6"  y="56" width="52" height="3"  rx="1.5" fill="var(--bk-stone-700, #4a443a)"/>
    </svg>
  );
}

const s = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflow:'hidden' },
  scroll: { flex:1, overflowY:'auto', padding:'54px 16px 24px', display:'flex', flexDirection:'column' },

  brandBlock: { display:'flex', flexDirection:'column', alignItems:'center', padding:'20px 0 28px', gap:4 },
  markFrame: { width:88, height:88, borderRadius:20, background:'var(--bk-bg-raised)', display:'grid', placeItems:'center', boxShadow:'var(--bk-shadow-1)', marginBottom:14 },
  eyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  wordmark: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:30, letterSpacing:'-0.02em', marginTop:2 },
  tagline: { fontSize:14, color:'var(--bk-fg-muted)', marginTop:2 },

  cardWrap: { background:'var(--bk-bg-raised)', borderRadius:20, padding:'18px 16px 16px', marginTop:'auto', display:'flex', flexDirection:'column', gap:12, boxShadow:'inset 0 0 0 1px var(--bk-line)' },

  offlineBanner: { display:'flex', gap:10, alignItems:'flex-start', padding:'10px 12px', borderRadius:12, background:'var(--bk-wood-50, #fbf3e2)', border:'1px solid var(--bk-wood-200, #e0c98f)', color:'var(--bk-fg)', fontSize:12, lineHeight:1.4 },
  offlineDot: { width:8, height:8, borderRadius:'50%', background:'var(--bk-wood-500)', marginTop:5, flexShrink:0 },

  errorBanner: { display:'flex', gap:10, alignItems:'center', padding:'10px 12px', borderRadius:12, background:'#FBE4E0', border:'1.5px solid var(--bk-miss)', color:'var(--bk-miss)', fontSize:13, fontWeight:600 },

  googleBtn: { display:'flex', alignItems:'center', justifyContent:'center', gap:10, minHeight:54, padding:'0 18px', borderRadius:14, border:'1.5px solid var(--bk-line-strong)', background:'#FFFFFF', color:'#1F1F1F', cursor:'pointer', fontFamily:'var(--bk-font-body)', fontSize:16, fontWeight:600 },
  googleGlyph: { width:22, height:22, borderRadius:'50%', display:'grid', placeItems:'center', color:'#FFFFFF', fontWeight:900, fontSize:13, background:'conic-gradient(from 0deg, #EA4335, #FBBC05, #34A853, #4285F4, #EA4335)' },
  googleLbl: {},

  appleBtn: { display:'flex', alignItems:'center', justifyContent:'center', gap:10, minHeight:54, padding:'0 18px', borderRadius:14, border:0, background:'#000000', color:'#FFFFFF', cursor:'pointer', fontFamily:'var(--bk-font-body)', fontSize:16, fontWeight:600 },
  appleGlyph: { display:'grid', placeItems:'center', color:'#FFFFFF' },
  appleLbl: {},

  divider: { display:'flex', alignItems:'center', gap:10, padding:'4px 4px' },
  dividerLine: { flex:1, height:1, background:'var(--bk-line)' },
  dividerLbl: { fontSize:11, fontWeight:600, letterSpacing:'0.12em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },

  anonBtn: { display:'flex', alignItems:'center', justifyContent:'center', gap:10, minHeight:54, padding:'0 18px', borderRadius:14, border:'1.5px solid var(--bk-line)', background:'var(--bk-bg-sunken)', color:'var(--bk-fg)', cursor:'pointer', fontFamily:'var(--bk-font-body)', fontSize:16, fontWeight:600 },
  anonGlyph: { display:'grid', placeItems:'center', color:'var(--bk-fg)' },
  anonLbl: {},

  restoreBtn: { background:'transparent', border:0, color:'var(--bk-meadow-600)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:14, padding:'8px 4px', cursor:'pointer', textDecoration:'underline', textUnderlineOffset:3 },

  foot: { textAlign:'center', fontFamily:'var(--bk-font-mono)', fontSize:10, letterSpacing:'0.3em', textTransform:'uppercase', color:'var(--bk-fg-muted)', paddingTop:18 },
};

window.SignInScreen = SignInScreen;
