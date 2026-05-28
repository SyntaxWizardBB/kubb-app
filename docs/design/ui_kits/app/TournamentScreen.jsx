/* global React, BK */
const { useState } = React;
const { Icon, AppBar } = BK;

// =====================================================================
// Screen: Tournaments — Mobile-Variante des Desktop-Splits.
//   Stack: Filter-Chips → Hero des aktiven Turniers → Sub-Tabs →
//   (Standings | Bracket | Mein Match | Spielplan) → Liste weiterer
// =====================================================================

const TOURNAMENTS = [
  { id:'friday', name:'BKC Friday League · KW 21', date:'23. Mai 2025', when:'läuft', status:'live', city:'Bern', teams:12, format:'Swiss · 4 Runden', registered:true, role:'Spieler', live:true },
  { id:'spring', name:'BKC Spring Open',           date:'06. Juni 2025', when:'in 12 Tagen', status:'upcoming', city:'Olten', teams:32, format:'Double-KO', registered:true, role:'Spieler' },
  { id:'lake',   name:'Lake Cup Zürichsee',        date:'21. Juni 2025', when:'in 27 Tagen', status:'upcoming', city:'Wädenswil', teams:24, format:'Liga + Finals', registered:false },
  { id:'tessin', name:'Tessin Trophy',             date:'09. Aug. 2025', when:'in 76 Tagen', status:'open', city:'Locarno', teams:16, format:'Round-Robin' },
  { id:'spring24', name:'BKC Spring Open 2024',    date:'07. Juni 2024', when:'archiviert', status:'done', city:'Olten', teams:28, format:'Double-KO', result:'3. Rang' },
];

const STANDINGS = [
  { rank:1, team:'Slingers',     w:4, l:0, pts:12, gd:'+18', you:false },
  { rank:2, team:'BKC United A', w:3, l:1, pts:9,  gd:'+11', you:false },
  { rank:3, team:'Marc & Vinz',  w:3, l:1, pts:9,  gd:'+9',  you:true },
  { rank:4, team:'Bern Bombers', w:2, l:2, pts:6,  gd:'+2',  you:false },
  { rank:5, team:'Pia & Tobi',   w:2, l:2, pts:6,  gd:'-1',  you:false },
  { rank:6, team:'Hammers',      w:1, l:3, pts:3,  gd:'-7',  you:false },
  { rank:7, team:'United B',     w:1, l:3, pts:3,  gd:'-12', you:false },
  { rank:8, team:'Casuals',      w:0, l:4, pts:0,  gd:'-20', you:false },
];

function TournamentScreen({ onBack, onOpenMatch }) {
  const [filter, setFilter] = useState('all');
  const [active, setActive] = useState('friday');
  const [tab, setTab]       = useState('standings');
  const sel = TOURNAMENTS.find(t => t.id === active) || TOURNAMENTS[0];

  const filtered = filter === 'all' ? TOURNAMENTS
    : filter === 'open' ? TOURNAMENTS.filter(t => t.status === 'open' || (t.status === 'upcoming' && !t.registered))
    : filter === 'live' ? TOURNAMENTS.filter(t => t.live)
    : TOURNAMENTS.filter(t => t.status === 'done');

  return (
    <div style={t.screen}>
      <AppBar
        eyebrow="Turniere · Saison 2025"
        title="Tour & Liga"
        onBack={onBack}
        right={<button style={t.iconBtn}><Icon.Filter/></button>}
      />

      {/* Filter chips */}
      <div style={t.filterRow}>
        {[['all','Alle'], ['open','Anmelden'], ['live','Live'], ['done','Archiv']].map(([k, lbl]) => (
          <button key={k}
                  style={{...t.filter, ...(filter === k ? t.filterOn : {})}}
                  onClick={() => setFilter(k)}>{lbl}</button>
        ))}
      </div>

      {/* Active tournament hero */}
      <button style={{...t.hero, ...(sel.live ? t.heroLive : {})}}
              onClick={() => {}}>
        <div style={t.heroHead}>
          {sel.live && <span style={t.liveBadge}><span style={t.liveBlink}/> LIVE</span>}
          {!sel.live && <StatusTag status={sel.status}/>}
          <span style={t.heroWhen}>{sel.when}</span>
        </div>
        <div style={t.heroName}>{sel.name}</div>
        <div style={t.heroMeta}>
          <span>{sel.date}</span>
          <span>·</span>
          <span>{sel.city}</span>
          <span>·</span>
          <span>{sel.teams} Teams</span>
        </div>
        {sel.registered && (
          <div style={t.heroReg}><span style={t.greenDot}/> angemeldet als {sel.role}</div>
        )}
      </button>

      {/* Action */}
      <div style={t.actionRow}>
        {sel.live ? (
          <button style={t.cta} onClick={onOpenMatch}><Icon.Target/> Mein Match öffnen</button>
        ) : sel.registered ? (
          <button style={t.ctaGhost}>Abmelden</button>
        ) : sel.status === 'done' ? (
          <button style={t.ctaGhost}><Icon.ChevronRight/> Rückblick</button>
        ) : (
          <button style={t.cta}><Icon.Plus2/> Anmelden · CHF 25</button>
        )}
      </div>

      {/* Sub-tabs */}
      <div style={t.tabs}>
        {[['standings','Tabelle'], ['bracket','Bracket'], ['mymatch','Mein Match'], ['schedule','Plan']].map(([k, lbl]) => (
          <button key={k}
                  style={{...t.tab, ...(tab === k ? t.tabOn : {})}}
                  onClick={() => setTab(k)}>{lbl}</button>
        ))}
      </div>

      {tab === 'standings' && <Standings/>}
      {tab === 'bracket'   && <BracketView/>}
      {tab === 'mymatch'   && <MyMatch onOpenMatch={onOpenMatch}/>}
      {tab === 'schedule'  && <Schedule/>}

      {/* List of others */}
      <div style={t.section}>Weitere Turniere</div>
      <div style={t.list}>
        {filtered.filter(x => x.id !== active).map(x => (
          <button key={x.id} style={t.tile} onClick={() => setActive(x.id)}>
            <div style={t.tileHead}>
              <span style={t.tileWhen}>{x.when}</span>
              <StatusTag status={x.status}/>
            </div>
            <div style={t.tileName}>{x.name}</div>
            <div style={t.tileSub}>{x.date} · {x.city}</div>
            {x.registered && <div style={t.tileReg}><span style={t.greenDot}/> angemeldet</div>}
            {x.result && <div style={t.tileResult}>Ergebnis: <b>{x.result}</b></div>}
          </button>
        ))}
      </div>
      <div style={{height:32}}/>
    </div>
  );
}

function StatusTag({ status }) {
  const c = {
    upcoming: { lbl:'Anstehend', bg:'var(--bk-meadow-100)', fg:'var(--bk-meadow-700)' },
    open:     { lbl:'Anmeldung', bg:'var(--bk-wood-100)',   fg:'var(--bk-wood-600)' },
    live:     { lbl:'LIVE',      bg:'var(--bk-stone-900)',  fg:'var(--bk-chalk-50)' },
    done:     { lbl:'Archiv',    bg:'var(--bk-stone-100)',  fg:'var(--bk-fg-muted)' },
  }[status];
  return <span style={{...t.tag, background:c.bg, color:c.fg}}>{c.lbl}</span>;
}

function Standings() {
  return (
    <div style={t.contentBox}>
      <div style={t.tableHead}>
        <span>#</span>
        <span style={{textAlign:'left'}}>Team</span>
        <span>S</span>
        <span>N</span>
        <span>Diff</span>
        <span>Pkt</span>
      </div>
      {STANDINGS.map(r => (
        <div key={r.rank} style={{...t.tableRow, ...(r.you ? t.tableRowYou : {})}}>
          <span style={{...t.rankBubble, ...(r.rank <= 3 ? t.rankPodium : {})}}>{r.rank}</span>
          <span style={t.teamCol}>
            {r.team}
            {r.you && <span style={t.youTag}>du</span>}
          </span>
          <span style={t.numCell}>{r.w}</span>
          <span style={t.numCell}>{r.l}</span>
          <span style={{...t.numCell, color: r.gd.startsWith('+') ? 'var(--bk-meadow-600)' : 'var(--bk-miss)'}}>{r.gd}</span>
          <span style={t.ptsCell}>{r.pts}</span>
        </div>
      ))}
    </div>
  );
}

function BracketView() {
  const rounds = [
    ['R1', [['Slingers','Casuals','3','0'], ['United A','Bombers','3','1'], ['Marc & Vinz','Pia & Tobi','3','1'], ['Hammers','United B','3','2']]],
    ['R2', [['Slingers','Hammers','3','0'], ['United A','Marc & Vinz','3','1']]],
    ['R3', [['Slingers','United A','3','2']]],
  ];
  return (
    <div style={t.contentBox}>
      <div style={t.bracketScroll}>
        {rounds.map(([name, matches], ri) => (
          <div key={ri} style={t.bracketCol}>
            <div style={t.bracketHead}>{name}</div>
            {matches.map((m, mi) => (
              <div key={mi} style={t.bracketMatch}>
                <div style={t.bracketSlot}><span>{m[0]}</span><span>{m[2]}</span></div>
                <div style={{...t.bracketSlot, opacity:0.55}}><span>{m[1]}</span><span>{m[3]}</span></div>
              </div>
            ))}
          </div>
        ))}
        <div style={t.bracketCol}>
          <div style={t.bracketHead}>Final</div>
          <div style={{...t.bracketMatch, background:'var(--bk-wood-100)', boxShadow:'inset 0 0 0 1.5px var(--bk-wood-400)'}}>
            <div style={t.bracketSlot}><span>?</span><span>–</span></div>
            <div style={t.bracketSlot}><span>?</span><span>–</span></div>
          </div>
        </div>
      </div>
    </div>
  );
}

function MyMatch({ onOpenMatch }) {
  return (
    <div style={t.contentBox}>
      <div style={t.myMatchHead}>
        <span style={t.myMatchRound}>Runde 4 · Court 2</span>
        <span style={t.myMatchClock}>in ~12 min</span>
      </div>
      <div style={t.myMatchTeams}>
        <div style={t.myMatchSide}>
          <span style={t.myMatchAv}>MV</span>
          <div>
            <div style={t.myMatchName}>Marc & Vinz</div>
            <div style={t.myMatchSub}>3 W · 1 N</div>
          </div>
        </div>
        <span style={t.myMatchScore}>2 : 1</span>
        <div style={t.myMatchSide}>
          <span style={t.myMatchAv}>UA</span>
          <div>
            <div style={t.myMatchName}>United A</div>
            <div style={t.myMatchSub}>3 W · 1 N</div>
          </div>
        </div>
      </div>
      <p style={t.myMatchNote}>
        Halbsatz-Sieger nach 4 von 5. Letzte Begegnung: 4:1 für United A (KW 17).
      </p>
      <button style={t.cta} onClick={onOpenMatch}><Icon.Target/> Match-Lobby öffnen</button>
    </div>
  );
}

function Schedule() {
  const slots = [
    { r:'R1', time:'18:00', home:'Marc & Vinz', away:'Pia & Tobi',  score:'3:1', done:true,  you:true },
    { r:'R2', time:'18:45', home:'Marc & Vinz', away:'United A',    score:'1:3', done:true,  you:true },
    { r:'R3', time:'19:30', home:'Marc & Vinz', away:'Hammers',     score:'3:0', done:true,  you:true },
    { r:'R4', time:'20:15', home:'Marc & Vinz', away:'United A',    score:null,  done:false, you:true, next:true },
  ];
  return (
    <div style={t.contentBox}>
      {slots.map((s, i) => (
        <div key={i} style={{...t.schedRow, ...(s.next ? t.schedRowNext : {})}}>
          <div style={t.schedLeft}>
            <span style={t.schedTime}>{s.time}</span>
            <span style={t.schedRound}>{s.r}</span>
          </div>
          <div style={t.schedTeams}>
            <span>{s.home}</span>
            <span style={{color:'var(--bk-fg-muted)', fontFamily:'var(--bk-font-mono)', fontSize:10}}>vs.</span>
            <span>{s.away}</span>
          </div>
          <span style={t.schedScore}>{s.score ?? '— : —'}</span>
          {s.done
            ? <span style={t.schedDone}>✓</span>
            : <span style={t.schedNext}>nächstes</span>}
        </div>
      ))}
    </div>
  );
}

const t = {
  screen: { display:'flex', flexDirection:'column', minHeight:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflowY:'auto' },
  iconBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },

  filterRow: { display:'flex', gap:6, padding:'4px 16px 10px', overflowX:'auto' },
  filter: { minHeight:32, padding:'0 12px', borderRadius:999, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg-muted)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:12, cursor:'pointer', boxShadow:'inset 0 0 0 1.5px var(--bk-line)', whiteSpace:'nowrap' },
  filterOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)', boxShadow:'none' },

  hero: { display:'flex', flexDirection:'column', gap:6, padding:'14px 16px', margin:'0 16px', background:'var(--bk-bg-raised)', borderRadius:18, border:0, textAlign:'left', cursor:'pointer', boxShadow:'var(--bk-shadow-1)' },
  heroLive: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)' },
  heroHead: { display:'flex', justifyContent:'space-between', alignItems:'center' },
  heroWhen: { fontFamily:'var(--bk-font-mono)', fontSize:10, opacity:0.7, letterSpacing:'0.04em' },
  liveBadge: { display:'inline-flex', alignItems:'center', gap:6, fontFamily:'var(--bk-font-mono)', fontSize:10, fontWeight:700, letterSpacing:'0.1em', textTransform:'uppercase', color:'var(--bk-miss)', background:'rgba(255,255,255,0.08)', padding:'3px 8px', borderRadius:4 },
  liveBlink: { width:6, height:6, borderRadius:999, background:'var(--bk-miss)' },
  heroName: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:20, letterSpacing:'-0.02em', lineHeight:1.15 },
  heroMeta: { display:'flex', gap:6, fontSize:11, opacity:0.78, flexWrap:'wrap' },
  heroReg: { display:'inline-flex', alignItems:'center', gap:6, fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-meadow-300)', marginTop:4 },
  greenDot: { width:6, height:6, borderRadius:999, background:'var(--bk-meadow-400)' },

  actionRow: { padding:'10px 16px 4px' },
  cta: { display:'flex', alignItems:'center', justifyContent:'center', gap:8, minHeight:50, width:'100%', borderRadius:14, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:15, cursor:'pointer' },
  ctaGhost: { display:'flex', alignItems:'center', justifyContent:'center', gap:8, minHeight:50, width:'100%', borderRadius:14, border:0, background:'transparent', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 1.5px var(--bk-line-strong)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:14, cursor:'pointer' },

  tabs: { display:'flex', gap:4, margin:'14px 16px 8px', background:'var(--bk-bg-sunken)', borderRadius:999, padding:3 },
  tab: { flex:1, minHeight:32, padding:'0 8px', border:0, borderRadius:999, background:'transparent', color:'var(--bk-fg-muted)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:12, cursor:'pointer' },
  tabOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)' },

  contentBox: { background:'var(--bk-bg-raised)', borderRadius:14, margin:'0 16px', padding:'4px 12px', overflow:'hidden' },

  tableHead: { display:'grid', gridTemplateColumns:'26px 1fr 24px 24px 38px 32px', gap:6, fontFamily:'var(--bk-font-mono)', fontSize:9, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--bk-fg-muted)', padding:'10px 0 6px', borderBottom:'1px solid var(--bk-line)', textAlign:'right' },
  tableRow: { display:'grid', gridTemplateColumns:'26px 1fr 24px 24px 38px 32px', gap:6, alignItems:'center', padding:'10px 0', borderBottom:'1px solid var(--bk-line)', textAlign:'right', fontFamily:'var(--bk-font-display)', fontSize:13 },
  tableRowYou: { background:'var(--bk-meadow-50)', margin:'0 -6px', padding:'10px 6px', borderRadius:6, borderBottom:'1px solid var(--bk-line)' },
  rankBubble: { width:22, height:22, borderRadius:999, background:'var(--bk-stone-100)', color:'var(--bk-fg-muted)', display:'inline-grid', placeItems:'center', fontFamily:'var(--bk-font-mono)', fontWeight:700, fontSize:10 },
  rankPodium: { background:'var(--bk-wood-400)', color:'#fff' },
  teamCol: { textAlign:'left', fontWeight:700, display:'flex', alignItems:'center', gap:6, overflow:'hidden', whiteSpace:'nowrap', textOverflow:'ellipsis' },
  youTag: { fontFamily:'var(--bk-font-mono)', fontSize:8, fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--bk-meadow-700)', background:'var(--bk-meadow-100)', padding:'1px 4px', borderRadius:3 },
  numCell: { fontFamily:'var(--bk-font-mono)', fontWeight:600, fontVariantNumeric:'tabular-nums', fontSize:11 },
  ptsCell: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:14, fontVariantNumeric:'tabular-nums' },

  // bracket
  bracketScroll: { display:'flex', gap:10, overflowX:'auto', padding:'10px 0' },
  bracketCol: { display:'flex', flexDirection:'column', gap:6, minWidth:120, flexShrink:0 },
  bracketHead: { fontFamily:'var(--bk-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  bracketMatch: { background:'var(--bk-bg-sunken)', borderRadius:8, padding:'6px 8px', display:'flex', flexDirection:'column', gap:2 },
  bracketSlot: { display:'flex', justifyContent:'space-between', alignItems:'center', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:11 },

  // my match
  myMatchHead: { display:'flex', justifyContent:'space-between', alignItems:'center', padding:'10px 0 8px', borderBottom:'1px solid var(--bk-line)' },
  myMatchRound: { fontFamily:'var(--bk-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  myMatchClock: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:13, color:'var(--bk-wood-600)' },
  myMatchTeams: { display:'grid', gridTemplateColumns:'1fr auto 1fr', gap:8, alignItems:'center', padding:'14px 0' },
  myMatchSide: { display:'flex', alignItems:'center', gap:8, minWidth:0 },
  myMatchAv: { width:36, height:36, borderRadius:10, background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)', display:'grid', placeItems:'center', fontWeight:700, fontSize:12, fontFamily:'var(--bk-font-display)' },
  myMatchName: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:13, lineHeight:1.1 },
  myMatchSub: { fontSize:11, color:'var(--bk-fg-muted)' },
  myMatchScore: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:22, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },
  myMatchNote: { fontSize:12, color:'var(--bk-fg-muted)', lineHeight:1.4, margin:'0 0 12px' },

  // schedule
  schedRow: { display:'grid', gridTemplateColumns:'56px 1fr auto auto', gap:8, alignItems:'center', padding:'10px 0', borderBottom:'1px solid var(--bk-line)' },
  schedRowNext: { background:'var(--bk-wood-50)', boxShadow:'inset 3px 0 0 0 var(--bk-wood-500)', margin:'0 -6px', padding:'10px 8px', borderRadius:6 },
  schedLeft: { display:'flex', flexDirection:'column' },
  schedTime: { fontFamily:'var(--bk-font-mono)', fontVariantNumeric:'tabular-nums', fontWeight:700, fontSize:13 },
  schedRound: { fontFamily:'var(--bk-font-mono)', fontSize:9, color:'var(--bk-fg-muted)', letterSpacing:'0.04em' },
  schedTeams: { display:'flex', flexDirection:'column', gap:1, fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:12, lineHeight:1.2 },
  schedScore: { fontFamily:'var(--bk-font-mono)', fontWeight:700, fontVariantNumeric:'tabular-nums', fontSize:12 },
  schedDone: { color:'var(--bk-meadow-600)', fontWeight:800 },
  schedNext: { fontFamily:'var(--bk-font-mono)', fontSize:9, color:'var(--bk-wood-600)', fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase' },

  section: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', padding:'18px 18px 8px' },

  list: { display:'flex', flexDirection:'column', gap:8, padding:'0 16px' },
  tile: { display:'flex', flexDirection:'column', gap:4, padding:'12px 14px', borderRadius:14, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', textAlign:'left', cursor:'pointer', boxShadow:'inset 0 0 0 1px var(--bk-line)' },
  tileHead: { display:'flex', justifyContent:'space-between', alignItems:'center' },
  tileWhen: { fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-fg-muted)' },
  tileName: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:15, letterSpacing:'-0.015em', lineHeight:1.15 },
  tileSub: { fontSize:11, color:'var(--bk-fg-muted)' },
  tileReg: { display:'inline-flex', alignItems:'center', gap:6, fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-meadow-700)' },
  tileResult: { fontFamily:'var(--bk-font-mono)', fontSize:11, color:'var(--bk-fg-muted)' },

  tag: { fontFamily:'var(--bk-font-mono)', fontSize:9, fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase', padding:'3px 7px', borderRadius:4 },
};

window.TournamentScreen = TournamentScreen;
