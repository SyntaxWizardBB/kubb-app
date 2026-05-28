/* global React, DIcon, TopBar, PrimaryBtn, SecondaryBtn, Card, CardHeader */
// =====================================================================
// Stats — full Analytics-View für Desktop.
//   Tab: Sniper / Finisseur
//   Inhalt: grosser Sparkline, Heros, Pro-Distanz / Pro-Konfig Tabelle,
//   Heatmap Wochentage × Stunden, Streak-Liste.
// =====================================================================

const { useState: useStatsState } = React;

const SNIPER_DIST = [
  { d:'4.0 m', rate:94, throws:18,  trend:+2 },
  { d:'4.5 m', rate:92, throws:24,  trend:+1 },
  { d:'5.0 m', rate:89, throws:96,  trend:+5 },
  { d:'5.5 m', rate:85, throws:42,  trend:+3 },
  { d:'6.0 m', rate:82, throws:208, trend:+3 },
  { d:'6.5 m', rate:74, throws:88,  trend:+0 },
  { d:'7.0 m', rate:71, throws:412, trend:+8 },
  { d:'7.5 m', rate:62, throws:124, trend:+4 },
  { d:'8.0 m', rate:58, throws:842, trend:+6 },
];

const FINIS_CFG = [
  { label:'Standard', c:'7 / 3', rate:62, n:48, trend:+4 },
  { label:'5/5',      c:'5 / 5', rate:48, n:31, trend:+3 },
  { label:'10/0',     c:'10 / 0', rate:38, n:18, trend:-1 },
  { label:'Spät',     c:'3 / 5', rate:71, n:22, trend:+2, user:true },
  { label:'Heim',     c:'8 / 2', rate:55, n:14, trend:+5, user:true },
];

const TREND_LONG = [42,46,44,48,52,49,54,58,55,60,58,62,65,63,68,66,71,72,74,73,75];
const PERIODS = [['7t','7 Tage'], ['4w','4 Wochen'], ['12w','12 Wochen'], ['1j','Saison']];

// 7 days × 14 hours (8-22) heatmap of activity
const HEATMAP = (() => {
  const days = ['Mo','Di','Mi','Do','Fr','Sa','So'];
  const data = days.map((d, di) => {
    return { day:d, cells: Array.from({length:14}, (_,h) => {
      const hour = h + 8;
      // Tend to play in evenings; weekends afternoon.
      let v = 0;
      if (hour >= 17 && hour <= 20) v = 0.4 + ((di * 7 + h * 5) % 60) / 100;
      else if (hour >= 14 && hour <= 17 && di >= 5) v = 0.6 + ((di * 3 + h) % 30) / 100;
      else if ((di * 9 + h * 13) % 23 < 4) v = 0.1 + ((di + h) % 20) / 100;
      return Math.min(1, v);
    })};
  });
  return { days, data, hours: Array.from({length:14}, (_, i) => i + 8) };
})();

function StatsScreen({ onRoute }) {
  const [tab, setTab]     = useStatsState('sniper');
  const [period, setPeriod] = useStatsState('4w');

  const data = tab === 'sniper' ? SNIPER_DIST : FINIS_CFG;
  const totals = data.reduce((a, x) => ({
    throws: a.throws + (x.throws ?? x.n),
    rateSum: a.rateSum + x.rate * (x.throws ?? x.n),
  }), { throws:0, rateSum:0 });
  const overall = totals.throws ? Math.round(totals.rateSum / totals.throws) : 0;

  return (
    <>
      <TopBar
        eyebrow="Statistik"
        title="Deine Wurf-Konstanz"
        subtitle="Aggregiert über alle Trainings — gefiltert nach Modus, Distanz und Zeitraum."
        right={<>
          <SecondaryBtn icon={<DIcon.Calendar/>} tone="ghost" size="sm">Export CSV</SecondaryBtn>
          <SecondaryBtn icon={<DIcon.Plus/>} tone="default" onClick={() => onRoute('training')}>Neue Session</SecondaryBtn>
        </>}
      />

      <div style={s.body}>
        {/* Tabs + period row */}
        <div style={s.controls}>
          <div style={s.tabRow}>
            {[['sniper','Sniper · 8 m'], ['finisseur','Finisseur · 6 Stöcke']].map(([k, label]) => (
              <button key={k}
                      style={{...s.tab, ...(tab === k ? s.tabOn : {})}}
                      onClick={() => setTab(k)}>
                {label}
              </button>
            ))}
          </div>
          <div style={s.periodRow}>
            {PERIODS.map(([k, label]) => (
              <button key={k}
                      style={{...s.period, ...(period === k ? s.periodOn : {})}}
                      onClick={() => setPeriod(k)}>{label}</button>
            ))}
          </div>
        </div>

        {/* Hero grid */}
        <div style={s.heroGrid}>
          <Card padding={20}>
            <CardHeader eyebrow={tab === 'sniper' ? 'Trefferrate · gewichtet' : 'Saubere Rate · gewichtet'}
                        title={`${period === '7t' ? '7 Tage' : period === '4w' ? '4 Wochen' : period === '12w' ? '12 Wochen' : 'Saison 2025'}`}/>
            <div style={s.heroMain}>
              <span style={s.heroBig}>{overall}<span style={s.heroUnit}>%</span></span>
              <div style={s.heroDelta}>
                <span style={s.deltaUp}>▲ {tab === 'sniper' ? '6.2' : '3.8'} %</span>
                <span style={{color:'var(--kc-fg-muted)', fontSize:12}}>vs. vorheriger Zeitraum</span>
              </div>
            </div>
            <BigSparkline points={TREND_LONG.slice(-((period==='7t'?7:period==='4w'?14:period==='12w'?20:21)))} tone={tab === 'sniper' ? 'meadow' : 'wood'}/>
          </Card>

          <Card padding={20}>
            <CardHeader eyebrow="Volumen" title={tab === 'sniper' ? 'Würfe gesamt' : 'Sessions gesamt'}/>
            <div style={s.heroMain}>
              <span style={{...s.heroBig, color:'var(--kc-fg)'}}>
                {totals.throws.toLocaleString('de-CH')}
              </span>
            </div>
            <div style={s.miniGrid}>
              <Mini label={tab==='sniper' ? 'Treffer' : 'sauber'} value={Math.round(totals.throws * overall / 100).toLocaleString('de-CH')} tone="hit"/>
              <Mini label={tab==='sniper' ? 'Miss' : 'Strafe'} value={Math.round(totals.throws * (100-overall) * 0.9 / 100).toLocaleString('de-CH')} tone="miss"/>
              <Mini label="Heli" value="187" tone="wood"/>
              <Mini label="Streak" value="6" tone="default" unit="d"/>
            </div>
          </Card>

          <Card padding={20}>
            <CardHeader eyebrow="Beste" title="Konstanteste Distanz"/>
            <div style={{display:'flex', alignItems:'baseline', gap:14, marginTop:6}}>
              <span style={s.heroBig}>{tab === 'sniper' ? '5.5 m' : '3 / 5'}</span>
              <span style={{...s.deltaUp, fontSize:15}}>▲ 12 %</span>
            </div>
            <p style={s.bestNote}>
              Variationskoeffizient unter den anderen Distanzen am tiefsten — du bist auf {tab === 'sniper' ? '5.5 m' : '3 / 5'} verlässlich.
            </p>
            <div style={s.recordGrid}>
              <Record label="Längste Streak" value="22 / 24" sub="Sniper · 5.5 m · gestern"/>
              <Record label="Bester Tag" value="78 %" sub="22. Mai · 96 Würfe"/>
            </div>
          </Card>
        </div>

        {/* Table + side */}
        <div style={s.split}>
          <Card padding={0} style={{minHeight:0}}>
            <div style={{padding:'18px 22px 8px'}}>
              <CardHeader eyebrow={tab === 'sniper' ? 'Pro Distanz' : 'Pro Konfiguration'}
                          title={`${data.length} ${tab === 'sniper' ? 'Distanzen' : 'Konfigs'}`}
                          right={<SecondaryBtn size="sm" tone="ghost" icon={<DIcon.Chevron/>}>Sortieren · Rate ↓</SecondaryBtn>}/>
            </div>
            <table style={s.table}>
              <thead>
                <tr style={s.thr}>
                  <th style={{...s.th, width:'18%'}}>{tab === 'sniper' ? 'Distanz' : 'Konfig'}</th>
                  <th style={{...s.th, textAlign:'left'}}>Verlauf</th>
                  <th style={{...s.th, width:80, textAlign:'right'}}>Rate</th>
                  <th style={{...s.th, width:80, textAlign:'right'}}>Trend</th>
                  <th style={{...s.th, width:100, textAlign:'right'}}>{tab === 'sniper' ? 'Würfe' : 'Sessions'}</th>
                </tr>
              </thead>
              <tbody>
                {data.map((x, i) => (
                  <tr key={i} style={s.tr}>
                    <td style={s.td}>
                      <div style={s.distCell}>
                        <span style={s.distLabel}>{tab === 'sniper' ? x.d : x.label}</span>
                        {tab === 'finisseur' && <span style={s.distRatio}>{x.c}</span>}
                        {x.user && <span style={s.userBadge}>eigen</span>}
                      </div>
                    </td>
                    <td style={s.td}>
                      <div style={s.distTrack}>
                        <div style={{...s.distFill, width:`${x.rate}%`, background: tab === 'sniper' ? 'linear-gradient(90deg, var(--kc-meadow-400), var(--kc-meadow-600))' : 'linear-gradient(90deg, var(--kc-wood-300), var(--kc-wood-500))'}}/>
                      </div>
                    </td>
                    <td style={{...s.td, textAlign:'right'}}>
                      <span style={s.tdRate}>{x.rate}<small> %</small></span>
                    </td>
                    <td style={{...s.td, textAlign:'right'}}>
                      <span style={{...s.tdTrend, color: x.trend >= 0 ? 'var(--kc-meadow-600)' : 'var(--kc-miss)'}}>
                        {x.trend > 0 ? '▲' : x.trend < 0 ? '▼' : '·'} {Math.abs(x.trend)}
                      </span>
                    </td>
                    <td style={{...s.td, textAlign:'right'}}>
                      <span style={s.tdN}>{(x.throws ?? x.n).toLocaleString('de-CH')}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>

          <div style={s.sideCol}>
            <Card padding={20}>
              <CardHeader eyebrow="Wann du spielst" title="Wochentag × Stunde"/>
              <Heatmap data={HEATMAP}/>
            </Card>

            <Card padding={20}>
              <CardHeader eyebrow="Highlights" title="Letzte 30 Tage"/>
              <ul style={s.highlightList}>
                <li style={s.highlight}>
                  <span style={s.hlIcon}><DIcon.Flame/></span>
                  <div>
                    <div style={s.hlTitle}>22 Treffer in Folge</div>
                    <div style={s.hlSub}>Sniper · 5.5 m · 24. Mai</div>
                  </div>
                </li>
                <li style={s.highlight}>
                  <span style={{...s.hlIcon, background:'var(--kc-wood-100)', color:'var(--kc-wood-500)'}}><DIcon.King/></span>
                  <div>
                    <div style={s.hlTitle}>Erster sauberer 5/5</div>
                    <div style={s.hlSub}>Finisseur · 19. Mai</div>
                  </div>
                </li>
                <li style={s.highlight}>
                  <span style={{...s.hlIcon, background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)'}}><DIcon.Cup/></span>
                  <div>
                    <div style={s.hlTitle}>Aufgestiegen: 1283 ELO</div>
                    <div style={s.hlSub}>BKC Friday League · 16. Mai</div>
                  </div>
                </li>
              </ul>
            </Card>
          </div>
        </div>
      </div>
    </>
  );
}

// ---------- Sub ----------
function BigSparkline({ points, tone }) {
  const w = 540, h = 110, pad = 6;
  const min = Math.min(...points);
  const span = Math.max(...points) - min || 1;
  const xs = points.map((_, i) => pad + (i * (w - 2*pad)) / (points.length - 1));
  const ys = points.map(p => h - pad - ((p - min) / span) * (h - 2*pad));
  const path = points.map((_, i) => `${i ? 'L' : 'M'}${xs[i]},${ys[i]}`).join(' ');
  const stroke = tone === 'wood' ? 'var(--kc-wood-500)' : 'var(--kc-meadow-600)';
  const fillId = tone === 'wood' ? 'statsSparkFillWood' : 'statsSparkFillMeadow';
  const fillStop = tone === 'wood' ? 'var(--kc-wood-300)' : 'var(--kc-meadow-300)';
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} preserveAspectRatio="none" style={{marginTop:10}}>
      <defs>
        <linearGradient id={fillId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stopColor={fillStop} stopOpacity="0.45"/>
          <stop offset="100%" stopColor={fillStop} stopOpacity="0"/>
        </linearGradient>
      </defs>
      <path d={`${path} L ${xs[xs.length-1]},${h} L ${xs[0]},${h} Z`} fill={`url(#${fillId})`}/>
      <path d={path} fill="none" stroke={stroke} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round"/>
      <circle cx={xs[xs.length-1]} cy={ys[ys.length-1]} r="5" fill="var(--kc-bg-raised)" stroke={stroke} strokeWidth="2.5"/>
    </svg>
  );
}

function Mini({ label, value, tone, unit }) {
  const color = tone === 'hit' ? 'var(--kc-meadow-600)' : tone === 'miss' ? 'var(--kc-miss)' : tone === 'wood' ? 'var(--kc-wood-500)' : 'var(--kc-fg)';
  return (
    <div>
      <div style={s.miniLbl}>{label}</div>
      <div style={{...s.miniVal, color}}>{value}{unit && <small style={s.miniUnit}>{unit}</small>}</div>
    </div>
  );
}

function Record({ label, value, sub }) {
  return (
    <div style={s.record}>
      <div style={s.recordLbl}>{label}</div>
      <div style={s.recordVal}>{value}</div>
      <div style={s.recordSub}>{sub}</div>
    </div>
  );
}

function Heatmap({ data }) {
  return (
    <div style={s.hmWrap}>
      <div style={s.hmGrid}>
        <div/>
        {data.hours.filter((_, i) => i % 2 === 0).map(h => (
          <div key={h} style={{...s.hmHour, gridColumn:`span 2`}}>{h}</div>
        ))}
        {data.data.map((row, ri) => (
          <React.Fragment key={ri}>
            <div style={s.hmDay}>{row.day}</div>
            {row.cells.map((v, ci) => (
              <div key={ci} style={{...s.hmCell, background: hmColor(v)}} title={`${row.day} ${data.hours[ci]}:00 — ${(v*100).toFixed(0)}%`}/>
            ))}
          </React.Fragment>
        ))}
      </div>
      <div style={s.hmLegend}>
        <span>weniger</span>
        {[0.05, 0.25, 0.5, 0.75, 0.95].map((v, i) => (
          <span key={i} style={{...s.hmLegendCell, background:hmColor(v)}}/>
        ))}
        <span>mehr</span>
      </div>
    </div>
  );
}

function hmColor(v) {
  if (v < 0.05) return 'var(--kc-stone-100)';
  const l = 90 - v * 50;
  return `oklch(${l}% 0.10 145)`;
}

// ---------- Styles ----------
const s = {
  body: { padding:'20px 40px 48px', display:'flex', flexDirection:'column', gap:18, maxWidth:1280 },

  controls: { display:'flex', justifyContent:'space-between', alignItems:'center', gap:18, flexWrap:'wrap' },
  tabRow: { display:'flex', gap:6, background:'var(--kc-bg-sunken)', padding:4, borderRadius:999 },
  tab: { minHeight:40, padding:'0 18px', borderRadius:999, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:14, cursor:'pointer' },
  tabOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },
  periodRow: { display:'flex', gap:4, background:'var(--kc-bg-sunken)', padding:4, borderRadius:999 },
  period: { minHeight:36, padding:'0 14px', borderRadius:999, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-mono)', fontWeight:600, fontSize:12, cursor:'pointer', letterSpacing:'0.04em' },
  periodOn: { background:'var(--kc-meadow-500)', color:'#fff' },

  heroGrid: { display:'grid', gridTemplateColumns:'1.4fr 1fr 1fr', gap:18 },
  heroMain: { display:'flex', alignItems:'baseline', gap:14, marginTop:6 },
  heroBig: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:64, lineHeight:1, letterSpacing:'-0.04em', color:'var(--kc-meadow-600)', fontVariantNumeric:'tabular-nums' },
  heroUnit: { fontSize:22, fontWeight:600, color:'var(--kc-fg-muted)', marginLeft:2 },
  heroDelta: { display:'flex', flexDirection:'column', gap:2 },
  deltaUp: { color:'var(--kc-meadow-600)', fontWeight:700, fontFamily:'var(--kc-font-mono)', fontSize:13 },

  miniGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:14, marginTop:14 },
  miniLbl: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  miniVal: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:22, marginTop:2, fontVariantNumeric:'tabular-nums', letterSpacing:'-0.02em' },
  miniUnit: { fontSize:13, marginLeft:2, color:'var(--kc-fg-muted)', fontWeight:600 },

  bestNote: { color:'var(--kc-fg-muted)', fontSize:13, lineHeight:1.5, margin:'12px 0 12px' },
  recordGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:12 },
  record: { padding:'10px 12px', borderRadius:10, background:'var(--kc-bg-sunken)' },
  recordLbl: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  recordVal: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:18, marginTop:2, fontVariantNumeric:'tabular-nums', letterSpacing:'-0.02em' },
  recordSub: { fontSize:11, color:'var(--kc-fg-muted)', marginTop:2 },

  split: { display:'grid', gridTemplateColumns:'1.5fr 1fr', gap:18 },
  sideCol: { display:'flex', flexDirection:'column', gap:18 },

  table: { width:'100%', borderCollapse:'collapse', fontFamily:'var(--kc-font-ui)' },
  thr: { },
  th: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)', padding:'8px 22px', textAlign:'left', borderTop:'1px solid var(--kc-line)' },
  tr: { },
  td: { padding:'12px 22px', borderTop:'1px solid var(--kc-line)', verticalAlign:'middle' },

  distCell: { display:'flex', alignItems:'center', gap:8 },
  distLabel: { fontWeight:700, fontSize:14, fontVariantNumeric:'tabular-nums' },
  distRatio: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)' },
  userBadge: { fontFamily:'var(--kc-font-mono)', fontSize:9, fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-meadow-700)', background:'var(--kc-meadow-100)', padding:'2px 6px', borderRadius:4 },
  distTrack: { height:8, background:'var(--kc-stone-100)', borderRadius:999, overflow:'hidden', maxWidth:'90%' },
  distFill: { height:'100%', borderRadius:999 },
  tdRate: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:16, fontVariantNumeric:'tabular-nums' },
  tdTrend: { fontFamily:'var(--kc-font-mono)', fontSize:12, fontWeight:600 },
  tdN: { fontFamily:'var(--kc-font-mono)', fontSize:12, color:'var(--kc-fg-muted)' },

  // Heatmap
  hmWrap: { marginTop:8 },
  hmGrid: { display:'grid', gridTemplateColumns:'28px repeat(14, 1fr)', gap:3, alignItems:'center' },
  hmHour: { fontFamily:'var(--kc-font-mono)', fontSize:10, color:'var(--kc-fg-muted)', textAlign:'left', paddingLeft:2 },
  hmDay:  { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, color:'var(--kc-fg-muted)' },
  hmCell: { aspectRatio:'1 / 1', borderRadius:3 },
  hmLegend: { display:'flex', alignItems:'center', gap:4, marginTop:10, fontFamily:'var(--kc-font-mono)', fontSize:10, color:'var(--kc-fg-muted)' },
  hmLegendCell: { width:14, height:14, borderRadius:3, display:'inline-block' },

  // Highlights
  highlightList: { listStyle:'none', padding:0, margin:0, display:'flex', flexDirection:'column', gap:10 },
  highlight: { display:'flex', alignItems:'center', gap:12 },
  hlIcon: { width:36, height:36, borderRadius:10, background:'var(--kc-meadow-100)', color:'var(--kc-meadow-700)', display:'grid', placeItems:'center', flexShrink:0 },
  hlTitle: { fontWeight:700, fontSize:14, letterSpacing:'-0.01em' },
  hlSub: { fontSize:12, color:'var(--kc-fg-muted)', marginTop:1 },
};

window.StatsScreen = StatsScreen;
