/* global React, BK */
const { useState } = React;
const { Icon } = BK;

// =====================================================================
// Screen: Home
//   - Hamburger -> App-Settings Modal (Sprache, Vibration, etc.)
//   - Profil-Icon -> Profil/Edit-Page
//   - Tournier-Kachel + News-Kachel
//   - FAB "Training" (Material 3 position: 16/16) -> sheet
// =====================================================================
function HomeScreen({ onPick, onOpenAppSettings, onOpenProfile }) {
  const [trainOpen, setTrainOpen] = useState(false);

  return (
    <div style={h.screen}>
      <div style={h.scroll}>
        {/* Top bar */}
        <header style={h.topbar}>
          <button style={h.iconBtn} onClick={onOpenAppSettings} aria-label="Menü"><Icon.Menu/></button>
          <img src="../../assets/logo-mark.svg" width="34" height="34" alt="Kubb Club"/>
          <button style={h.iconBtn} onClick={onOpenProfile} aria-label="Profil"><Icon.Profile/></button>
        </header>

        <div style={h.greetBlock}>
          <div style={h.eyebrow}>Kubb Club</div>
          <div style={h.greeting}>Servus, Marc.</div>
        </div>

        {/* Tournier (primary tile) */}
        <button style={h.tournierCard} onClick={() => onPick('tournier')}>
          <div style={h.tournierLeft}>
            <div style={h.tournierEyebrow}>Tournier</div>
            <div style={h.tournierName}>Match-Modus</div>
            <div style={h.tournierSub}>Voll­spiel · 6 Stöcke pro Halbsatz</div>
          </div>
          <div style={h.tournierIcon} aria-hidden="true">
            <Icon.Cup/>
          </div>
        </button>

        {/* News tile */}
        <a style={h.newsCard} href="https://kubbtour.ch" target="_blank" rel="noopener noreferrer">
          <div style={h.newsLeft}>
            <div style={h.newsEyebrow}>News · Kubbtour.ch</div>
            <div style={h.newsTitle}>Saison 2025 — Termine sind raus</div>
            <div style={h.newsSub}>tippen für alle Turniere & Anmeldung</div>
          </div>
          <div style={h.newsArrow} aria-hidden="true"><Icon.ChevronRight/></div>
        </a>

        <div style={h.section}>Zuletzt</div>
        <div style={h.recentList}>
          <RecentRow tag="Sniper" rate="64 %" sub="8.0 m · 36 Würfe · gestern"/>
          <RecentRow tag="Fin" rate="✓ 5/6" sub="7/3 · sauber · gestern"/>
          <RecentRow tag="Fin" rate="✗ 6/6" sub="5/5 · Strafkubb · vor 2 Tagen" tone="bad"/>
        </div>
      </div>

      {/* FAB — Material 3: 16/16 from screen edge */}
      <button style={h.fab} onClick={() => setTrainOpen(true)} aria-label="Neue Trainings-Session starten">
        <Icon.Plus2/>
        <span>Training</span>
      </button>

      {trainOpen && (
        <TrainingSheet
          onPick={(mode) => { setTrainOpen(false); onPick(mode); }}
          onClose={() => setTrainOpen(false)}
        />
      )}
    </div>
  );
}

function RecentRow({ tag, rate, sub, tone }) {
  return (
    <div style={h.recent}>
      <span style={h.recentTag}>{tag}</span>
      <span style={{...h.recentRate, color: tone === 'bad' ? 'var(--bk-miss)' : 'var(--bk-fg)'}}>{rate}</span>
      <span style={h.recentSub}>{sub}</span>
    </div>
  );
}

function TrainingSheet({ onPick, onClose }) {
  return (
    <div style={h.sheetBackdrop} onClick={onClose}>
      <div style={h.sheet} onClick={e => e.stopPropagation()}>
        <div style={h.sheetGrabber}/>
        <div style={h.sheetHead}>
          <div>
            <div style={h.eyebrow}>Neue Session</div>
            <h2 style={h.sheetTitle}>Welcher Modus?</h2>
          </div>
          <button style={h.iconBtn} onClick={onClose} aria-label="Schliessen"><Icon.Close/></button>
        </div>

        <button style={{...h.modeCard, background:'var(--bk-meadow-500)', color:'var(--bk-on-primary)'}}
                onClick={() => onPick('8m')}>
          <div style={{textAlign:'left'}}>
            <div style={h.modeName}>Sniper-Training</div>
            <div style={h.modeSub}>Trefferquote · Konstanz</div>
          </div>
          <div style={h.modeNum}>8 m</div>
        </button>

        <button style={{...h.modeCard, background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)'}}
                onClick={() => onPick('finisseur')}>
          <div style={{textAlign:'left'}}>
            <div style={h.modeName}>Finisseur</div>
            <div style={h.modeSub}>Match-Endspiel · 6 Stöcke</div>
          </div>
          <div style={h.modeNum}>7/3</div>
        </button>
      </div>
    </div>
  );
}

const h = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', position:'relative', overflow:'hidden' },
  scroll: { flex:1, overflowY:'auto', padding:'54px 16px 96px' },
  topbar: { display:'flex', alignItems:'center', justifyContent:'space-between', marginLeft:-4, marginRight:-4, paddingBottom:4 },
  iconBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },

  greetBlock: { padding:'8px 0 16px' },
  eyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  greeting: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:28, letterSpacing:'-0.02em', marginTop:2 },

  tournierCard: { display:'flex', justifyContent:'space-between', alignItems:'center', minHeight:120, border:0, padding:'18px 18px', borderRadius:20, marginBottom:12, textAlign:'left', cursor:'pointer', background:'var(--bk-wood-500)', color:'var(--bk-chalk-50)', boxShadow:'var(--bk-shadow-1)', width:'100%' },
  tournierLeft: { display:'flex', flexDirection:'column', gap:2, minWidth:0, flex:1 },
  tournierEyebrow: { fontSize:11, fontWeight:700, letterSpacing:'0.08em', textTransform:'uppercase', opacity:0.85 },
  tournierName: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:28, letterSpacing:'-0.02em', lineHeight:1 },
  tournierSub: { fontSize:13, opacity:0.85, marginTop:4 },
  tournierIcon: { width:64, height:64, borderRadius:16, background:'rgba(255,255,255,0.18)', display:'grid', placeItems:'center' },

  newsCard: { display:'flex', justifyContent:'space-between', alignItems:'center', minHeight:72, padding:'12px 14px', borderRadius:16, marginBottom:6, textDecoration:'none', cursor:'pointer', background:'var(--bk-bg-raised)', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 1px var(--bk-line)' },
  newsLeft: { display:'flex', flexDirection:'column', gap:1, minWidth:0, flex:1 },
  newsEyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-meadow-600)' },
  newsTitle: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:15, letterSpacing:'-0.01em', lineHeight:1.2 },
  newsSub: { fontSize:12, color:'var(--bk-fg-muted)', marginTop:2 },
  newsArrow: { color:'var(--bk-fg-muted)', flexShrink:0, marginLeft:8 },

  section: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', marginTop:14, marginBottom:8 },

  recentList: { background:'var(--bk-bg-raised)', borderRadius:14, padding:'4px 12px' },
  recent: { display:'grid', gridTemplateColumns:'56px 80px 1fr', alignItems:'baseline', gap:8, padding:'10px 0', borderBottom:'1px solid var(--bk-line)' },
  recentTag: { fontFamily:'var(--bk-font-mono)', fontSize:11, fontWeight:700, color:'var(--bk-fg-muted)', letterSpacing:'0.06em', textTransform:'uppercase' },
  recentRate: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:18, fontVariantNumeric:'tabular-nums' },
  recentSub: { fontSize:13, color:'var(--bk-fg-muted)' },

  // FAB — Material 3: 16/16 from container edge
  fab: { position:'absolute', right:24, bottom:24, minHeight:56, padding:'0 22px 0 18px', display:'flex', alignItems:'center', gap:10, borderRadius:16, border:0, background:'var(--bk-meadow-600)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer', boxShadow:'var(--bk-shadow-2)' },

  // sheet
  sheetBackdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.45)', display:'flex', alignItems:'flex-end', zIndex:10 },
  sheet: { width:'100%', background:'var(--bk-bg-raised)', borderTopLeftRadius:24, borderTopRightRadius:24, padding:'10px 18px 32px', display:'flex', flexDirection:'column', gap:10 },
  sheetGrabber: { width:36, height:4, background:'var(--bk-stone-200)', borderRadius:999, alignSelf:'center', marginBottom:6 },
  sheetHead: { display:'flex', alignItems:'flex-start', justifyContent:'space-between', marginBottom:4 },
  sheetTitle: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:22, margin:0, letterSpacing:'-0.02em' },

  modeCard: { display:'flex', justifyContent:'space-between', alignItems:'center', minHeight:96, border:0, padding:'14px 18px', borderRadius:18, textAlign:'left', cursor:'pointer', boxShadow:'var(--bk-shadow-1)' },
  modeName: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:24, letterSpacing:'-0.02em', lineHeight:1.1 },
  modeSub: { fontSize:13, opacity:0.85, marginTop:2 },
  modeNum: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:36, letterSpacing:'-0.03em', fontVariantNumeric:'tabular-nums' },
};

window.HomeScreen = HomeScreen;
