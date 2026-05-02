/* global React, BK */
const { useState } = React;
const { Icon } = BK;

// =====================================================================
// Screen: Finisseur — Konfiguration
// =====================================================================
const BUILTIN_PRESETS = [
  { id:'std',  label:'Standard', f:7, b:3, builtin:true },
  { id:'5x5',  label:'5/5',      f:5, b:5, builtin:true },
  { id:'all',  label:'10/0',     f:10, b:0, builtin:true },
  { id:'late', label:'Spät',     f:3, b:5, builtin:true },
];

function FinisseurConfigScreen({ onBack, onStart }) {
  const [field, setField] = useState(7);
  const [base, setBase]   = useState(3);
  const [userPresets, setUserPresets] = useState([
    { id:'p-clean', label:'Sauber', f:6, b:4 },
  ]);
  const [savePromptOpen, setSavePromptOpen] = useState(false);

  // Constraints:
  //  - field + base ≤ 10 (10 Kubbs total im Spiel)
  //  - base ≤ 5 (max. 5 Basiskubbs)
  //  - daher: maxBase = min(5, 10 − field), maxField = 10 (base wird ggf. angepasst)
  const TOTAL_MAX = 10;
  const BASE_HARD = 5;
  const maxBase  = Math.max(0, Math.min(BASE_HARD, TOTAL_MAX - field));
  const maxField = TOTAL_MAX;

  // Wenn Feldkubbs erhöht werden → Basis ggf. nach unten klemmen
  const setFieldClamped = (v) => {
    const nf = Math.max(0, Math.min(maxField, v));
    setField(nf);
    const nbMax = Math.min(BASE_HARD, TOTAL_MAX - nf);
    if (base > nbMax) setBase(Math.max(0, nbMax));
  };
  const setBaseClamped = (v) => setBase(Math.max(0, Math.min(maxBase, v)));

  const presets = [...BUILTIN_PRESETS, ...userPresets];
  const matchesExisting = presets.some(p => p.f === field && p.b === base);

  const removePreset = (id) => setUserPresets(list => list.filter(p => p.id !== id));
  const addPreset = (label) => {
    const trimmed = (label || '').trim() || `${field}/${base}`;
    setUserPresets(list => [...list, { id:'p-'+Date.now(), label:trimmed, f:field, b:base }]);
    setSavePromptOpen(false);
  };

  return (
    <div style={c.screen}>
      <header style={c.topbar}>
        <button style={c.iconBtn} onClick={onBack}><Icon.Back/></button>
        <div style={c.topTitle}>
          <div style={c.topEyebrow}>Finisseur</div>
          <div style={c.topName}>Konfiguration</div>
        </div>
        <div style={{width:48}}/>
      </header>

      {/* Visual stack representation */}
      <div style={c.preview}>
        <div style={c.previewRow}>
          {Array.from({length: field}).map((_, i) =>
            <div key={i} style={c.kubbField}/>
          )}
        </div>
        <div style={c.pitchLine}/>
        <div style={c.previewRow}>
          {Array.from({length: base}).map((_, i) =>
            <div key={i} style={c.kubbBase}/>
          )}
        </div>
        <div style={c.previewLabel}>{field} / {base}  ·  6 Stöcke</div>
      </div>

      {/* Stepper: Feldkubbs */}
      <Stepper label="Feldkubbs (eingeworfen)"
               value={field} setValue={setFieldClamped} min={0} max={maxField}/>
      <Stepper label={`Basiskubbs  ·  max ${maxBase}`}
               value={base} setValue={setBaseClamped} min={0} max={maxBase} accent="wood"/>
      <div style={c.constraintNote}>
        Total maximal {TOTAL_MAX} Kubbs &middot; Basis maximal {BASE_HARD}.
        Aktuell <b>{field + base} / {TOTAL_MAX}</b>.
      </div>

      {/* Presets */}
      <div style={c.presetBlock}>
        <div style={c.presetHead}>
          <span style={c.presetEyebrow}>Presets</span>
          {!matchesExisting && (
            <button style={c.savePill} onClick={() => setSavePromptOpen(true)}>
              <Icon.Plus2/> Speichern
            </button>
          )}
        </div>
        <div style={c.presetRow}>
          {presets.map(p => {
            const on = p.f === field && p.b === base;
            return (
              <div key={p.id} style={c.presetWrap}>
                <button style={{...c.preset, ...(on ? c.presetOn : {})}}
                        onClick={() => { setField(p.f); setBase(p.b); }}>
                  <span style={c.presetLabel}>{p.label}</span>
                  <span style={{...c.presetRatio, color: on ? 'rgba(255,255,255,0.75)' : 'var(--bk-fg-muted)'}}>{p.f}/{p.b}</span>
                </button>
                {!p.builtin && (
                  <button style={c.presetRemove}
                          onClick={(e) => { e.stopPropagation(); removePreset(p.id); }}
                          aria-label={`Preset ${p.label} entfernen`}>
                    <Icon.Close/>
                  </button>
                )}
              </div>
            );
          })}
        </div>
      </div>

      <button style={c.startBtn} onClick={() => onStart({ field, base })}>
        Finisseur starten
      </button>

      {savePromptOpen && (
        <SavePresetSheet f={field} b={base}
                         onCancel={() => setSavePromptOpen(false)}
                         onSave={addPreset}/>
      )}
    </div>
  );
}

function SavePresetSheet({ f, b, onCancel, onSave }) {
  const [name, setName] = useState('');
  return (
    <div style={c.sheetBackdrop} onClick={onCancel}>
      <div style={c.sheet} onClick={e => e.stopPropagation()}>
        <div style={c.sheetGrabber}/>
        <div style={c.sheetHead}>
          <div>
            <div style={c.topEyebrow}>Preset speichern</div>
            <h2 style={c.sheetTitle}>{f} / {b}</h2>
          </div>
          <button style={c.iconBtn} onClick={onCancel} aria-label="Abbrechen"><Icon.Close/></button>
        </div>
        <label style={{display:'flex', flexDirection:'column', gap:6, marginTop:4}}>
          <span style={c.stepperLabel}>Name</span>
          <input type="text" value={name} autoFocus
                 onChange={e => setName(e.target.value)}
                 placeholder={`z.\u202fB. Heim-Setup`}
                 style={c.input}/>
        </label>
        <div style={c.sheetActions}>
          <button style={c.cancelBtn} onClick={onCancel}>Abbrechen</button>
          <button style={c.saveBtn} onClick={() => onSave(name)}>Speichern</button>
        </div>
      </div>
    </div>
  );
}

function Stepper({ label, value, setValue, min, max, accent }) {
  const ringColor = accent === 'wood' ? 'var(--bk-wood-400)' : 'var(--bk-meadow-500)';
  return (
    <div style={c.stepper}>
      <div style={c.stepperHead}>
        <span style={c.stepperLabel}>{label}</span>
        <span style={c.stepperRange}>{min}–{max}</span>
      </div>
      <div style={c.stepperRow}>
        <button style={c.stepBtn} onClick={() => setValue(Math.max(min, value-1))}>
          <Icon.Minus/>
        </button>
        <div style={{...c.stepValue, boxShadow: `inset 0 0 0 2px ${ringColor}`}}>
          {value}
        </div>
        <button style={c.stepBtn} onClick={() => setValue(Math.min(max, value+1))}>
          <Icon.Plus/>
        </button>
      </div>
    </div>
  );
}

const c = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflowY:'auto', paddingBottom:8 },
  topbar: { display:'flex', alignItems:'center', justifyContent:'space-between', padding:'54px 12px 6px' },
  iconBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },
  topTitle: { textAlign:'center' },
  topEyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  topName: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:20, letterSpacing:'-0.02em' },

  preview: { padding:'14px 16px 10px', display:'flex', flexDirection:'column', alignItems:'center', gap:10, background:'var(--bk-bg-raised)', margin:'8px 16px 14px', borderRadius:16, paddingBottom:14 },
  previewRow: { display:'flex', flexWrap:'wrap', gap:5, justifyContent:'center', minHeight:30 },
  kubbField: { width:14, height:24, background:'var(--bk-wood-400)', borderTop:'2px solid var(--bk-wood-600)', borderRadius:2 },
  kubbBase:  { width:18, height:32, background:'var(--bk-wood-300)', borderTop:'2px solid var(--bk-wood-500)', borderRadius:2 },
  pitchLine: { width:'80%', height:2, background:'var(--bk-line-strong)', margin:'4px 0' },
  previewLabel: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:18, letterSpacing:'-0.02em', color:'var(--bk-fg-muted)', marginTop:2 },

  stepper: { padding:'10px 16px' },
  stepperHead: { display:'flex', justifyContent:'space-between', marginBottom:8 },
  stepperLabel: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  stepperRange: { fontFamily:'var(--bk-font-mono)', fontSize:11, color:'var(--bk-fg-subtle)' },
  stepperRow: { display:'grid', gridTemplateColumns:'64px 1fr 64px', gap:10, alignItems:'stretch' },
  stepBtn: { minHeight:64, borderRadius:14, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 2px var(--bk-line)', display:'grid', placeItems:'center', cursor:'pointer' },
  stepValue: { background:'var(--bk-bg-raised)', borderRadius:14, display:'grid', placeItems:'center', fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:36, fontVariantNumeric:'tabular-nums' },

  presetBlock: { padding:'4px 16px 14px' },
  presetHead: { display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:8 },
  presetEyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  savePill: { minHeight:36, padding:'0 12px', borderRadius:999, border:0, background:'transparent', boxShadow:'inset 0 0 0 1.5px var(--bk-line-strong)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:13, cursor:'pointer', display:'inline-flex', alignItems:'center', gap:4 },
  presetRow: { display:'flex', gap:8, flexWrap:'wrap', alignItems:'center' },
  presetWrap: { position:'relative', display:'flex' },
  preset: { minHeight:48, padding:'8px 16px 8px 14px', borderRadius:14, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', cursor:'pointer', display:'flex', flexDirection:'column', alignItems:'flex-start', lineHeight:1.1, gap:2, boxShadow:'inset 0 0 0 1.5px var(--bk-line)' },
  presetOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)', boxShadow:'none' },
  presetLabel: { fontSize:13, fontWeight:600 },
  presetRatio: { fontSize:11, fontFamily:'var(--bk-font-mono)', letterSpacing:'0.04em' },
  presetRemove: { position:'absolute', top:-6, right:-6, width:22, height:22, borderRadius:'50%', border:0, background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)', display:'grid', placeItems:'center', cursor:'pointer', boxShadow:'0 1px 2px rgba(0,0,0,0.2)' },

  // Save-preset sheet
  sheetBackdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.45)', display:'flex', alignItems:'flex-end', zIndex:10 },
  sheet: { width:'100%', background:'var(--bk-bg-raised)', borderTopLeftRadius:24, borderTopRightRadius:24, padding:'10px 18px 32px', display:'flex', flexDirection:'column', gap:10 },
  sheetGrabber: { width:36, height:4, background:'var(--bk-stone-200)', borderRadius:999, alignSelf:'center', marginBottom:6 },
  sheetHead: { display:'flex', alignItems:'flex-start', justifyContent:'space-between' },
  sheetTitle: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:24, margin:0, letterSpacing:'-0.02em' },
  input: { minHeight:48, padding:'0 14px', borderRadius:12, border:'1.5px solid var(--bk-line-strong)', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', fontSize:16, outline:'none' },
  sheetActions: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:10, marginTop:6 },
  cancelBtn: { minHeight:54, borderRadius:14, border:0, background:'var(--bk-bg-sunken)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:16, cursor:'pointer' },
  saveBtn:   { minHeight:54, borderRadius:14, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer' },

  startBtn: { margin:'auto 16px 28px', minHeight:60, borderRadius:16, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:18, cursor:'pointer' },
  constraintNote: { padding:'2px 18px 6px', fontSize:11, color:'var(--bk-fg-muted)', fontFamily:'var(--bk-font-mono)', letterSpacing:'0.02em' },
};

window.FinisseurConfigScreen = FinisseurConfigScreen;
