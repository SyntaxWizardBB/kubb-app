/* global React, BK */
const { useState } = React;
const { Icon } = BK;

// =====================================================================
// Modal: CSV-Export
//   - Picks date range, mode filter, then triggers download.
// =====================================================================
function CsvExportModal({ onClose }) {
  const [range, setRange] = useState('all');
  const [modes, setModes] = useState({ sniper:true, finisseur:true });
  const total = (modes.sniper ? 187 : 0) + (modes.finisseur ? 119 : 0);

  return (
    <div style={x.backdrop} onClick={onClose}>
      <div style={x.sheet} onClick={e => e.stopPropagation()}>
        <div style={x.grabber}/>
        <div style={x.head}>
          <div>
            <div style={x.eyebrow}>Daten</div>
            <h2 style={x.title}>CSV-Export</h2>
          </div>
          <button style={x.iconBtn} onClick={onClose} aria-label="Schliessen"><Icon.Close/></button>
        </div>

        <div style={x.section}>Zeitraum</div>
        <div style={x.chipRow}>
          {[['all','Alle'],['30','30 Tage'],['90','90 Tage'],['year','Jahr']].map(([k,lbl]) => (
            <button key={k} style={{...x.chip, ...(range===k ? x.chipOn : {})}} onClick={() => setRange(k)}>
              {lbl}
            </button>
          ))}
        </div>

        <div style={x.section}>Modi</div>
        <div style={x.checks}>
          <Check label="Sniper-Training" sub="187 Sessions" on={modes.sniper}
                 onChange={v => setModes({...modes, sniper:v})}/>
          <Check label="Finisseur" sub="119 Sessions" on={modes.finisseur}
                 onChange={v => setModes({...modes, finisseur:v})}/>
        </div>

        <div style={x.preview}>
          <div style={x.previewHead}>Vorschau · sessions.csv</div>
          <pre style={x.code}>{
`datum,modus,distanz,würfe,treffer,heli,ergebnis
2024-08-21,sniper,8.0,36,23,1,
2024-08-20,finisseur,7/3,5,4,0,sauber
2024-08-19,finisseur,5/5,6,3,0,verfehlt
…`
          }</pre>
          <div style={x.previewMeta}>{total} Sessions · ~{Math.max(2, Math.round(total*0.4))} kB</div>
        </div>

        <button style={x.dlBtn} onClick={onClose}>
          <Icon.Download/>
          <span>Herunterladen</span>
        </button>
      </div>
    </div>
  );
}

function Check({ label, sub, on, onChange }) {
  return (
    <button style={{...x.check, ...(on ? x.checkOn : {})}} onClick={() => onChange(!on)}>
      <span style={{...x.checkBox, ...(on ? x.checkBoxOn : {})}}>
        {on && <Icon.Check/>}
      </span>
      <span style={x.checkText}>
        <span style={x.checkLbl}>{label}</span>
        <span style={x.checkSub}>{sub}</span>
      </span>
    </button>
  );
}

const x = {
  backdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.55)', display:'flex', alignItems:'flex-end', zIndex:20 },
  sheet: { width:'100%', maxHeight:'92%', overflowY:'auto', background:'var(--bk-bg)', borderTopLeftRadius:24, borderTopRightRadius:24, padding:'10px 0 40px', display:'flex', flexDirection:'column' },
  grabber: { width:36, height:4, background:'var(--bk-stone-200)', borderRadius:999, alignSelf:'center', marginBottom:6 },
  head: { display:'flex', alignItems:'flex-start', justifyContent:'space-between', padding:'4px 18px 12px' },
  eyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  title: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:24, margin:0, letterSpacing:'-0.02em' },
  iconBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },

  section: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', padding:'8px 18px 8px' },

  chipRow: { display:'flex', gap:8, padding:'0 16px 6px', flexWrap:'wrap' },
  chip: { minHeight:40, padding:'0 16px', borderRadius:999, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:13, cursor:'pointer', boxShadow:'inset 0 0 0 1.5px var(--bk-line)' },
  chipOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)', boxShadow:'none' },

  checks: { display:'flex', flexDirection:'column', gap:8, padding:'0 16px 6px' },
  check: { display:'flex', alignItems:'center', gap:12, padding:'12px 14px', minHeight:60, background:'var(--bk-bg-raised)', borderRadius:14, border:0, boxShadow:'inset 0 0 0 1.5px var(--bk-line)', cursor:'pointer', textAlign:'left', color:'var(--bk-fg)' },
  checkOn: { boxShadow:'inset 0 0 0 2px var(--bk-meadow-500)' },
  checkBox: { width:24, height:24, borderRadius:6, background:'transparent', boxShadow:'inset 0 0 0 2px var(--bk-line-strong)', display:'grid', placeItems:'center', flexShrink:0, color:'#fff' },
  checkBoxOn: { background:'var(--bk-meadow-500)', boxShadow:'none' },
  checkText: { display:'flex', flexDirection:'column', gap:1 },
  checkLbl: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:15 },
  checkSub: { fontSize:12, color:'var(--bk-fg-muted)' },

  preview: { margin:'8px 16px 6px', background:'var(--bk-bg-sunken)', borderRadius:12, padding:'10px 12px' },
  previewHead: { fontFamily:'var(--bk-font-mono)', fontSize:11, color:'var(--bk-fg-muted)', marginBottom:6, letterSpacing:'0.04em' },
  code: { fontFamily:'var(--bk-font-mono)', fontSize:11, color:'var(--bk-fg)', margin:0, whiteSpace:'pre', overflow:'auto', lineHeight:1.5 },
  previewMeta: { fontFamily:'var(--bk-font-mono)', fontSize:11, color:'var(--bk-fg-muted)', marginTop:6 },

  dlBtn: { margin:'14px 16px 0', minHeight:54, borderRadius:14, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer', display:'flex', alignItems:'center', justifyContent:'center', gap:10 },
};

window.CsvExportModal = CsvExportModal;
