/* global React */
// =====================================================================
// CsvExportModal — Daten-Export für Desktop.
//   Modal mit Zeitraum, Mode-Filter, Spalten-Auswahl und Vorschau.
//   Pendant zur mobilen CsvExportModal (Bottom-Sheet).
// =====================================================================

const { useState: useCsvState } = React;

function CsvExportModal({ onClose }) {
  const [range, setRange]   = useCsvState('all');
  const [modes, setModes]   = useCsvState({ sniper:true, finisseur:true, match:true });
  const [cols, setCols]     = useCsvState({ basics:true, location:false, helitrack:true, partner:false });

  const sessionCounts = { sniper:187, finisseur:119, match:46 };
  const total = (modes.sniper ? sessionCounts.sniper : 0)
              + (modes.finisseur ? sessionCounts.finisseur : 0)
              + (modes.match ? sessionCounts.match : 0);
  const filename = `kubbclub_${range === 'all' ? 'alle' : range}_${new Date().toISOString().slice(0,10)}.csv`;

  return (
    <div style={ex.backdrop} onClick={onClose}>
      <div style={ex.modal} onClick={e => e.stopPropagation()}>
        <header style={ex.head}>
          <div>
            <div style={ex.eyebrow}>Daten</div>
            <h2 style={ex.title}>CSV-Export</h2>
          </div>
          <button style={ex.close} onClick={onClose}>×</button>
        </header>

        <div style={ex.body}>
          <div style={ex.left}>
            <div style={ex.section}>Zeitraum</div>
            <div style={ex.chipRow}>
              {[['all','Alle'],['30','30 Tage'],['90','90 Tage'],['year','Saison 2025'],['custom','Eigen…']].map(([k, lbl]) => (
                <button key={k} style={{...ex.chip, ...(range === k ? ex.chipOn : {})}} onClick={() => setRange(k)}>
                  {lbl}
                </button>
              ))}
            </div>

            <div style={ex.section}>Modi</div>
            <div style={ex.checks}>
              <Check label="Sniper-Training" sub={`${sessionCounts.sniper} Sessions · 7'420 Würfe`}
                     on={modes.sniper} onChange={v => setModes({...modes, sniper:v})}/>
              <Check label="Finisseur"       sub={`${sessionCounts.finisseur} Sessions · 5 Konfigurationen`}
                     on={modes.finisseur} onChange={v => setModes({...modes, finisseur:v})}/>
              <Check label="Match (Live)"    sub={`${sessionCounts.match} Spiele · 3 Turniere`}
                     on={modes.match} onChange={v => setModes({...modes, match:v})}/>
            </div>

            <div style={ex.section}>Spalten</div>
            <div style={ex.colsGrid}>
              <ColChip label="Basis (Datum, Quote, Würfe)" on={cols.basics} onChange={v => setCols({...cols, basics:v})}/>
              <ColChip label="Helikopter-Tracking" on={cols.helitrack} onChange={v => setCols({...cols, helitrack:v})}/>
              <ColChip label="Standort & Pitch" on={cols.location} onChange={v => setCols({...cols, location:v})}/>
              <ColChip label="Partner / Gegner" on={cols.partner} onChange={v => setCols({...cols, partner:v})}/>
            </div>
          </div>

          <div style={ex.right}>
            <div style={ex.section}>Vorschau</div>
            <div style={ex.preview}>
              <div style={ex.previewHead}>
                <span style={ex.previewFile}>{filename}</span>
                <span style={ex.previewMeta}>{total} Sessions · ~{Math.max(2, Math.round(total * 0.4))} kB</span>
              </div>
              <pre style={ex.code}>{
`datum,modus,distanz,würfe,treffer,${cols.helitrack ? 'heli,' : ''}ergebnis
2025-05-24,sniper,8.0,36,23,${cols.helitrack ? '1,' : ''}
2025-05-23,finisseur,7/3,5,4,${cols.helitrack ? '0,' : ''}sauber
2025-05-22,finisseur,5/5,6,3,${cols.helitrack ? '0,' : ''}verfehlt
2025-05-21,match,—,28,18,${cols.helitrack ? '4,' : ''}3:2 vs United A
2025-05-20,sniper,6.5,24,17,${cols.helitrack ? '0,' : ''}
…  (${total - 5} weitere Zeilen)`
              }</pre>
            </div>

            <div style={ex.meta}>
              <MetaRow label="Encoding"     value="UTF-8 mit BOM"/>
              <MetaRow label="Trennzeichen" value="," />
              <MetaRow label="Dezimal"      value="." />
              <MetaRow label="Datum"        value="ISO 8601" />
            </div>
          </div>
        </div>

        <footer style={ex.footer}>
          <button style={ex.cancel} onClick={onClose}>Abbrechen</button>
          <button style={ex.primary} onClick={onClose}>
            <span>↓</span>
            <span>{filename} herunterladen</span>
          </button>
        </footer>
      </div>
    </div>
  );
}

function Check({ label, sub, on, onChange }) {
  return (
    <button style={{...ex.check, ...(on ? ex.checkOn : {})}} onClick={() => onChange(!on)}>
      <span style={{...ex.checkBox, ...(on ? ex.checkBoxOn : {})}}>
        {on && '✓'}
      </span>
      <span style={{flex:1, minWidth:0}}>
        <span style={ex.checkLbl}>{label}</span>
        <span style={ex.checkSub}>{sub}</span>
      </span>
    </button>
  );
}

function ColChip({ label, on, onChange }) {
  return (
    <button style={{...ex.colChip, ...(on ? ex.colChipOn : {})}} onClick={() => onChange(!on)}>
      <span style={{...ex.colBox, ...(on ? ex.colBoxOn : {})}}>{on && '✓'}</span>
      <span>{label}</span>
    </button>
  );
}

function MetaRow({ label, value }) {
  return (
    <div style={ex.metaRow}>
      <span style={ex.metaLbl}>{label}</span>
      <span style={ex.metaVal}>{value}</span>
    </div>
  );
}

const ex = {
  backdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.55)', display:'grid', placeItems:'center', zIndex:40 },
  modal: { width:880, maxWidth:'94vw', maxHeight:'94vh', background:'var(--kc-bg-raised)', borderRadius:18, boxShadow:'var(--kc-shadow-4)', display:'flex', flexDirection:'column', overflow:'hidden' },
  head: { display:'flex', alignItems:'flex-start', justifyContent:'space-between', padding:'22px 28px 14px', borderBottom:'1px solid var(--kc-line)' },
  eyebrow: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  title: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:26, letterSpacing:'-0.02em', margin:'2px 0 0', fontVariationSettings:'"opsz" 72' },
  close: { width:36, height:36, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontSize:24, cursor:'pointer', lineHeight:1 },

  body: { display:'grid', gridTemplateColumns:'1.1fr 1fr', gap:24, padding:'18px 28px 18px', overflowY:'auto', flex:1 },
  left: { display:'flex', flexDirection:'column', minWidth:0 },
  right: { display:'flex', flexDirection:'column', minWidth:0 },

  section: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)', padding:'10px 0 8px' },

  chipRow: { display:'flex', gap:6, flexWrap:'wrap' },
  chip: { minHeight:38, padding:'0 14px', borderRadius:999, border:0, background:'var(--kc-bg-sunken)', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer', boxShadow:'inset 0 0 0 1.5px transparent' },
  chipOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  checks: { display:'flex', flexDirection:'column', gap:8 },
  check: { display:'flex', alignItems:'center', gap:12, padding:'12px 14px', background:'var(--kc-bg-sunken)', borderRadius:12, border:0, cursor:'pointer', textAlign:'left', color:'var(--kc-fg)', boxShadow:'inset 0 0 0 1.5px transparent' },
  checkOn: { boxShadow:'inset 0 0 0 1.5px var(--kc-meadow-500)' },
  checkBox: { width:22, height:22, borderRadius:6, background:'transparent', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-300)', display:'grid', placeItems:'center', flexShrink:0, fontSize:13, fontWeight:800, color:'#fff' },
  checkBoxOn: { background:'var(--kc-meadow-500)', boxShadow:'none' },
  checkLbl: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14, display:'block' },
  checkSub: { fontSize:12, color:'var(--kc-fg-muted)', display:'block', marginTop:2 },

  colsGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:6 },
  colChip: { display:'flex', alignItems:'center', gap:8, padding:'10px 12px', background:'var(--kc-bg-sunken)', border:0, borderRadius:10, cursor:'pointer', textAlign:'left', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:12, boxShadow:'inset 0 0 0 1.5px transparent' },
  colChipOn: { boxShadow:'inset 0 0 0 1.5px var(--kc-meadow-500)' },
  colBox: { width:18, height:18, borderRadius:4, background:'transparent', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-300)', display:'grid', placeItems:'center', flexShrink:0, fontSize:11, fontWeight:800, color:'#fff' },
  colBoxOn: { background:'var(--kc-meadow-500)', boxShadow:'none' },

  preview: { background:'var(--kc-stone-900)', borderRadius:12, padding:'14px 16px', minHeight:240, display:'flex', flexDirection:'column', gap:10 },
  previewHead: { display:'flex', justifyContent:'space-between', alignItems:'baseline', gap:10, paddingBottom:8, borderBottom:'1px solid rgba(255,255,255,0.15)' },
  previewFile: { fontFamily:'var(--kc-font-mono)', fontSize:12, color:'var(--kc-chalk-50)', letterSpacing:'0.02em', overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' },
  previewMeta: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-stone-300)', letterSpacing:'0.04em', whiteSpace:'nowrap' },
  code: { fontFamily:'var(--kc-font-mono)', fontSize:11.5, color:'var(--kc-meadow-200)', margin:0, whiteSpace:'pre', overflowX:'auto', lineHeight:1.7, flex:1 },

  meta: { marginTop:14, padding:'12px 16px', borderRadius:12, background:'var(--kc-bg-sunken)', display:'flex', flexDirection:'column', gap:0 },
  metaRow: { display:'flex', justifyContent:'space-between', padding:'7px 0', borderTop:'1px solid var(--kc-line)' },
  metaLbl: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.04em' },
  metaVal: { fontFamily:'var(--kc-font-mono)', fontSize:12, color:'var(--kc-fg)', fontWeight:600 },

  footer: { display:'flex', justifyContent:'flex-end', gap:10, padding:'16px 28px 22px', borderTop:'1px solid var(--kc-line)' },
  cancel: { padding:'0 18px', height:44, borderRadius:12, border:0, background:'transparent', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:14, cursor:'pointer', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-200)' },
  primary: { display:'inline-flex', alignItems:'center', gap:8, padding:'0 22px', height:44, borderRadius:12, border:0, background:'var(--kc-meadow-600)', color:'#fff', fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14, cursor:'pointer', boxShadow:'var(--kc-shadow-1)' },
};

window.CsvExportModal = CsvExportModal;
