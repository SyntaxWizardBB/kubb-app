/* global React, BK */
const { useState, useMemo } = React;
const { Icon, AppBar } = BK;

// =====================================================================
// Screen: Statistik
//   - AppBar (vereinheitlicht)
//   - Sparkline-Graph IMMER ganz oben unter der AppBar
//   - Filter-Pille rechts in der AppBar -> öffnet Filter-Sheet
//     - Sniper:    Distanzen einzeln aktivieren / "Alle" / "Stamm"
//     - Finisseur: Built-in & User-Presets einzeln aktivieren / "Alle"
//   - Aggregate (Hero-Zahlen + Distanzliste) reagieren auf Filter
// =====================================================================

const ALL_DISTANCES = [4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0];

// Mock-Daten — Sniper pro Distanz
const SNIPER_DATA = {
  '4.0': { rate:94, throws:18,  trend:[88,90,89,92,93,93,94,94] },
  '4.5': { rate:92, throws:24,  trend:[86,88,89,90,91,92,92,92] },
  '5.0': { rate:89, throws:96,  trend:[80,82,84,86,87,88,89,89] },
  '5.5': { rate:85, throws:42,  trend:[78,80,81,82,83,84,85,85] },
  '6.0': { rate:82, throws:208, trend:[74,76,77,79,80,81,82,82] },
  '6.5': { rate:74, throws:88,  trend:[68,70,71,72,73,73,74,74] },
  '7.0': { rate:71, throws:412, trend:[60,63,65,67,68,70,71,71] },
  '7.5': { rate:62, throws:124, trend:[55,56,58,59,60,61,62,62] },
  '8.0': { rate:58, throws:842, trend:[52,55,49,58,61,57,60,64] },
};

// Mock-Daten — Finisseur per Konfig (built-in + 2 user presets als Demo)
const FINIS_BUILTIN = [
  { id:'std',  c:'7 / 3',  rate:62, n:48, label:'Standard', trend:[55,57,60,58,61,62,62,62] },
  { id:'5x5',  c:'5 / 5',  rate:48, n:31, label:'5/5',      trend:[40,42,45,46,47,48,48,48] },
  { id:'all',  c:'10 / 0', rate:38, n:18, label:'10/0',     trend:[28,30,32,34,35,36,37,38] },
  { id:'late', c:'3 / 5',  rate:71, n:22, label:'Spät',     trend:[60,63,66,68,69,70,71,71] },
];

function StatsScreen({ onBack, userPresets }) {
  const [tab, setTab] = useState('8m');
  const [filterOpen, setFilterOpen] = useState(false);

  // Sniper-Filter: Set von aktiven Distanzen (als string '8.0' etc.)
  const [sniperSel, setSniperSel] = useState(() => new Set(ALL_DISTANCES.map(d => d.toFixed(1))));
  // Finisseur-Filter: Set von aktiven Preset-IDs
  const [finSel, setFinSel] = useState(() => {
    const ids = [...FINIS_BUILTIN.map(p => p.id), ...(userPresets || []).map(p => p.id)];
    return new Set(ids);
  });

  return (
    <div style={st.screen}>
      <AppBar
        eyebrow="Profil"
        title="Statistik"
        onBack={onBack}
        right={
          <button style={st.filterBtn}
                  onClick={() => setFilterOpen(true)}
                  aria-label="Filter">
            <Icon.Filter/>
          </button>
        }
      />

      {/* Tabs direkt unter AppBar */}
      <div style={st.tabs}>
        {[['8m','Sniper'],['finisseur','Finisseur']].map(([k, label]) => (
          <button key={k} style={{...st.tab, ...(k===tab ? st.tabOn : {})}}
                  onClick={() => setTab(k)}>
            {label}
          </button>
        ))}
      </div>

      {tab === '8m'
        ? <SniperStats selection={sniperSel}/>
        : <FinisseurStats selection={finSel} userPresets={userPresets || []}/>}

      {filterOpen && tab === '8m' && (
        <SniperFilterSheet
          selection={sniperSel}
          setSelection={setSniperSel}
          onClose={() => setFilterOpen(false)}/>
      )}
      {filterOpen && tab === 'finisseur' && (
        <FinisseurFilterSheet
          selection={finSel}
          setSelection={setFinSel}
          userPresets={userPresets || []}
          onClose={() => setFilterOpen(false)}/>
      )}
    </div>
  );
}

// =====================================================================
// Sniper Stats — Graph oben, dann Heros, dann Distanzliste
// =====================================================================
function SniperStats({ selection }) {
  const sel = useMemo(() => {
    return ALL_DISTANCES
      .filter(d => selection.has(d.toFixed(1)))
      .map(d => ({ d:d.toFixed(1) + ' m', key:d.toFixed(1), ...SNIPER_DATA[d.toFixed(1)] }));
  }, [selection]);

  const filtered = sel.length < ALL_DISTANCES.length;

  // Aggregate: throws-weighted hit rate
  const totals = sel.reduce((a, x) => ({
    throws: a.throws + x.throws,
    hits:   a.hits   + Math.round(x.throws * x.rate / 100),
  }), { throws:0, hits:0 });
  const overall = totals.throws ? Math.round(100 * totals.hits / totals.throws) : 0;

  // Aggregate trend: weighted average per index
  const trend = useMemo(() => {
    if (!sel.length) return [];
    const n = sel[0].trend.length;
    return Array.from({length:n}, (_, i) => {
      const w = sel.reduce((a, x) => a + x.throws, 0);
      const sum = sel.reduce((a, x) => a + x.trend[i] * x.throws, 0);
      return w ? Math.round(sum / w) : 0;
    });
  }, [sel]);

  return (
    <div style={st.body}>
      {/* GRAPH ZUERST */}
      <div style={st.graphBlock}>
        <div style={st.graphHead}>
          <span style={st.sectionHead}>Trefferrate · letzte 4 Wochen</span>
          {filtered && <span style={st.filterTag}>{sel.length} / {ALL_DISTANCES.length} Distanzen</span>}
        </div>
        {sel.length ? <Sparkline points={trend}/> : <EmptyGraph/>}
      </div>

      {sel.length === 0 ? (
        <EmptyFilter label="Keine Distanzen ausgewählt — nutze den Filter oben rechts."/>
      ) : (
        <>
          <div style={st.heroRow}>
            <Hero label="Trefferrate" value={overall} unit="%" big/>
            <Hero label="∑ Würfe"     value={totals.throws.toLocaleString('de-CH')} unit="" tone="muted"/>
          </div>

          <div style={st.sectionHead}>Pro Distanz</div>
          <div style={st.distList}>
            {sel.map(x => (
              <div key={x.key} style={st.distRow}>
                <span style={st.distLbl}>{x.d}</span>
                <div style={st.distTrack}>
                  <div style={{...st.distFill, width:`${x.rate}%`}}/>
                </div>
                <span style={st.distVal}>{x.rate}<span style={{fontSize:11, opacity:0.6}}> %</span></span>
                <span style={st.distMeta}>{x.throws}</span>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

// =====================================================================
// Finisseur Stats — Graph oben, dann Heros, dann Konfigs
// =====================================================================
function FinisseurStats({ selection, userPresets }) {
  const userRows = userPresets.map(p => ({
    id: p.id,
    c: `${p.f} / ${p.b}`,
    rate: 50 + ((p.f * 7 + p.b * 11) % 35),
    n: 6 + ((p.f + p.b) * 3) % 24,
    label: p.label,
    user: true,
    trend: [
      40 + (p.f % 20), 45 + (p.f % 18), 48 + (p.b % 12),
      50 + ((p.f+p.b) % 15), 52, 54, 55 + (p.f % 10),
      50 + ((p.f * 7 + p.b * 11) % 35),
    ],
  }));
  const all = [...FINIS_BUILTIN, ...userRows];
  const sel = all.filter(x => selection.has(x.id));
  const filtered = sel.length < all.length;

  const overall = sel.length
    ? Math.round(sel.reduce((a, x) => a + x.rate * x.n, 0) / Math.max(1, sel.reduce((a, x) => a + x.n, 0)))
    : 0;

  const trend = useMemo(() => {
    if (!sel.length) return [];
    const n = sel[0].trend.length;
    return Array.from({length:n}, (_, i) => {
      const w = sel.reduce((a, x) => a + x.n, 0);
      const sum = sel.reduce((a, x) => a + x.trend[i] * x.n, 0);
      return w ? Math.round(sum / w) : 0;
    });
  }, [sel]);

  return (
    <div style={st.body}>
      {/* GRAPH ZUERST */}
      <div style={st.graphBlock}>
        <div style={st.graphHead}>
          <span style={st.sectionHead}>Saubere Rate · letzte 4 Wochen</span>
          {filtered && <span style={st.filterTag}>{sel.length} / {all.length} Konfigs</span>}
        </div>
        {sel.length ? <Sparkline points={trend} tone="wood"/> : <EmptyGraph/>}
      </div>

      {sel.length === 0 ? (
        <EmptyFilter label="Keine Konfigs ausgewählt — nutze den Filter oben rechts."/>
      ) : (
        <>
          <div style={st.heroRow}>
            <Hero label="Saubere Rate" value={overall} unit="%" big/>
            <Hero label="∑ Sessions"   value={sel.reduce((a, x) => a + x.n, 0)} unit="" tone="muted"/>
          </div>

          <div style={st.sectionHead}>Pro Konfig</div>
          <div style={st.distList}>
            {sel.map((x, i) => (
              <div key={i} style={st.distRow}>
                <span style={st.distLbl}>
                  {x.label}
                  <span style={st.distRatio}>{x.c}</span>
                  {x.user && <span style={st.userBadge}>eigen</span>}
                </span>
                <div style={st.distTrack}>
                  <div style={{...st.distFill, width:`${x.rate}%`, background:'var(--bk-wood-400)'}}/>
                </div>
                <span style={st.distVal}>{x.rate}<span style={{fontSize:11, opacity:0.6}}> %</span></span>
                <span style={st.distMeta}>{x.n}</span>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

// =====================================================================
// Filter Sheets
// =====================================================================
function SniperFilterSheet({ selection, setSelection, onClose }) {
  const toggle = (k) => {
    const next = new Set(selection);
    next.has(k) ? next.delete(k) : next.add(k);
    setSelection(next);
  };
  const all  = () => setSelection(new Set(ALL_DISTANCES.map(d => d.toFixed(1))));
  const stamm = () => setSelection(new Set(['8.0']));   // Stamm-Distanz default
  const none = () => setSelection(new Set());

  return (
    <FilterSheet onClose={onClose} title="Distanzen filtern" eyebrow="Sniper">
      <div style={st.fQuickRow}>
        <button style={st.fQuick} onClick={all}>Alle</button>
        <button style={st.fQuick} onClick={stamm}>Stamm 8 m</button>
        <button style={st.fQuick} onClick={none}>Keine</button>
      </div>
      <div style={st.fGrid}>
        {ALL_DISTANCES.map(d => {
          const k = d.toFixed(1);
          const on = selection.has(k);
          return (
            <button key={k}
                    style={{...st.fChip, ...(on ? st.fChipOn : {})}}
                    onClick={() => toggle(k)}>
              {k} m
            </button>
          );
        })}
      </div>
      <button style={st.fApply} onClick={onClose}>Übernehmen</button>
    </FilterSheet>
  );
}

function FinisseurFilterSheet({ selection, setSelection, userPresets, onClose }) {
  const all = [...FINIS_BUILTIN, ...(userPresets || []).map(p => ({ id:p.id, label:p.label, c:`${p.f}/${p.b}`, user:true }))];
  const toggle = (id) => {
    const next = new Set(selection);
    next.has(id) ? next.delete(id) : next.add(id);
    setSelection(next);
  };
  const setAll = () => setSelection(new Set(all.map(x => x.id)));
  const setNone = () => setSelection(new Set());
  const setBuiltin = () => setSelection(new Set(FINIS_BUILTIN.map(p => p.id)));

  return (
    <FilterSheet onClose={onClose} title="Konfigs filtern" eyebrow="Finisseur">
      <div style={st.fQuickRow}>
        <button style={st.fQuick} onClick={setAll}>Alle</button>
        <button style={st.fQuick} onClick={setBuiltin}>Nur Standard</button>
        <button style={st.fQuick} onClick={setNone}>Keine</button>
      </div>
      <div style={st.fList}>
        {all.map(x => {
          const on = selection.has(x.id);
          return (
            <button key={x.id}
                    style={{...st.fListRow, ...(on ? st.fListRowOn : {})}}
                    onClick={() => toggle(x.id)}>
              <span style={st.fListLabel}>
                {x.label}
                {x.user && <span style={st.userBadge}>eigen</span>}
              </span>
              <span style={st.fListRatio}>{x.c}</span>
              <span style={{...st.fCheck, ...(on ? st.fCheckOn : {})}}>{on ? '✓' : ''}</span>
            </button>
          );
        })}
      </div>
      <button style={st.fApply} onClick={onClose}>Übernehmen</button>
    </FilterSheet>
  );
}

function FilterSheet({ children, onClose, title, eyebrow }) {
  return (
    <div style={st.sheetBackdrop} onClick={onClose}>
      <div style={st.sheet} onClick={e => e.stopPropagation()}>
        <div style={st.sheetGrabber}/>
        <div style={st.sheetHead}>
          <div>
            <div style={st.sheetEyebrow}>{eyebrow}</div>
            <h2 style={st.sheetTitle}>{title}</h2>
          </div>
          <button style={st.iconBtn} onClick={onClose} aria-label="Schliessen"><Icon.Close/></button>
        </div>
        {children}
      </div>
    </div>
  );
}

// =====================================================================
// Bits
// =====================================================================
function Hero({ label, value, unit, big, tone }) {
  const color = tone === 'wood' ? 'var(--bk-wood-500)' : tone === 'muted' ? 'var(--bk-fg)' : 'var(--bk-meadow-600)';
  return (
    <div style={st.hero}>
      <span style={st.heroLbl}>{label}</span>
      <span style={{...st.heroVal, color, fontSize: big ? 56 : 40}}>
        {value}<span style={{fontSize: big ? 22 : 16, fontWeight:600, color:'var(--bk-fg-muted)', marginLeft:2}}>{unit}</span>
      </span>
    </div>
  );
}

function Sparkline({ points, tone }) {
  const w = 320, h = 96, pad = 6;
  const min = Math.min(...points), max = Math.max(...points);
  const xs = points.map((_, i) => pad + (i*(w-2*pad))/(points.length-1));
  const ys = points.map(p => h - pad - ((p-min)/(max-min || 1))*(h-2*pad));
  const path = points.map((_, i) => `${i?'L':'M'}${xs[i]},${ys[i]}`).join(' ');
  const stroke = tone === 'wood' ? 'var(--bk-wood-500)' : 'var(--bk-meadow-600)';
  const fill   = tone === 'wood' ? 'var(--bk-wood-100)' : 'var(--bk-meadow-100)';
  return (
    <div style={st.spark}>
      <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} preserveAspectRatio="none">
        <path d={`${path} L ${xs[xs.length-1]},${h} L ${xs[0]},${h} Z`} fill={fill}/>
        <path d={path} fill="none" stroke={stroke} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round"/>
        <circle cx={xs[xs.length-1]} cy={ys[ys.length-1]} r="4" fill={stroke}/>
      </svg>
      <div style={st.sparkRow}>
        <span>vor 4 W</span>
        <span style={{fontWeight:700, color:'var(--bk-fg)'}}>{points[points.length-1]} %</span>
        <span>heute</span>
      </div>
    </div>
  );
}

function EmptyGraph() {
  return (
    <div style={{...st.spark, textAlign:'center', color:'var(--bk-fg-muted)', fontSize:13, padding:'24px 12px'}}>
      Keine Daten — bitte mindestens eine Auswahl im Filter aktivieren.
    </div>
  );
}

function EmptyFilter({ label }) {
  return (
    <div style={st.emptyFilter}>
      <Icon.Filter/>
      <span>{label}</span>
    </div>
  );
}

const st = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflowY:'auto', paddingBottom:24 },
  filterBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },
  iconBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },

  tabs: { display:'flex', gap:6, background:'var(--bk-bg-sunken)', margin:'0 16px 14px', borderRadius:999, padding:4 },
  tab: { flex:1, minHeight:44, border:0, borderRadius:999, background:'transparent', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:14, cursor:'pointer' },
  tabOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)' },

  body: { padding:'0 16px 18px', display:'flex', flexDirection:'column', gap:14 },

  graphBlock: { display:'flex', flexDirection:'column', gap:6 },
  graphHead: { display:'flex', justifyContent:'space-between', alignItems:'baseline', gap:10 },
  filterTag: { fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-meadow-600)', background:'var(--bk-meadow-100)', padding:'2px 8px', borderRadius:999, letterSpacing:'0.04em', fontWeight:600 },

  heroRow: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:10 },
  hero: { background:'var(--bk-bg-raised)', borderRadius:16, padding:'12px 14px', display:'flex', flexDirection:'column', gap:2 },
  heroLbl: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  heroVal: { fontFamily:'var(--bk-font-display)', fontWeight:800, lineHeight:1, letterSpacing:'-0.03em', fontVariantNumeric:'tabular-nums' },

  sectionHead: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', marginTop:6 },

  distList: { display:'flex', flexDirection:'column', gap:6, background:'var(--bk-bg-raised)', borderRadius:14, padding:'10px 12px' },
  distRow: { display:'grid', gridTemplateColumns:'minmax(96px, 1fr) 1.2fr 56px 36px', gap:10, alignItems:'center', padding:'4px 0' },
  distLbl: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:13, display:'flex', alignItems:'center', gap:6, flexWrap:'wrap' },
  distRatio: { fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-fg-muted)', letterSpacing:'0.04em' },
  userBadge: { fontFamily:'var(--bk-font-mono)', fontSize:9, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--bk-meadow-600)', background:'var(--bk-meadow-100)', padding:'1px 5px', borderRadius:4 },
  distTrack: { height:8, background:'var(--bk-stone-100)', borderRadius:999, overflow:'hidden' },
  distFill: { height:'100%', background:'var(--bk-meadow-500)', borderRadius:999 },
  distVal: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:16, textAlign:'right', fontVariantNumeric:'tabular-nums' },
  distMeta: { fontFamily:'var(--bk-font-mono)', fontSize:11, color:'var(--bk-fg-muted)', textAlign:'right' },

  spark: { background:'var(--bk-bg-raised)', borderRadius:14, padding:'10px 12px' },
  sparkRow: { display:'flex', justifyContent:'space-between', alignItems:'baseline', fontFamily:'var(--bk-font-mono)', fontSize:11, color:'var(--bk-fg-muted)', marginTop:4 },

  emptyFilter: { display:'flex', alignItems:'center', justifyContent:'center', gap:10, color:'var(--bk-fg-muted)', fontSize:13, padding:'14px 12px', background:'var(--bk-bg-raised)', borderRadius:12 },

  // Filter sheet
  sheetBackdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.55)', display:'flex', alignItems:'flex-end', zIndex:30 },
  sheet: { width:'100%', maxHeight:'92%', overflowY:'auto', background:'var(--bk-bg)', borderTopLeftRadius:24, borderTopRightRadius:24, padding:'10px 18px 28px', display:'flex', flexDirection:'column', gap:12 },
  sheetGrabber: { width:36, height:4, background:'var(--bk-stone-200)', borderRadius:999, alignSelf:'center', marginBottom:6 },
  sheetHead: { display:'flex', alignItems:'flex-start', justifyContent:'space-between', marginBottom:2 },
  sheetEyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  sheetTitle: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:22, margin:0, letterSpacing:'-0.02em' },

  fQuickRow: { display:'flex', gap:6, flexWrap:'wrap' },
  fQuick: { minHeight:36, padding:'0 12px', borderRadius:999, border:0, background:'var(--bk-bg-sunken)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:13, cursor:'pointer' },

  fGrid: { display:'grid', gridTemplateColumns:'repeat(3, 1fr)', gap:8 },
  fChip: { minHeight:48, padding:'0 6px', borderRadius:12, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 1.5px var(--bk-line)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:14, cursor:'pointer', fontVariantNumeric:'tabular-nums' },
  fChipOn: { background:'var(--bk-meadow-500)', color:'#fff', boxShadow:'none' },

  fList: { display:'flex', flexDirection:'column', gap:6 },
  fListRow: { display:'grid', gridTemplateColumns:'1fr auto 28px', gap:10, alignItems:'center', minHeight:54, padding:'8px 14px', borderRadius:12, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 1.5px var(--bk-line)', fontFamily:'var(--bk-font-display)', textAlign:'left', cursor:'pointer' },
  fListRowOn: { background:'var(--bk-meadow-100)', boxShadow:'inset 0 0 0 1.5px var(--bk-meadow-500)' },
  fListLabel: { fontWeight:700, fontSize:14, display:'flex', alignItems:'center', gap:6 },
  fListRatio: { fontFamily:'var(--bk-font-mono)', fontSize:12, color:'var(--bk-fg-muted)' },
  fCheck: { width:24, height:24, borderRadius:6, border:'1.5px solid var(--bk-line-strong)', display:'inline-grid', placeItems:'center', fontSize:14, fontWeight:800 },
  fCheckOn: { background:'var(--bk-meadow-500)', borderColor:'var(--bk-meadow-500)', color:'#fff' },

  fApply: { marginTop:6, minHeight:54, borderRadius:14, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer' },
};

window.StatsScreen = StatsScreen;
