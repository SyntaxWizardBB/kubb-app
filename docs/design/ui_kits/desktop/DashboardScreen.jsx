/* global React, DIcon, TopBar, PrimaryBtn, SecondaryBtn, Card, CardHeader */
// =====================================================================
// Dashboard — Übersicht beim Einstieg. Linke Spalte (Recent Sessions
// Master-Liste), rechte Spalte (Stats-Summary + nächstes Turnier +
// Trainings-Quick-Start). Master/Detail-Spirit.
// =====================================================================

function DashboardScreen({ onRoute }) {
  return (
    <>
      <TopBar
        eyebrow="Dashboard · Saison 2025"
        title="Servus, Marc."
        subtitle="Du hast diese Woche 4 Sessions gespielt — +12 Treffer gegenüber letzter Woche."
        right={<>
          <SecondaryBtn icon={<DIcon.Calendar/>} tone="default">Diese Woche</SecondaryBtn>
          <PrimaryBtn icon={<DIcon.Plus/>} onClick={() => onRoute('training')}>Training starten</PrimaryBtn>
        </>}
      />

      <div style={d.body}>
        {/* Hero-Tile Row — Tournament + Heute */}
        <div style={d.heroRow}>
          <button style={d.tournamentTile} onClick={() => onRoute('tournament')}>
            <div style={d.tileEyebrow}>Nächstes Turnier · in 12 Tagen</div>
            <div style={d.tileTitle}>BKC Spring Open</div>
            <div style={d.tileSub}>Sa, 06. Juni · Olten · 32 Teams angemeldet</div>
            <div style={d.tileMeta}>
              <span style={d.tileMetaItem}><b>3.</b> letzter Lauf</span>
              <span style={d.tileMetaItem}><b>1283</b> ELO</span>
              <span style={d.tileMetaItem}><b>14</b> Mitspieler</span>
            </div>
            <div style={d.tileArrow}><DIcon.Chevron/></div>
          </button>

          <div style={d.todayCol}>
            <Card padding={18}>
              <div style={d.todayHead}>Heute</div>
              <div style={d.todayMain}>
                <span style={d.todayBig}>64<span style={d.todayUnit}>%</span></span>
                <span style={d.todayLbl}>Trefferrate · 8 m</span>
              </div>
              <div style={d.todayDelta}>
                <span style={d.deltaUp}>▲ 4.0 %</span>
                <span style={{color:'var(--kc-fg-muted)'}}>vs. 7-Tage-Schnitt</span>
              </div>
              <hr style={d.thinLine}/>
              <div style={d.todayGrid}>
                <Mini label="Sessions" value="2"/>
                <Mini label="Würfe" value="78"/>
                <Mini label="Heli" value="3" tone="wood"/>
              </div>
            </Card>
            <button style={d.invitePill} onClick={() => onRoute('match')}>
              <span style={d.invitePillAvatar}>VL</span>
              <span style={{flex:1, textAlign:'left'}}>
                <div style={{fontWeight:700, fontSize:13}}>Vinz lädt dich ein</div>
                <div style={{fontSize:12, color:'var(--kc-fg-muted)'}}>Match · vor 18 min</div>
              </span>
              <DIcon.Chevron/>
            </button>
          </div>
        </div>

        {/* Main grid — left: recent sessions, right: stats + community */}
        <div style={d.grid}>
          <div style={d.col}>
            <Card padding={0}>
              <div style={{padding:'18px 20px 4px'}}>
                <CardHeader
                  eyebrow="Verlauf"
                  title="Letzte Sessions"
                  right={<SecondaryBtn size="sm" tone="ghost" icon={<DIcon.Chevron/>} onClick={() => onRoute('stats')}>Alle</SecondaryBtn>}
                />
              </div>
              <div>
                {RECENT.map((r, i) => (
                  <SessionRow key={i} {...r} onClick={() => onRoute('stats')}/>
                ))}
              </div>
            </Card>

            <Card padding={20}>
              <CardHeader eyebrow="Konstanz" title="Trefferrate · 4 Wochen"/>
              <BigSparkline points={[58,61,57,64,62,66,68,71,69,73,72,75]} max={80}/>
              <div style={d.sparkAxis}>
                <span>vor 4 W</span><span>3</span><span>2</span><span>1</span><span style={{color:'var(--kc-fg)'}}>heute</span>
              </div>
            </Card>
          </div>

          <div style={d.col}>
            <Card padding={20}>
              <CardHeader eyebrow="Statistik" title="Pro Distanz"
                          right={<SecondaryBtn size="sm" tone="ghost" icon={<DIcon.Chevron/>} onClick={() => onRoute('stats')}>Details</SecondaryBtn>}/>
              <div style={d.distList}>
                {DIST.map((x, i) => <DistRow key={i} {...x}/>)}
              </div>
            </Card>

            <Card padding={20}>
              <CardHeader eyebrow="Club & Freunde" title="BKC · Diese Woche"/>
              <div style={d.leaderboard}>
                {LEADERBOARD.map((p, i) => (
                  <div key={i} style={{...d.lbRow, ...(p.you ? d.lbRowYou : {})}}>
                    <span style={d.lbRank}>{i+1}.</span>
                    <span style={d.lbAvatar}>{p.initials}</span>
                    <span style={d.lbName}>{p.name}{p.you && <span style={d.youTag}>du</span>}</span>
                    <span style={d.lbRate}>{p.rate} %</span>
                    <span style={d.lbDelta}>{p.delta > 0 ? `+${p.delta}` : p.delta}</span>
                  </div>
                ))}
              </div>
            </Card>

            <Card padding={18}>
              <CardHeader eyebrow="News · Kubbtour.ch" title="Saison 2025 — Termine sind raus"/>
              <p style={{margin:'0 0 12px', color:'var(--kc-fg-muted)', fontSize:14, lineHeight:1.5}}>
                Anmeldungen für BKC Spring Open, Lake Cup und Tessin Trophy sind offen. Vier neue Tour-Stops gegenüber 2024.
              </p>
              <SecondaryBtn size="sm" tone="ink" icon={<DIcon.Chevron/>}>Zur Tour-Übersicht</SecondaryBtn>
            </Card>
          </div>
        </div>
      </div>
    </>
  );
}

// ---------- Sub-Components ----------
function SessionRow({ tag, rate, sub, when, tone, onClick }) {
  const rateColor = tone === 'bad' ? 'var(--kc-miss)' : tone === 'fin-clean' ? 'var(--kc-meadow-600)' : 'var(--kc-fg)';
  return (
    <button onClick={onClick} style={d.sessionRow}>
      <span style={d.sessionTag}>{tag}</span>
      <span style={{...d.sessionRate, color:rateColor}}>{rate}</span>
      <span style={d.sessionSub}>{sub}</span>
      <span style={d.sessionWhen}>{when}</span>
      <span style={d.sessionArrow}><DIcon.Chevron/></span>
    </button>
  );
}

function Mini({ label, value, tone }) {
  return (
    <div>
      <div style={d.miniLbl}>{label}</div>
      <div style={{...d.miniVal, color: tone === 'wood' ? 'var(--kc-wood-500)' : 'var(--kc-fg)'}}>{value}</div>
    </div>
  );
}

function DistRow({ d:dist, rate, throws, trend }) {
  return (
    <div style={d_distRow.row}>
      <span style={d_distRow.lbl}>{dist}</span>
      <div style={d_distRow.track}>
        <div style={{...d_distRow.fill, width:`${rate}%`}}/>
      </div>
      <span style={d_distRow.val}>{rate}<small> %</small></span>
      <span style={{...d_distRow.delta, color: trend >= 0 ? 'var(--kc-meadow-600)' : 'var(--kc-miss)'}}>
        {trend >= 0 ? `▲ ${trend}` : `▼ ${Math.abs(trend)}`}
      </span>
      <span style={d_distRow.n}>{throws}</span>
    </div>
  );
}

function BigSparkline({ points, max }) {
  const w = 540, h = 140, pad = 8;
  const min = Math.min(...points);
  const span = (max ?? Math.max(...points)) - min || 1;
  const xs = points.map((_, i) => pad + (i * (w - 2*pad)) / (points.length - 1));
  const ys = points.map(p => h - pad - ((p - min) / span) * (h - 2*pad));
  const path = points.map((_, i) => `${i ? 'L' : 'M'}${xs[i]},${ys[i]}`).join(' ');
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} preserveAspectRatio="none" style={{display:'block'}}>
      <defs>
        <linearGradient id="dashSparkFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stopColor="var(--kc-meadow-300)" stopOpacity="0.4"/>
          <stop offset="100%" stopColor="var(--kc-meadow-300)" stopOpacity="0"/>
        </linearGradient>
      </defs>
      {[0,1,2,3].map(i => (
        <line key={i} x1="0" x2={w} y1={pad + i*((h - 2*pad)/3)} y2={pad + i*((h - 2*pad)/3)} stroke="var(--kc-stone-100)" strokeWidth="1"/>
      ))}
      <path d={`${path} L ${xs[xs.length-1]},${h} L ${xs[0]},${h} Z`} fill="url(#dashSparkFill)"/>
      <path d={path} fill="none" stroke="var(--kc-meadow-600)" strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round"/>
      {xs.map((x, i) => i === xs.length - 1 && (
        <g key={i}>
          <circle cx={x} cy={ys[i]} r="5" fill="var(--kc-bg-raised)" stroke="var(--kc-meadow-600)" strokeWidth="2.5"/>
        </g>
      ))}
    </svg>
  );
}

// ---------- Data ----------
const RECENT = [
  { tag:'Sniper', rate:'64 %', sub:'8.0 m · 36 Würfe · 6 Heli', when:'heute · 18:12' },
  { tag:'Fin',    rate:'✓ 5/6', sub:'7/3 · sauber · 12 min', when:'gestern · 19:42', tone:'fin-clean' },
  { tag:'Fin',    rate:'✗ 6/6', sub:'5/5 · Strafkubb · 14 min', when:'vor 2 Tagen', tone:'bad' },
  { tag:'Sniper', rate:'71 %', sub:'7.0 m · 24 Würfe', when:'vor 2 Tagen' },
  { tag:'Sniper', rate:'58 %', sub:'8.0 m · 60 Würfe · 4 Heli', when:'vor 4 Tagen' },
  { tag:'Fin',    rate:'✓ 4/6', sub:'7/3 · 9 min', when:'vor 5 Tagen', tone:'fin-clean' },
];

const DIST = [
  { d:'4.0 m', rate:94, throws:18,  trend:+2 },
  { d:'5.0 m', rate:89, throws:96,  trend:+5 },
  { d:'6.0 m', rate:82, throws:208, trend:+3 },
  { d:'7.0 m', rate:71, throws:412, trend:+8 },
  { d:'8.0 m', rate:58, throws:842, trend:+6 },
];

const LEADERBOARD = [
  { initials:'JT', name:'Jonas T.',   rate:74, delta:+5 },
  { initials:'AV', name:'Anna V.',    rate:71, delta:+2 },
  { initials:'MB', name:'Marc B.',    rate:68, delta:+4, you:true },
  { initials:'PG', name:'Pia G.',     rate:66, delta:-1 },
  { initials:'TK', name:'Tobi K.',    rate:62, delta:+1 },
];

// ---------- Styles ----------
const d = {
  body: { padding:'24px 40px 48px', display:'flex', flexDirection:'column', gap:24, maxWidth:1280 },

  heroRow: { display:'grid', gridTemplateColumns:'1.55fr 1fr', gap:18, alignItems:'stretch' },
  tournamentTile: { position:'relative', border:0, padding:'28px 32px', borderRadius:18, textAlign:'left', cursor:'pointer', background:'var(--kc-wood-500)', backgroundImage:'linear-gradient(135deg, var(--kc-wood-500) 0%, var(--kc-wood-600) 100%)', color:'var(--kc-chalk-50)', boxShadow:'var(--kc-shadow-2)', minHeight:212, display:'flex', flexDirection:'column', justifyContent:'space-between', overflow:'hidden' },
  tileEyebrow: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.1em', textTransform:'uppercase', opacity:0.78 },
  tileTitle:   { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:48, letterSpacing:'-0.025em', lineHeight:1, marginTop:8, fontVariationSettings:'"opsz" 96' },
  tileSub:     { fontSize:15, opacity:0.85, marginTop:8 },
  tileMeta:    { display:'flex', gap:24, marginTop:20, fontFamily:'var(--kc-font-ui)', fontSize:13, flexWrap:'wrap' },
  tileMetaItem:{ display:'flex', flexDirection:'column', opacity:0.95, whiteSpace:'nowrap' },
  tileArrow:   { position:'absolute', top:24, right:24, opacity:0.6 },

  todayCol: { display:'flex', flexDirection:'column', gap:12 },
  todayHead: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  todayMain: { display:'flex', alignItems:'baseline', gap:14, marginTop:6 },
  todayBig:  { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:72, letterSpacing:'-0.04em', lineHeight:1, color:'var(--kc-meadow-600)', fontVariantNumeric:'tabular-nums' },
  todayUnit: { fontSize:24, fontWeight:600, color:'var(--kc-fg-muted)', marginLeft:2 },
  todayLbl:  { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.04em', whiteSpace:'nowrap' },
  todayDelta:{ display:'flex', gap:10, marginTop:4, fontSize:13, whiteSpace:'nowrap' },
  deltaUp:   { color:'var(--kc-meadow-600)', fontWeight:700, fontFamily:'var(--kc-font-mono)' },
  thinLine:  { border:0, borderTop:'1px solid var(--kc-line)', margin:'14px 0' },
  todayGrid: { display:'grid', gridTemplateColumns:'1fr 1fr 1fr', gap:12 },
  miniLbl:   { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  miniVal:   { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:24, letterSpacing:'-0.02em', lineHeight:1.1, marginTop:2, fontVariantNumeric:'tabular-nums' },

  invitePill: { display:'flex', alignItems:'center', gap:10, padding:'10px 14px', borderRadius:14, border:0, background:'var(--kc-bg-raised)', color:'var(--kc-fg)', boxShadow:'var(--kc-shadow-1)', cursor:'pointer' },
  invitePillAvatar: { width:36, height:36, borderRadius:999, background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)', fontWeight:700, fontSize:13, display:'grid', placeItems:'center' },

  grid: { display:'grid', gridTemplateColumns:'1.4fr 1fr', gap:18 },
  col:  { display:'flex', flexDirection:'column', gap:18, minWidth:0 },

  sessionRow: { display:'grid', gridTemplateColumns:'62px 90px 1fr auto 24px', gap:14, alignItems:'baseline', padding:'14px 20px', border:0, borderTop:'1px solid var(--kc-line)', background:'transparent', textAlign:'left', cursor:'pointer', width:'100%' },
  sessionTag: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:700, color:'var(--kc-fg-muted)', letterSpacing:'0.08em', textTransform:'uppercase' },
  sessionRate:{ fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:20, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },
  sessionSub: { fontSize:14, color:'var(--kc-fg-muted)' },
  sessionWhen:{ fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-subtle)', letterSpacing:'0.04em', textAlign:'right' },
  sessionArrow:{ color:'var(--kc-fg-subtle)' },

  sparkAxis: { display:'flex', justifyContent:'space-between', fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', marginTop:8, letterSpacing:'0.04em' },

  distList: { display:'flex', flexDirection:'column', gap:4 },

  leaderboard: { display:'flex', flexDirection:'column' },
  lbRow: { display:'grid', gridTemplateColumns:'28px 32px 1fr auto 48px', gap:12, alignItems:'center', padding:'10px 0', borderBottom:'1px solid var(--kc-line)' },
  lbRowYou: { background:'var(--kc-meadow-50)', margin:'0 -10px', padding:'10px', borderRadius:8, borderBottom:'none' },
  lbRank: { fontFamily:'var(--kc-font-mono)', fontSize:13, fontWeight:600, color:'var(--kc-fg-muted)' },
  lbAvatar: { width:28, height:28, borderRadius:999, background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)', fontSize:11, fontWeight:700, display:'grid', placeItems:'center' },
  lbName: { fontWeight:600, fontSize:14, display:'flex', alignItems:'center', gap:6 },
  youTag: { fontFamily:'var(--kc-font-mono)', fontSize:9, fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-meadow-700)', background:'var(--kc-meadow-100)', padding:'2px 6px', borderRadius:4 },
  lbRate: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:15, fontVariantNumeric:'tabular-nums' },
  lbDelta: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-meadow-600)', textAlign:'right', fontWeight:600 },
};

const d_distRow = {
  row: { display:'grid', gridTemplateColumns:'52px 1fr 62px 52px 48px', gap:10, alignItems:'center', padding:'8px 0', borderBottom:'1px solid var(--kc-line)' },
  lbl: { fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, fontVariantNumeric:'tabular-nums' },
  track: { height:8, background:'var(--kc-stone-100)', borderRadius:999, overflow:'hidden' },
  fill: { height:'100%', background:'linear-gradient(90deg, var(--kc-meadow-400), var(--kc-meadow-600))', borderRadius:999 },
  val: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:16, fontVariantNumeric:'tabular-nums', textAlign:'right' },
  delta: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, textAlign:'right' },
  n: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', textAlign:'right' },
};

window.DashboardScreen = DashboardScreen;
