/* global React, DIcon, TopBar, PrimaryBtn, SecondaryBtn, Card, CardHeader */
// =====================================================================
// Tournaments — Liste + Detail (Standings) im Split.
//   Linke Spalte (380): Tournament-Liste mit Status-Tags
//   Rechte Spalte (flex): Detail des ausgewählten Turniers
//     - Hero (Logo + Name + Datum + CTA)
//     - Bracket-Tabs (Standings | Bracket | Mein Match | Spielplan)
//     - Standings-Tabelle
// =====================================================================

const { useState: useTournState } = React;

const TOURNAMENTS = [
  { id:'spring', name:'BKC Spring Open', date:'06. Juni 2025', when:'in 12 Tagen', status:'upcoming', city:'Olten', teams:32, format:'Double-KO', registered:true, role:'Spieler' },
  { id:'lake',   name:'Lake Cup Zürichsee', date:'21. Juni 2025', when:'in 27 Tagen', status:'upcoming', city:'Wädenswil', teams:24, format:'Liga + Finals', registered:false },
  { id:'tessin', name:'Tessin Trophy', date:'09. Aug. 2025', when:'in 76 Tagen', status:'open', city:'Locarno', teams:16, format:'Round-Robin' },
  { id:'friday', name:'BKC Friday League · KW 21', date:'23. Mai 2025', when:'läuft', status:'live', city:'Bern', teams:12, format:'Swiss · 4 Runden', registered:true, role:'Spieler', live:true },
  { id:'spring24', name:'BKC Spring Open 2024', date:'07. Juni 2024', when:'archiviert', status:'done', city:'Olten', teams:28, format:'Double-KO', result:'3. Rang' },
  { id:'lake24',   name:'Lake Cup 2024', date:'22. Juni 2024', when:'archiviert', status:'done', city:'Wädenswil', teams:20, format:'Liga + Finals', result:'5. Rang' },
];

const STANDINGS = [
  { rank:1,  team:'Solothurn Slingers', w:4, l:0, pts:12, gd:'+18', form:['W','W','W','W'], you:false },
  { rank:2,  team:'BKC United A',       w:3, l:1, pts:9,  gd:'+11', form:['W','L','W','W'], you:false },
  { rank:3,  team:'Marc & Vinz',        w:3, l:1, pts:9,  gd:'+9',  form:['W','W','L','W'], you:true },
  { rank:4,  team:'Bern Bombers',       w:2, l:2, pts:6,  gd:'+2',  form:['L','W','W','L'], you:false },
  { rank:5,  team:'Pia & Tobi',         w:2, l:2, pts:6,  gd:'-1',  form:['W','L','L','W'], you:false },
  { rank:6,  team:'Wood Hammers',       w:1, l:3, pts:3,  gd:'-7',  form:['L','L','W','L'], you:false },
  { rank:7,  team:'BKC United B',       w:1, l:3, pts:3,  gd:'-12', form:['L','W','L','L'], you:false },
  { rank:8,  team:'Zürichsee Casuals',  w:0, l:4, pts:0,  gd:'-20', form:['L','L','L','L'], you:false },
];

function TournamentScreen({ onRoute }) {
  const [active, setActive] = useTournState('friday');
  const [tab, setTab] = useTournState('standings');
  const sel = TOURNAMENTS.find(t => t.id === active) || TOURNAMENTS[0];

  return (
    <>
      <TopBar
        eyebrow="Turniere · Saison 2025"
        title="Tour & Liga"
        subtitle="3 Turniere offen für Anmeldung · 1 Liga live · 14 archiviert."
        right={<>
          <SecondaryBtn icon={<DIcon.Search/>} tone="ghost">Suchen</SecondaryBtn>
          <PrimaryBtn icon={<DIcon.Plus/>}>Turnier hosten</PrimaryBtn>
        </>}
      />

      <div style={tr.split}>
        {/* LEFT — list */}
        <aside style={tr.aside}>
          <div style={tr.listFilter}>
            <button style={{...tr.fchip, ...tr.fchipOn}}>Alle</button>
            <button style={tr.fchip}>Anmelden</button>
            <button style={tr.fchip}>Live</button>
            <button style={tr.fchip}>Archiv</button>
          </div>
          <div style={tr.list}>
            {TOURNAMENTS.map(t => (
              <button key={t.id}
                      style={{...tr.tile, ...(active === t.id ? tr.tileOn : {})}}
                      onClick={() => setActive(t.id)}>
                <div style={tr.tileHead}>
                  <span style={tr.tileWhen}>{t.when}</span>
                  <StatusTag status={t.status}/>
                </div>
                <div style={tr.tileName}>{t.name}</div>
                <div style={tr.tileSub}>
                  <span><DIcon.Calendar/> {t.date}</span>
                  <span>·</span>
                  <span>{t.city} · {t.teams} Teams</span>
                </div>
                {t.registered && (
                  <div style={tr.tileFootRegistered}>
                    <span style={tr.greenDot}/> angemeldet als {t.role}
                  </div>
                )}
                {t.result && (
                  <div style={tr.tileFootResult}>Ergebnis: <b>{t.result}</b></div>
                )}
              </button>
            ))}
          </div>
        </aside>

        {/* RIGHT — detail */}
        <main style={tr.main}>
          {/* Hero */}
          <div style={tr.hero}>
            <div style={tr.heroLogo}>
              <img src="../../assets/logo-mark.svg" alt="" width="72" height="72"/>
            </div>
            <div style={{flex:1, minWidth:0}}>
              <div style={tr.heroEyebrow}>
                {sel.live && <span style={tr.liveDot}><span style={tr.liveDotInner}/></span>}
                {sel.live ? 'LIVE · Runde 4 / 4' : sel.status === 'done' ? 'ARCHIVIERT' : sel.status === 'upcoming' && sel.registered ? 'ANGEMELDET' : 'ANMELDUNG OFFEN'}
              </div>
              <h2 style={tr.heroTitle}>{sel.name}</h2>
              <div style={tr.heroMeta}>
                <Meta label="Datum"  value={sel.date}/>
                <Meta label="Ort"    value={sel.city}/>
                <Meta label="Format" value={sel.format}/>
                <Meta label="Teams"  value={sel.teams.toString()}/>
              </div>
            </div>
            <div style={tr.heroActions}>
              {sel.live ? <PrimaryBtn icon={<DIcon.Target/>}>Match öffnen</PrimaryBtn>
                : sel.registered ? <SecondaryBtn tone="ink">Abmelden</SecondaryBtn>
                : sel.status === 'done' ? <SecondaryBtn icon={<DIcon.Chevron/>}>Rückblick öffnen</SecondaryBtn>
                : <PrimaryBtn icon={<DIcon.Plus/>}>Anmelden · CHF 25</PrimaryBtn>}
              <SecondaryBtn tone="ghost" size="sm" icon={<DIcon.Calendar/>}>Zum Kalender</SecondaryBtn>
            </div>
          </div>

          {/* Sub tabs */}
          <div style={tr.subtabs}>
            {[['standings','Tabelle'], ['bracket','Bracket'], ['mymatch','Mein Match'], ['schedule','Spielplan'], ['rules','Regeln']].map(([k, label]) => (
              <button key={k}
                      style={{...tr.subtab, ...(tab === k ? tr.subtabOn : {})}}
                      onClick={() => setTab(k)}>{label}</button>
            ))}
          </div>

          {/* Content */}
          {tab === 'standings' && <Standings/>}
          {tab === 'bracket'   && <BracketView/>}
          {tab === 'mymatch'   && <MyMatchPanel onRoute={onRoute}/>}
          {tab === 'schedule'  && <SchedulePanel/>}
          {tab === 'rules'     && <RulesPanel sel={sel}/>}
        </main>
      </div>
    </>
  );
}

function StatusTag({ status }) {
  const cfg = {
    upcoming: { label:'Anstehend', bg:'var(--kc-meadow-100)', fg:'var(--kc-meadow-700)' },
    open:     { label:'Anmeldung', bg:'var(--kc-wood-100)', fg:'var(--kc-wood-600)' },
    live:     { label:'LIVE',     bg:'var(--kc-stone-900)', fg:'var(--kc-chalk-50)' },
    done:     { label:'Archiv',   bg:'var(--kc-stone-100)', fg:'var(--kc-fg-muted)' },
  }[status];
  return <span style={{...tr.tag, background:cfg.bg, color:cfg.fg}}>{cfg.label}</span>;
}

function Meta({ label, value }) {
  return (
    <div style={tr.meta}>
      <span style={tr.metaLbl}>{label}</span>
      <span style={tr.metaVal}>{value}</span>
    </div>
  );
}

function Standings() {
  return (
    <Card padding={0}>
      <div style={{padding:'18px 22px 8px'}}>
        <CardHeader eyebrow="BKC Friday League · KW 21" title="Tabelle nach Runde 4"
                    right={<span style={tr.runde}>Runde 4 / 4</span>}/>
      </div>
      <table style={tr.table}>
        <thead>
          <tr>
            <th style={{...tr.th, width:48}}>#</th>
            <th style={{...tr.th, textAlign:'left'}}>Team</th>
            <th style={{...tr.th, width:48, textAlign:'right'}}>S</th>
            <th style={{...tr.th, width:48, textAlign:'right'}}>N</th>
            <th style={{...tr.th, width:60, textAlign:'right'}}>Diff</th>
            <th style={{...tr.th, width:140, textAlign:'left'}}>Form</th>
            <th style={{...tr.th, width:64, textAlign:'right'}}>Pkt</th>
          </tr>
        </thead>
        <tbody>
          {STANDINGS.map(r => (
            <tr key={r.rank} style={{...tr.tr, ...(r.you ? tr.trYou : {})}}>
              <td style={tr.td}>
                <span style={{...tr.rankBubble, ...(r.rank <= 3 ? tr.rankPodium : {})}}>{r.rank}</span>
              </td>
              <td style={tr.td}>
                <span style={tr.teamName}>{r.team}{r.you && <span style={tr.youTag}>du</span>}</span>
              </td>
              <td style={{...tr.td, textAlign:'right'}}><span style={tr.recordCell}>{r.w}</span></td>
              <td style={{...tr.td, textAlign:'right'}}><span style={tr.recordCell}>{r.l}</span></td>
              <td style={{...tr.td, textAlign:'right'}}>
                <span style={{...tr.diffCell, color: r.gd.startsWith('+') ? 'var(--kc-meadow-600)' : r.gd === '0' ? 'var(--kc-fg-muted)' : 'var(--kc-miss)'}}>{r.gd}</span>
              </td>
              <td style={tr.td}>
                <span style={tr.formRow}>
                  {r.form.map((f, i) => (
                    <span key={i} style={{...tr.formCell, background: f === 'W' ? 'var(--kc-meadow-500)' : 'var(--kc-stone-200)', color: f === 'W' ? '#fff' : 'var(--kc-fg-muted)'}}>{f}</span>
                  ))}
                </span>
              </td>
              <td style={{...tr.td, textAlign:'right'}}><span style={tr.ptsCell}>{r.pts}</span></td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

function BracketView() {
  const rounds = [
    { name:'Runde 1', matches:[['Slingers','Casuals'], ['United A','Bombers'], ['Marc & Vinz','Pia & Tobi'], ['Hammers','United B']] },
    { name:'Runde 2', matches:[['Slingers','Hammers'], ['United A','Marc & Vinz']] },
    { name:'Runde 3', matches:[['Slingers','United A']] },
  ];
  return (
    <Card padding={22}>
      <CardHeader eyebrow="Bracket" title="Single-Elimination"/>
      <div style={tr.bracketRow}>
        {rounds.map((r, ri) => (
          <div key={ri} style={tr.bracketCol}>
            <div style={tr.bracketHead}>{r.name}</div>
            <div style={tr.bracketMatches}>
              {r.matches.map((m, mi) => (
                <div key={mi} style={tr.bracketMatch}>
                  <div style={tr.bracketSlot}>
                    <span>{m[0]}</span>
                    <span style={tr.bracketScore}>3</span>
                  </div>
                  <div style={{...tr.bracketSlot, opacity:0.6}}>
                    <span>{m[1]}</span>
                    <span style={tr.bracketScore}>1</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}
        <div style={tr.bracketCol}>
          <div style={tr.bracketHead}>Final</div>
          <div style={{...tr.bracketMatch, background:'var(--kc-wood-100)', boxShadow:'inset 0 0 0 1.5px var(--kc-wood-400)'}}>
            <div style={tr.bracketSlot}><span>?</span><span style={tr.bracketScore}>–</span></div>
            <div style={tr.bracketSlot}><span>?</span><span style={tr.bracketScore}>–</span></div>
          </div>
        </div>
      </div>
    </Card>
  );
}

function MyMatchPanel({ onRoute }) {
  return (
    <Card padding={22}>
      <CardHeader eyebrow="Nächstes Match · Runde 4"
                  title="Marc & Vinz vs. BKC United A"
                  right={<span style={tr.runde}>Court 2 · in ~12 min</span>}/>
      <div style={tr.matchInfo}>
        <div style={tr.matchTeam}>
          <span style={tr.matchAvatar}>MV</span>
          <div>
            <div style={tr.matchTeamName}>Marc & Vinz</div>
            <div style={tr.matchTeamSub}>3 W · 1 N · 1283 / 1241 ELO</div>
          </div>
          <div style={tr.matchTeamScore}>2</div>
        </div>
        <div style={tr.matchVs}>vs.</div>
        <div style={tr.matchTeam}>
          <div style={tr.matchTeamScore}>1</div>
          <div style={{textAlign:'right'}}>
            <div style={tr.matchTeamName}>BKC United A</div>
            <div style={tr.matchTeamSub}>3 W · 1 N · 1305 / 1298 ELO</div>
          </div>
          <span style={tr.matchAvatar}>UA</span>
        </div>
      </div>
      <p style={tr.matchNote}>Halbsatz-Sieger nach 4 von 5 möglichen Halbsätzen. Letztes direktes Aufeinandertreffen: 4:1 für United A (KW 17).</p>
      <div style={{display:'flex', gap:10}}>
        <PrimaryBtn icon={<DIcon.Target/>} onClick={() => onRoute('match')}>Match-Lobby öffnen</PrimaryBtn>
        <SecondaryBtn tone="default">Aufstellung wechseln</SecondaryBtn>
      </div>
    </Card>
  );
}

function SchedulePanel() {
  const slots = [
    { round:'Runde 1', t:'18:00', court:'Court 1', home:'Slingers', away:'Casuals', score:'3:0', done:true },
    { round:'Runde 1', t:'18:00', court:'Court 2', home:'Marc & Vinz', away:'Pia & Tobi', score:'3:1', done:true, you:true },
    { round:'Runde 2', t:'18:45', court:'Court 1', home:'Slingers', away:'Hammers', score:'3:0', done:true },
    { round:'Runde 2', t:'18:45', court:'Court 2', home:'Marc & Vinz', away:'United A', score:'1:3', done:true, you:true },
    { round:'Runde 3', t:'19:30', court:'Court 1', home:'Slingers', away:'United A', score:'3:2', done:true },
    { round:'Runde 3', t:'19:30', court:'Court 2', home:'Marc & Vinz', away:'Hammers', score:'3:0', done:true, you:true },
    { round:'Runde 4', t:'20:15', court:'Court 2', home:'Marc & Vinz', away:'United A', score:null, done:false, you:true },
  ];
  return (
    <Card padding={0}>
      <div style={{padding:'18px 22px 8px'}}>
        <CardHeader eyebrow="Spielplan" title="14 Matches · 7 abgeschlossen"/>
      </div>
      <ul style={{listStyle:'none', padding:0, margin:0}}>
        {slots.map((m, i) => (
          <li key={i} style={{...tr.scheduleRow, ...(m.you ? tr.scheduleRowYou : {}), ...(!m.done ? tr.scheduleRowNext : {})}}>
            <span style={tr.schedTime}>{m.t}</span>
            <span style={tr.schedRound}>{m.round}</span>
            <span style={tr.schedCourt}>{m.court}</span>
            <span style={tr.schedTeams}>
              <span style={{fontWeight: m.you ? 700 : 500}}>{m.home}</span>
              <span style={tr.schedVs}>vs.</span>
              <span style={{fontWeight: m.you ? 700 : 500}}>{m.away}</span>
            </span>
            <span style={tr.schedScore}>{m.score ?? '— : —'}</span>
            <span>{m.done ? <span style={tr.schedDone}>✓</span> : <span style={tr.schedNext}>nächstes</span>}</span>
          </li>
        ))}
      </ul>
    </Card>
  );
}

function RulesPanel({ sel }) {
  return (
    <Card padding={22}>
      <CardHeader eyebrow="Regelwerk" title={`Regeln · ${sel.format}`}/>
      <ul style={tr.rulesList}>
        <li><b>Mannschaft:</b> 2 Spieler pro Team. Substitutionen nur zwischen Halbsätzen.</li>
        <li><b>Material:</b> Holz-Kubbs nach Schweizer Standard. König 280×80 mm.</li>
        <li><b>Halbsatz:</b> Sieger nach 4 von max. 5 Halbsätzen. 6 Wurfstöcke pro Halbsatz.</li>
        <li><b>Strafkubb:</b> Bei verfrühtem König-Treffer → Strafkubb. Drei Strafkubbs → Halbsatz verloren.</li>
        <li><b>Helikopter:</b> Erlaubt. Wird im Live-Tracking optional erfasst.</li>
        <li><b>Punkte:</b> Sieg = 3 Pkt, Niederlage = 0 Pkt. Tabellengleichheit → Diff. → direkter Vergleich.</li>
      </ul>
    </Card>
  );
}

// ---------- Styles ----------
const tr = {
  split: { display:'grid', gridTemplateColumns:'380px 1fr', gap:20, padding:'24px 32px 32px', minHeight:0 },
  aside: { display:'flex', flexDirection:'column', gap:14, overflowY:'auto', maxHeight:'calc(100vh - 220px)' },
  main:  { display:'flex', flexDirection:'column', gap:18, minWidth:0 },

  listFilter: { display:'flex', gap:4, background:'var(--kc-bg-sunken)', padding:4, borderRadius:999, alignSelf:'flex-start' },
  fchip: { minHeight:32, padding:'0 12px', borderRadius:999, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:12, cursor:'pointer' },
  fchipOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  list: { display:'flex', flexDirection:'column', gap:8 },
  tile: { textAlign:'left', border:0, padding:'14px 16px', borderRadius:14, background:'var(--kc-bg-raised)', color:'var(--kc-fg)', cursor:'pointer', boxShadow:'inset 0 0 0 1.5px transparent', display:'flex', flexDirection:'column', gap:6 },
  tileOn: { boxShadow:'inset 0 0 0 1.5px var(--kc-meadow-500)' },
  tileHead: { display:'flex', justifyContent:'space-between', alignItems:'center' },
  tileWhen: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.04em' },
  tileName: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:18, letterSpacing:'-0.015em', lineHeight:1.1, fontVariationSettings:'"opsz" 36' },
  tileSub: { display:'flex', gap:6, color:'var(--kc-fg-muted)', fontSize:12, alignItems:'center' },
  tileFootRegistered: { display:'flex', alignItems:'center', gap:6, fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-meadow-700)', marginTop:2 },
  tileFootResult: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', marginTop:2 },
  greenDot: { width:8, height:8, borderRadius:999, background:'var(--kc-meadow-500)' },
  tag: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase', padding:'3px 8px', borderRadius:4 },

  // Hero
  hero: { display:'flex', alignItems:'center', gap:22, padding:'22px 26px', borderRadius:18, background:'var(--kc-bg-raised)', boxShadow:'var(--kc-shadow-1)' },
  heroLogo: { width:88, height:88, borderRadius:18, background:'var(--kc-meadow-50)', display:'grid', placeItems:'center', flexShrink:0, border:'1px solid var(--kc-meadow-100)' },
  heroEyebrow: { display:'flex', alignItems:'center', gap:8, fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:700, letterSpacing:'0.1em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  heroTitle: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:36, letterSpacing:'-0.025em', margin:'4px 0 12px', lineHeight:1.05, fontVariationSettings:'"opsz" 72' },
  heroMeta: { display:'flex', gap:28 },
  meta: { display:'flex', flexDirection:'column', gap:2 },
  metaLbl: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  metaVal: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14, letterSpacing:'-0.01em' },
  heroActions: { display:'flex', flexDirection:'column', gap:8, alignItems:'flex-end', flexShrink:0 },

  liveDot: { width:10, height:10, borderRadius:999, background:'var(--kc-miss)', display:'inline-grid', placeItems:'center', boxShadow:'0 0 0 4px rgba(183,58,42,0.18)' },
  liveDotInner: { width:4, height:4, borderRadius:999, background:'#fff' },

  // sub tabs
  subtabs: { display:'flex', gap:0, borderBottom:'1px solid var(--kc-line)' },
  subtab: { minHeight:42, padding:'0 16px', border:0, background:'transparent', color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:14, cursor:'pointer', borderBottom:'2px solid transparent', marginBottom:-1 },
  subtabOn: { color:'var(--kc-fg)', borderBottomColor:'var(--kc-stone-900)' },

  // Standings table
  table: { width:'100%', borderCollapse:'collapse', fontFamily:'var(--kc-font-ui)' },
  th: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)', padding:'8px 18px', textAlign:'right', borderTop:'1px solid var(--kc-line)' },
  tr: {},
  trYou: { background:'var(--kc-meadow-50)' },
  td: { padding:'12px 18px', borderTop:'1px solid var(--kc-line)' },
  rankBubble: { width:28, height:28, borderRadius:999, background:'var(--kc-stone-100)', color:'var(--kc-fg-muted)', display:'inline-grid', placeItems:'center', fontFamily:'var(--kc-font-mono)', fontWeight:700, fontSize:12 },
  rankPodium: { background:'var(--kc-wood-400)', color:'#fff' },
  teamName: { fontWeight:700, fontSize:14, display:'flex', alignItems:'center', gap:8 },
  youTag: { fontFamily:'var(--kc-font-mono)', fontSize:9, fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-meadow-700)', background:'var(--kc-meadow-100)', padding:'2px 6px', borderRadius:4 },
  recordCell: { fontFamily:'var(--kc-font-mono)', fontVariantNumeric:'tabular-nums', fontSize:13, color:'var(--kc-fg)' },
  diffCell: { fontFamily:'var(--kc-font-mono)', fontVariantNumeric:'tabular-nums', fontSize:13, fontWeight:600 },
  formRow: { display:'flex', gap:4 },
  formCell: { width:22, height:22, borderRadius:5, fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:700, display:'grid', placeItems:'center' },
  ptsCell: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:18, fontVariantNumeric:'tabular-nums', letterSpacing:'-0.02em' },
  runde: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.06em', textTransform:'uppercase' },

  // bracket
  bracketRow: { display:'flex', gap:24, alignItems:'stretch', overflowX:'auto', paddingTop:8 },
  bracketCol: { minWidth:200, display:'flex', flexDirection:'column', justifyContent:'space-around', gap:14 },
  bracketHead: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  bracketMatches: { display:'flex', flexDirection:'column', justifyContent:'space-around', gap:16, flex:1 },
  bracketMatch: { background:'var(--kc-bg-sunken)', borderRadius:10, padding:'8px 12px', display:'flex', flexDirection:'column', gap:4 },
  bracketSlot: { display:'flex', justifyContent:'space-between', alignItems:'center', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13 },
  bracketScore: { fontFamily:'var(--kc-font-mono)', fontWeight:700, fontVariantNumeric:'tabular-nums' },

  // my match
  matchInfo: { display:'grid', gridTemplateColumns:'1fr auto 1fr', alignItems:'center', gap:14, marginTop:14, paddingBottom:14, borderBottom:'1px solid var(--kc-line)' },
  matchTeam: { display:'flex', alignItems:'center', gap:12 },
  matchAvatar: { width:48, height:48, borderRadius:14, background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)', display:'grid', placeItems:'center', fontWeight:700, fontFamily:'var(--kc-font-ui)' },
  matchTeamName: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:20, letterSpacing:'-0.02em', fontVariationSettings:'"opsz" 36' },
  matchTeamSub: { fontSize:12, color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-mono)' },
  matchTeamScore: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:48, letterSpacing:'-0.04em', fontVariantNumeric:'tabular-nums', minWidth:48, textAlign:'center' },
  matchVs: { fontFamily:'var(--kc-font-mono)', fontSize:13, color:'var(--kc-fg-muted)', letterSpacing:'0.1em', textTransform:'uppercase' },
  matchNote: { color:'var(--kc-fg-muted)', fontSize:13, lineHeight:1.5, margin:'14px 0 14px' },

  // schedule
  scheduleRow: { display:'grid', gridTemplateColumns:'60px 90px 80px 1fr 80px 80px', gap:14, alignItems:'center', padding:'12px 22px', borderTop:'1px solid var(--kc-line)', fontFamily:'var(--kc-font-ui)', fontSize:13 },
  scheduleRowYou: { background:'var(--kc-meadow-50)' },
  scheduleRowNext: { background:'var(--kc-wood-100)', boxShadow:'inset 4px 0 0 0 var(--kc-wood-500)' },
  schedTime: { fontFamily:'var(--kc-font-mono)', fontVariantNumeric:'tabular-nums', fontWeight:600 },
  schedRound: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.04em' },
  schedCourt: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)' },
  schedTeams: { display:'flex', gap:8, alignItems:'center' },
  schedVs: { color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-mono)', fontSize:11 },
  schedScore: { fontFamily:'var(--kc-font-mono)', fontWeight:700, fontVariantNumeric:'tabular-nums', textAlign:'right' },
  schedDone: { color:'var(--kc-meadow-600)' },
  schedNext: { fontFamily:'var(--kc-font-mono)', fontSize:10, color:'var(--kc-wood-600)', fontWeight:700, letterSpacing:'0.08em', textTransform:'uppercase' },

  // rules
  rulesList: { padding:'0 0 0 18px', margin:'14px 0 0', display:'flex', flexDirection:'column', gap:8, color:'var(--kc-fg)', lineHeight:1.5, fontSize:14 },
};

window.TournamentScreen = TournamentScreen;
