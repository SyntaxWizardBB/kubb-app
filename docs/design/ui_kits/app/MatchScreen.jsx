/* global React, BK */
const { useState } = React;
const { Icon, AppBar } = BK;

// =====================================================================
// Screen: Match — Live Match-Modus auf Mobile.
//   Pendant zu desktop/MatchScreen.jsx, aber Single-Column für Phone.
//   Tabs: Lobby (pre-game) | Live (in-game) | Result (post-game)
// =====================================================================
function MatchScreen({ onBack, initialStage }) {
  const [stage, setStage] = useState(initialStage || 'live');   // lobby | live | result
  return (
    <div style={m.screen}>
      <AppBar
        eyebrow={stage === 'lobby' ? 'Match · Lobby' : stage === 'live' ? 'Match · LIVE' : 'Match · Ergebnis'}
        title={stage === 'lobby' ? 'Marc & Vinz' : stage === 'result' ? 'Sieg · 3:2' : 'Halbsatz 4 / 5'}
        onBack={onBack}
        right={
          <button style={m.stageBtn} onClick={() => setStage(stage === 'lobby' ? 'live' : stage === 'live' ? 'result' : 'lobby')} aria-label="Stage wechseln">
            <Icon.ChevronRight/>
          </button>
        }
      />

      <div style={m.stageTabs}>
        {[['lobby','Lobby'], ['live','Live'], ['result','Ergebnis']].map(([k, lbl]) => (
          <button key={k}
                  style={{...m.stageTab, ...(stage === k ? m.stageTabOn : {})}}
                  onClick={() => setStage(k)}>{lbl}</button>
        ))}
      </div>

      <div style={m.body}>
        {stage === 'lobby'  && <Lobby  onStart={() => setStage('live')}/>}
        {stage === 'live'   && <Live   onFinish={() => setStage('result')}/>}
        {stage === 'result' && <Result onRestart={() => setStage('lobby')}/>}
      </div>
    </div>
  );
}

// =====================================================================
// LOBBY
// =====================================================================
function Lobby({ onStart }) {
  return (
    <>
      <div style={m.lobbyHero}>
        <Side initials="MV" name="Marc & Vinz" elo={1283} form={['W','W','L','W']} you/>
        <div style={m.vsCol}>
          <div style={m.vsBig}>vs.</div>
          <div style={m.vsClock}>20:15</div>
          <div style={m.vsMeta}>Court 2 · BKC Friday</div>
        </div>
        <Side initials="UA" name="BKC United A" elo={1305} form={['W','L','W','W']}/>
      </div>

      <div style={m.section}>Direkter Vergleich</div>
      <div style={m.h2hList}>
        {[
          { date:'KW 17', score:'1:3', won:false },
          { date:'KW 11', score:'3:2', won:true  },
          { date:'KW 04', score:'2:3', won:true  },
        ].map((h, i) => (
          <div key={i} style={m.h2hRow}>
            <span style={m.h2hDate}>{h.date}</span>
            <span style={m.h2hTeams}>Marc & Vinz vs. United A</span>
            <span style={m.h2hScore}>{h.score}</span>
            <span style={{...m.h2hTag, background: h.won ? 'var(--bk-meadow-100)' : 'var(--bk-stone-100)', color: h.won ? 'var(--bk-meadow-700)' : 'var(--bk-fg-muted)'}}>{h.won ? 'Sieg' : 'N'}</span>
          </div>
        ))}
      </div>

      <div style={m.section}>Match-Setup</div>
      <div style={m.setupList}>
        <SetupRow label="Format" value="Best of 5 · 6 Stöcke"/>
        <SetupRow label="Heli-Tracking" value="ja" tone="ok"/>
        <SetupRow label="Strafkubb" value="schwedisch"/>
        <SetupRow label="Court" value="Court 2 · Bern Stadion"/>
      </div>

      <button style={m.startBtn} onClick={onStart}>
        <span style={m.startDot}/> Match starten
      </button>
    </>
  );
}

function Side({ initials, name, elo, form, you }) {
  return (
    <div style={m.side}>
      <div style={{...m.sideAvatar, background: you ? 'var(--bk-meadow-600)' : 'var(--bk-stone-900)'}}>{initials}</div>
      <div style={m.sideName}>{name}</div>
      <div style={m.sideElo}>{elo} ELO</div>
      <div style={m.formRow}>
        {form.map((f, i) => (
          <span key={i} style={{...m.formCell, background: f === 'W' ? 'var(--bk-meadow-500)' : 'var(--bk-stone-200)', color: f === 'W' ? '#fff' : 'var(--bk-fg-muted)'}}>{f}</span>
        ))}
      </div>
    </div>
  );
}

function SetupRow({ label, value, tone }) {
  return (
    <div style={m.setupRow}>
      <span style={m.setupLbl}>{label}</span>
      <span style={{...m.setupVal, color: tone === 'ok' ? 'var(--bk-meadow-700)' : 'var(--bk-fg)'}}>{value}</span>
    </div>
  );
}

// =====================================================================
// LIVE
// =====================================================================
function Live({ onFinish }) {
  return (
    <>
      {/* Score strip */}
      <div style={m.scoreStrip}>
        <div style={m.scoreSide}>
          <div style={{...m.scoreAvatar, background:'var(--bk-meadow-600)'}}>MV</div>
          <div style={m.scoreName}>Marc & Vinz</div>
        </div>
        <div style={m.scoreNumWrap}>
          <span style={{...m.scoreNum, color:'var(--bk-meadow-500)'}}>2</span>
          <span style={m.scoreColon}>:</span>
          <span style={m.scoreNum}>1</span>
        </div>
        <div style={m.scoreSide}>
          <div style={{...m.scoreAvatar, background:'var(--bk-stone-900)'}}>UA</div>
          <div style={m.scoreName}>United A</div>
        </div>
      </div>
      <div style={m.scoreMeta}>
        <span>Halbsatz 4 / 5</span>
        <span style={m.liveDot}>● LIVE · 4:12</span>
      </div>

      {/* Action pad — 4 large tap targets */}
      <div style={m.actionGrid}>
        <Action label="Treffer" tone="hit"/>
        <Action label="Miss"    tone="miss"/>
        <Action label="Heli"    tone="heli"/>
        <Action label="Strafe"  tone="penalty"/>
      </div>

      {/* Mini-counters */}
      <div style={m.miniCounters}>
        <Mini label="Stock" value="4 / 6"/>
        <Mini label="Treff" value="18"  tone="hit"/>
        <Mini label="Heli"  value="4"   tone="heli"/>
        <Mini label="Straf" value="0"   tone="penalty" muted/>
      </div>

      <div style={m.section}>Per-Wurf Log · Halbsatz 4</div>
      <ul style={m.log}>
        {[
          { idx:22, p:'Marc B.',  type:'hit',     note:'Reihenkubb · 7 m', t:'4:12' },
          { idx:21, p:'Anna V.',  type:'miss',    note:'zu lang',           t:'3:58' },
          { idx:20, p:'Vinz L.',  type:'heli',    note:'Heli · 8 m',        t:'3:41' },
          { idx:19, p:'Jonas T.', type:'hit',     note:'Mittelkubb · 6 m',  t:'3:24' },
        ].map((l, i) => (
          <li key={i} style={{...m.logRow, ...(i === 0 ? m.logRowLatest : {})}}>
            <span style={m.logIdx}>#{l.idx}</span>
            <span style={{...m.logTag, ...TAG[l.type]}}>{TAG[l.type].label}</span>
            <span style={m.logText}>{l.p}<br/><small style={{color:'var(--bk-fg-muted)'}}>{l.note}</small></span>
            <span style={m.logTime}>{l.t}</span>
          </li>
        ))}
      </ul>

      <div style={m.endRow}>
        <button style={m.endBtnGhost}>
          <Icon.Back/> Letzten Wurf zurück
        </button>
        <button style={m.endBtn} onClick={onFinish}>Halbsatz beenden</button>
      </div>
    </>
  );
}

const TAG = {
  hit:     { background:'var(--bk-meadow-100)', color:'var(--bk-meadow-700)', label:'TREF' },
  miss:    { background:'var(--bk-stone-100)',  color:'var(--bk-fg-muted)',   label:'MISS' },
  heli:    { background:'var(--bk-wood-100)',   color:'var(--bk-wood-600)',   label:'HELI' },
  penalty: { background:'#fae2e6',              color:'var(--bk-penalty)',    label:'STRAF' },
};

function Action({ label, tone }) {
  const tones = {
    hit:     { background:'var(--bk-hit)',     color:'#fff' },
    miss:    { background:'var(--bk-miss)',    color:'#fff' },
    heli:    { background:'var(--bk-heli)',    color:'var(--bk-stone-900)' },
    penalty: { background:'var(--bk-penalty)', color:'#fff' },
  }[tone];
  return (
    <button style={{...m.actionBtn, ...tones}}>
      <span style={m.actionLbl}>{label}</span>
      <span style={m.actionPlus}>+</span>
    </button>
  );
}

function Mini({ label, value, tone, muted }) {
  const color =
    tone === 'hit'     ? 'var(--bk-hit)' :
    tone === 'miss'    ? 'var(--bk-miss)' :
    tone === 'heli'    ? 'var(--bk-heli)' :
    tone === 'penalty' ? 'var(--bk-penalty)' :
    'var(--bk-fg)';
  return (
    <div style={{...m.mini, opacity: muted ? 0.5 : 1}}>
      <span style={m.miniLbl}>{label}</span>
      <span style={{...m.miniVal, color}}>{value}</span>
    </div>
  );
}

// =====================================================================
// RESULT
// =====================================================================
function Result({ onRestart }) {
  return (
    <>
      <div style={m.resultHero}>
        <div style={m.resultEyebrow}>Sieg · Best of 5</div>
        <div style={m.resultBigRow}>
          <span style={{...m.resultBig, color:'var(--bk-meadow-500)'}}>3</span>
          <span style={m.resultColon}>:</span>
          <span style={{...m.resultBig, color:'var(--bk-fg-muted)'}}>2</span>
        </div>
        <div style={m.resultTeams}>Marc & Vinz vs. BKC United A</div>
        <div style={m.resultMeta}>9:42 min · 28 Würfe · ELO +18</div>
      </div>

      <div style={m.section}>Halbsatz-Verlauf</div>
      <div style={m.setRow}>
        {[
          { n:1, h:6, a:4, won:true },
          { n:2, h:5, a:6, won:false },
          { n:3, h:6, a:3, won:true },
          { n:4, h:4, a:6, won:false },
          { n:5, h:6, a:5, won:true },
        ].map(s => (
          <div key={s.n} style={{...m.setCard, ...(s.won ? m.setCardW : m.setCardL)}}>
            <div style={m.setLbl}>HS {s.n}</div>
            <div style={m.setScore}>{s.h}:{s.a}</div>
          </div>
        ))}
      </div>

      <div style={m.section}>Statistik · du vs. Gegner</div>
      <div style={m.statsList}>
        <StatRow label="Treffer"     home="18 / 28" away="14 / 27" homeBetter/>
        <StatRow label="Trefferrate" home="64 %"    away="52 %"    homeBetter/>
        <StatRow label="Heli erfolg" home="4 / 5"   away="2 / 3"   homeBetter/>
        <StatRow label="Strafkubbs"  home="0"       away="2"       homeBetter/>
      </div>

      <div style={m.resultActions}>
        <button style={m.endBtnGhost} onClick={onRestart}>Revanche</button>
        <button style={m.endBtn}>Match teilen</button>
      </div>
    </>
  );
}

function StatRow({ label, home, away, homeBetter }) {
  return (
    <div style={m.statRow}>
      <span style={m.statLbl}>{label}</span>
      <span style={{...m.statVal, color: homeBetter ? 'var(--bk-meadow-700)' : 'var(--bk-fg)', fontWeight: homeBetter ? 800 : 700}}>{home}</span>
      <span style={m.statSep}>·</span>
      <span style={{...m.statVal, color:'var(--bk-fg-muted)'}}>{away}</span>
    </div>
  );
}

// ---------- styles ----------
const m = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflowY:'auto' },

  stageBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },
  stageTabs: { display:'flex', gap:4, margin:'4px 16px 12px', background:'var(--bk-bg-sunken)', padding:3, borderRadius:999 },
  stageTab: { flex:1, minHeight:34, padding:'0 12px', border:0, borderRadius:999, background:'transparent', color:'var(--bk-fg-muted)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:12, cursor:'pointer' },
  stageTabOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)' },

  body: { padding:'0 0 24px' },

  // Lobby
  lobbyHero: { display:'grid', gridTemplateColumns:'1fr auto 1fr', gap:6, alignItems:'center', padding:'10px 16px 18px' },
  side: { display:'flex', flexDirection:'column', alignItems:'center', gap:4, minWidth:0 },
  sideAvatar: { width:48, height:48, borderRadius:12, color:'#fff', display:'grid', placeItems:'center', fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:16 },
  sideName: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:13, textAlign:'center', letterSpacing:'-0.01em', lineHeight:1.1, marginTop:4 },
  sideElo: { fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-fg-muted)' },
  formRow: { display:'flex', gap:3, marginTop:4 },
  formCell: { width:16, height:16, borderRadius:3, fontFamily:'var(--bk-font-mono)', fontSize:9, fontWeight:700, display:'grid', placeItems:'center' },

  vsCol: { display:'flex', flexDirection:'column', alignItems:'center', gap:2, padding:'0 6px' },
  vsBig: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:28, letterSpacing:'-0.03em', color:'var(--bk-fg)', lineHeight:1 },
  vsClock: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:18, color:'var(--bk-meadow-600)', marginTop:4, fontVariantNumeric:'tabular-nums' },
  vsMeta: { fontFamily:'var(--bk-font-mono)', fontSize:9, color:'var(--bk-fg-muted)', letterSpacing:'0.04em', textTransform:'uppercase' },

  section: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', padding:'12px 18px 6px' },

  h2hList: { display:'flex', flexDirection:'column', background:'var(--bk-bg-raised)', borderRadius:14, margin:'0 16px', padding:'2px 12px' },
  h2hRow: { display:'grid', gridTemplateColumns:'52px 1fr 40px 36px', gap:8, alignItems:'center', padding:'10px 0', borderBottom:'1px solid var(--bk-line)' },
  h2hDate: { fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-fg-muted)' },
  h2hTeams: { fontSize:12, fontWeight:600 },
  h2hScore: { fontFamily:'var(--bk-font-mono)', fontSize:12, fontWeight:700, textAlign:'center' },
  h2hTag: { fontFamily:'var(--bk-font-mono)', fontSize:9, fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase', padding:'2px 6px', borderRadius:4, textAlign:'center' },

  setupList: { display:'flex', flexDirection:'column', background:'var(--bk-bg-raised)', borderRadius:14, margin:'0 16px', padding:'2px 12px' },
  setupRow: { display:'flex', justifyContent:'space-between', alignItems:'center', padding:'12px 0', borderBottom:'1px solid var(--bk-line)' },
  setupLbl: { fontSize:11, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  setupVal: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:13 },

  startBtn: { margin:'18px 16px 0', minHeight:56, borderRadius:16, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer', display:'flex', alignItems:'center', justifyContent:'center', gap:10 },
  startDot: { width:8, height:8, borderRadius:999, background:'#fff' },

  // Live
  scoreStrip: { display:'grid', gridTemplateColumns:'1fr auto 1fr', gap:8, alignItems:'center', padding:'10px 16px 4px', background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)', margin:'0 16px', borderRadius:14, marginBottom:4 },
  scoreSide: { display:'flex', alignItems:'center', gap:8, padding:'10px 4px' },
  scoreAvatar: { width:32, height:32, borderRadius:8, color:'#fff', display:'grid', placeItems:'center', fontWeight:700, fontSize:12, fontFamily:'var(--bk-font-display)' },
  scoreName: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:13, lineHeight:1.1 },
  scoreNumWrap: { display:'flex', alignItems:'baseline', gap:6, fontFamily:'var(--bk-font-display)', fontVariantNumeric:'tabular-nums' },
  scoreNum: { fontWeight:800, fontSize:44, letterSpacing:'-0.04em', lineHeight:1, color:'var(--bk-chalk-50)' },
  scoreColon: { fontWeight:600, fontSize:30, color:'var(--bk-stone-400)' },
  scoreMeta: { display:'flex', justifyContent:'space-between', padding:'6px 22px 10px', fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-fg-muted)', letterSpacing:'0.06em', textTransform:'uppercase' },
  liveDot: { color:'var(--bk-miss)', fontWeight:700 },

  actionGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:8, padding:'0 16px 8px' },
  actionBtn: { minHeight:80, borderRadius:16, border:0, display:'flex', justifyContent:'space-between', alignItems:'center', padding:'0 18px', cursor:'pointer', boxShadow:'var(--bk-shadow-1)' },
  actionLbl: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:20, letterSpacing:'-0.02em' },
  actionPlus: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:36, lineHeight:1, opacity:0.85 },

  miniCounters: { display:'grid', gridTemplateColumns:'repeat(4, 1fr)', gap:6, padding:'4px 16px 8px' },
  mini: { display:'flex', flexDirection:'column', alignItems:'center', gap:2, padding:'8px 4px', background:'var(--bk-bg-raised)', borderRadius:10 },
  miniLbl: { fontSize:9, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  miniVal: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:20, fontVariantNumeric:'tabular-nums', letterSpacing:'-0.02em' },

  log: { listStyle:'none', padding:0, margin:'0 16px', background:'var(--bk-bg-raised)', borderRadius:14 },
  logRow: { display:'grid', gridTemplateColumns:'34px 48px 1fr auto', gap:8, alignItems:'center', padding:'10px 12px', borderTop:'1px solid var(--bk-line)' },
  logRowLatest: { background:'var(--bk-meadow-50)', borderRadius:8, borderTop:0 },
  logIdx: { fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-fg-muted)' },
  logTag: { fontFamily:'var(--bk-font-mono)', fontSize:9, fontWeight:700, letterSpacing:'0.06em', padding:'3px 6px', borderRadius:4, textAlign:'center' },
  logText: { fontSize:12, fontWeight:600, lineHeight:1.3 },
  logTime: { fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-fg-muted)', fontVariantNumeric:'tabular-nums' },

  endRow: { display:'flex', flexDirection:'column', gap:8, padding:'12px 16px 0' },
  endBtn: { minHeight:54, borderRadius:14, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:16, cursor:'pointer' },
  endBtnGhost: { minHeight:48, borderRadius:12, border:0, background:'transparent', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 1.5px var(--bk-line-strong)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:14, cursor:'pointer', display:'flex', alignItems:'center', justifyContent:'center', gap:8 },

  // Result
  resultHero: { display:'flex', flexDirection:'column', alignItems:'center', gap:4, padding:'20px 16px 18px', background:'var(--bk-meadow-500)', color:'var(--bk-chalk-50)', margin:'0 16px', borderRadius:18 },
  resultEyebrow: { fontSize:11, fontWeight:700, letterSpacing:'0.1em', textTransform:'uppercase', opacity:0.85 },
  resultBigRow: { display:'flex', alignItems:'baseline', gap:8, fontFamily:'var(--bk-font-display)', fontVariantNumeric:'tabular-nums', marginTop:2 },
  resultBig: { fontWeight:800, fontSize:88, letterSpacing:'-0.05em', lineHeight:0.85 },
  resultColon: { fontSize:60, fontWeight:600, opacity:0.6 },
  resultTeams: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:14, marginTop:8 },
  resultMeta: { fontFamily:'var(--bk-font-mono)', fontSize:10, opacity:0.8, letterSpacing:'0.06em', textTransform:'uppercase', marginTop:4 },

  setRow: { display:'grid', gridTemplateColumns:'repeat(5, 1fr)', gap:6, padding:'0 16px' },
  setCard: { padding:'10px 4px', borderRadius:10, textAlign:'center', display:'flex', flexDirection:'column', gap:2 },
  setCardW: { background:'var(--bk-meadow-100)', color:'var(--bk-meadow-700)' },
  setCardL: { background:'var(--bk-stone-100)',  color:'var(--bk-fg-muted)' },
  setLbl: { fontFamily:'var(--bk-font-mono)', fontSize:9, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase' },
  setScore: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:20, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },

  statsList: { display:'flex', flexDirection:'column', background:'var(--bk-bg-raised)', borderRadius:14, margin:'0 16px', padding:'2px 12px' },
  statRow: { display:'grid', gridTemplateColumns:'1fr auto auto auto', gap:8, alignItems:'baseline', padding:'10px 0', borderBottom:'1px solid var(--bk-line)' },
  statLbl: { fontSize:12, color:'var(--bk-fg-muted)' },
  statVal: { fontFamily:'var(--bk-font-display)', fontSize:14, fontVariantNumeric:'tabular-nums' },
  statSep: { color:'var(--bk-fg-muted)' },

  resultActions: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:10, padding:'14px 16px 0' },
};

window.MatchScreen = MatchScreen;
