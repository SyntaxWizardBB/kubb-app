/* global React, BK */
const { useState, useMemo } = React;
const { Icon, AppBar } = BK;

// =====================================================================
// Screen: Finisseur — Per-Stick Eingabe
//   - Helikopter blendet andere Optionen NICHT aus (gleichzeitig wählbar
//     ist nicht möglich, aber sie bleiben sichtbar)
//   - Feldkubb-Auswahl ist dynamisch: max = remaining (kann nicht mehr
//     umwerfen als noch stehen)
//   - Strafkubb wird als Anzahl gewählt (0/1/2). 2 = "Strafkubb 2x"
//     (zweiter Strafkubb gesetzt und gleich wieder draussen)
//   - 8m-Treffer (Basis) erscheint nur wenn remBase>0 (logisch möglich)
//   - Königswurf erscheint nur am letzten möglichen Stock
//     (alle Feld + Basis = umgeworfen ODER letzter Stock im Set)
// =====================================================================
function FinisseurStickScreen({ config = {field:7, base:3}, onBack, onFinish }) {
  const empty = () => ({ field:0, eightM:false, p1:0, p2:0, heli:false, king:null });
  const [sticks, setSticks] = useState(Array.from({length:6}, empty));
  const [current, setCurrent] = useState(0);

  // Aggregate prior sticks (everything BEFORE current)
  const prior = sticks.slice(0, current);
  const fieldDownPrior = prior.reduce((a, s) => a + s.field, 0);
  const baseDownPrior  = prior.reduce((a, s) => a + (s.eightM ? 1 : 0), 0);
  const remFieldBefore = Math.max(0, config.field - fieldDownPrior);
  const remBaseBefore  = Math.max(0, config.base  - baseDownPrior);

  // Total down (incl. current stick)
  const fieldDown = sticks.reduce((a, s) => a + s.field, 0);
  const baseDown  = sticks.reduce((a, s) => a + (s.eightM ? 1 : 0), 0);
  const remField  = Math.max(0, config.field - fieldDown);
  const remBase   = Math.max(0, config.base  - baseDown);

  const stick = sticks[current];

  const update = (patch) => {
    setSticks(prev => prev.map((s, i) => i === current ? { ...s, ...patch } : s));
  };
  const setHeli = (on) => {
    if (on) update({ heli:true, field:0, eightM:false, p1:0, p2:0, king:null });
    else update({ heli:false });
  };

  // Derived: is logical 8m / König possible RIGHT NOW for this stick?
  // 8m possible when there are still base kubbs upright (before this stick's eightM toggle counts)
  const eightMPossible = remBaseBefore > 0;
  // König possible when (a) it's the last stick of the set, OR
  // (b) all field+base kubbs are down considering current stick's contribution
  const fieldDownIfApplied = fieldDownPrior + stick.field;
  const baseDownIfApplied  = baseDownPrior  + (stick.eightM ? 1 : 0);
  const allDown = fieldDownIfApplied >= config.field && baseDownIfApplied >= config.base;
  const lastStick = current === 5;
  const kingPossible = (allDown || lastStick) && !stick.heli;

  // Field max for this stick = remaining BEFORE this stick
  const fieldMaxThisStick = remFieldBefore;
  const fieldOptions = Array.from({length: fieldMaxThisStick + 1}, (_, n) => n);

  const next = () => {
    if (current < 5) setCurrent(current + 1);
    else onFinish(sticks);
  };

  return (
    <div style={f.screen}>
      <AppBar
        eyebrow={`Finisseur · ${config.field}/${config.base}`}
        title={<>Stock {current+1} <span style={{opacity:0.5}}>/ 6</span></>}
        onBack={onBack}
      />

      {/* Stick progress */}
      <div style={f.stickRow}>
        {sticks.map((s, i) => {
          const tone =
            i > current ? 'pending' :
            i === current ? 'active' :
            s.heli ? 'heli' :
            (s.p1 + s.p2) > 0 ? 'penalty' :
            s.king?.hit ? 'king' :
            (s.field > 0 || s.eightM) ? 'done' : 'empty';
          return <span key={i} style={{...f.stickPip, ...f.stickPipTones[tone]}}/>;
        })}
      </div>

      {/* Remaining */}
      <div style={f.remaining}>
        <div style={f.remCell}>
          <span style={f.remLbl}>Feldkubbs übrig</span>
          <span style={f.remVal}>{remField}</span>
        </div>
        <div style={f.remDivider}/>
        <div style={f.remCell}>
          <span style={f.remLbl}>Basiskubbs übrig</span>
          <span style={{...f.remVal, color:'var(--bk-wood-500)'}}>{remBase}</span>
        </div>
      </div>

      {/* Outcome inputs */}
      <div style={f.section}>
        <div style={f.sectionHead}>
          Feldkubbs umgeworfen <span style={f.sectionMeta}>0–{fieldMaxThisStick}</span>
        </div>
        {fieldMaxThisStick === 0 ? (
          <div style={f.empty}>keine Feldkubbs mehr — direkt 8m oder König</div>
        ) : (
          <div style={f.bigRow}>
            {fieldOptions.map(n => (
              <button key={n}
                      style={{...f.bigChip, ...(stick.field===n && !stick.heli ? f.bigChipOn : {})}}
                      onClick={() => !stick.heli && update({ field:n })}
                      disabled={stick.heli}>
                {n}
              </button>
            ))}
          </div>
        )}
      </div>

      <div style={f.toggleGrid}>
        {eightMPossible && (
          <Toggle on={stick.eightM && !stick.heli} disabled={stick.heli}
                  label="8m-Treffer" sub="Wurf auf Basiskubb"
                  onClick={() => update({ eightM: !stick.eightM })}/>
        )}
        <Toggle on={stick.heli} tone="heli"
                label="Helikopter" sub="ungültig, Stock weg"
                onClick={() => setHeli(!stick.heli)}/>
        {kingPossible && (
          <Toggle on={!!stick.king}
                  tone="king"
                  label="Königswurf" sub={stick.king?.style ? `${stick.king.style} · ${stick.king.hit ? 'Treffer' : 'verfehlt'}` : 'am Ende'}
                  onClick={() => update({ king: stick.king ? null : { hit:true, style:'oben' } })}/>
        )}
      </div>

      {/* Strafkubb — nur beim ersten Stock relevant (Strafkubbs aus dem
          letzten Halbsatz werden zu Beginn gesetzt). Vertikales Layout
          mit Anzahl-Eingabe für Kubbs, die ausserhalb gelandet sind. */}
      {/* Strafkubb — nur beim ersten Stock relevant. Zwei Würfe (1× / 2×),
          jeder Wurf wirft 0..config.base Strafkubbs um. Summe ≤ config.base. */}
      {!stick.heli && current === 0 && config.base > 0 && (
        <div style={f.section}>
          <div style={f.sectionHead}>
            Strafkubbs (vom letzten Halbsatz)
            <span style={f.sectionMeta}>
              {stick.p1 + stick.p2} / {config.base} umgeworfen
            </span>
          </div>

          <div style={f.penaltyThrowCol}>
            <PenaltyThrowRow
              label="1× geworfen"
              sub="erster Strafkubb-Wurf"
              value={stick.p1}
              max={Math.max(0, config.base - stick.p2)}
              onChange={v => update({ p1:v })}/>
            <PenaltyThrowRow
              label="2× geworfen"
              sub="zweiter Strafkubb-Wurf"
              value={stick.p2}
              max={Math.max(0, config.base - stick.p1)}
              onChange={v => update({ p2:v })}/>
          </div>
        </div>
      )}

      {/* King detail (when set) */}
      {stick.king && !stick.heli && (
        <div style={f.kingDetail}>
          <div style={f.kingRow}>
            <span style={f.kingLbl}>Position</span>
            <Segmented value={stick.king.style} options={['oben', 'unten']}
              onChange={v => update({ king: { ...stick.king, style: v } })}/>
          </div>
          <div style={f.kingRow}>
            <span style={f.kingLbl}>Outcome</span>
            <Segmented value={stick.king.hit ? 'Treffer' : 'verfehlt'} options={['Treffer','verfehlt']}
              tone="hit"
              onChange={v => update({ king: { ...stick.king, hit: v === 'Treffer' } })}/>
          </div>
        </div>
      )}

      <button style={f.nextBtn} onClick={next}>
        {current < 5 ? `Stock ${current+2}` : 'Session abschliessen'}
      </button>
    </div>
  );
}

function PenaltyThrowRow({ label, sub, value, max, onChange }) {
  const v = Math.max(0, Math.min(max, value || 0));
  // Render 0..max as a row of compact chips so the user picks directly.
  const chips = Array.from({ length: max + 1 }, (_, n) => n);
  return (
    <div style={f.penaltyThrow}>
      <div style={f.penaltyThrowHead}>
        <div style={f.penaltyThrowLabels}>
          <span style={f.penaltyThrowLbl}>{label}</span>
          <span style={f.penaltyThrowSub}>{sub}</span>
        </div>
        <span style={f.penaltyThrowReadout}>
          <span style={f.penaltyThrowReadoutN}>{v}</span>
          <span style={f.penaltyThrowReadoutMax}>/ {max}</span>
        </span>
      </div>
      {max === 0 ? (
        <div style={f.penaltyEmpty}>nicht mehr möglich (Summe ≤ {value > 0 ? '…' : '…'})</div>
      ) : (
        <div style={f.penaltyChipRow}>
          {chips.map(n => (
            <button key={n}
                    onClick={() => onChange(n)}
                    style={{...f.penaltyNumChip, ...(n === v ? f.penaltyNumChipOn : {})}}>
              {n}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function Toggle({ on, label, sub, onClick, tone, disabled }) {
  const onColor =
    tone === 'heli'    ? 'var(--bk-heli)' :
    tone === 'king'    ? 'var(--bk-king)' :
    'var(--bk-meadow-600)';
  const onText = tone === 'heli' || tone === 'king' ? 'var(--bk-stone-900)' : '#fff';
  return (
    <button onClick={!disabled ? onClick : undefined}
            style={{
              ...f.toggle,
              ...(on ? { background: onColor, color: onText, boxShadow:'none' } : {}),
              ...(disabled ? f.disabled : {})
            }}>
      <span style={f.toggleLabel}>{label}</span>
      <span style={f.toggleSub}>{sub}</span>
    </button>
  );
}

function Segmented({ value, options, onChange }) {
  return (
    <div style={f.seg}>
      {options.map(o => (
        <button key={o}
                style={{...f.segBtn, ...(value===o ? f.segBtnOn : {})}}
                onClick={() => onChange(o)}>
          {o}
        </button>
      ))}
    </div>
  );
}

const f = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflowY:'auto', paddingBottom:32 },
  topbar: { display:'flex', alignItems:'center', justifyContent:'space-between', padding:'54px 12px 6px' },
  iconBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },
  topTitle: { textAlign:'center' },
  topEyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  topName: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:20, letterSpacing:'-0.02em' },

  stickRow: { display:'flex', gap:8, justifyContent:'center', padding:'4px 16px 10px' },
  stickPip: { flex:1, maxWidth:48, height:6, borderRadius:3, background:'var(--bk-stone-200)' },
  stickPipTones: {
    pending: { background:'var(--bk-stone-200)' },
    active:  { background:'var(--bk-stone-900)' },
    done:    { background:'var(--bk-meadow-500)' },
    heli:    { background:'var(--bk-heli)' },
    penalty: { background:'var(--bk-penalty)' },
    king:    { background:'var(--bk-king)' },
    empty:   { background:'var(--bk-stone-200)' },
  },

  remaining: { display:'flex', alignItems:'center', justifyContent:'space-around', background:'var(--bk-bg-raised)', margin:'4px 16px 14px', borderRadius:16, padding:'10px 8px' },
  remCell: { display:'flex', flexDirection:'column', alignItems:'center', gap:2 },
  remLbl: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  remVal: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:32, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums', color:'var(--bk-meadow-600)' },
  remDivider: { width:1, alignSelf:'stretch', background:'var(--bk-line)', margin:'4px 0' },

  section: { padding:'2px 16px 6px' },
  sectionHead: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', marginBottom:8, display:'flex', justifyContent:'space-between', alignItems:'baseline' },
  sectionMeta: { fontFamily:'var(--bk-font-mono)', fontSize:10, color:'var(--bk-fg-subtle)', textTransform:'none', letterSpacing:0, fontWeight:500 },
  bigRow: { display:'grid', gridTemplateColumns:'repeat(auto-fit, minmax(56px, 1fr))', gap:8 },
  bigChip: { minHeight:60, borderRadius:14, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 2px var(--bk-line)', fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:24, fontVariantNumeric:'tabular-nums', cursor:'pointer' },
  bigChipOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)', boxShadow:'none' },
  empty: { fontSize:12, color:'var(--bk-fg-muted)', fontStyle:'italic', padding:'10px 0' },
  disabled: { opacity:0.35, pointerEvents:'none' },

  toggleGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:8, padding:'10px 16px 6px' },
  toggle: { textAlign:'left', padding:'10px 14px', minHeight:64, border:0, borderRadius:14, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 2px var(--bk-line)', display:'flex', flexDirection:'column', justifyContent:'center', gap:2, cursor:'pointer' },
  toggleLabel: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:15 },
  toggleSub: { fontSize:11, opacity:0.85 },

  // Strafkubb — pro Wurf 0..base (Summe ≤ base)
  penaltyThrowCol: { display:'flex', flexDirection:'column', gap:10 },
  penaltyThrow: { background:'var(--bk-bg-raised)', borderRadius:14, padding:'10px 14px 12px', display:'flex', flexDirection:'column', gap:8 },
  penaltyThrowHead: { display:'flex', alignItems:'center', justifyContent:'space-between', gap:10 },
  penaltyThrowLabels: { display:'flex', flexDirection:'column' },
  penaltyThrowLbl: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:15 },
  penaltyThrowSub: { fontSize:11, color:'var(--bk-fg-muted)' },
  penaltyThrowReadout: { display:'flex', alignItems:'baseline', gap:2, fontFamily:'var(--bk-font-display)', fontVariantNumeric:'tabular-nums' },
  penaltyThrowReadoutN: { fontWeight:800, fontSize:22 },
  penaltyThrowReadoutMax: { fontSize:12, color:'var(--bk-fg-muted)', fontWeight:600 },
  penaltyChipRow: { display:'flex', gap:6, flexWrap:'wrap' },
  penaltyNumChip: { flex:'1 1 44px', minWidth:44, minHeight:44, borderRadius:10, border:0, background:'var(--bk-bg)', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 1.5px var(--bk-line-strong)', fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:18, fontVariantNumeric:'tabular-nums', cursor:'pointer' },
  penaltyNumChipOn: { background:'var(--bk-penalty)', color:'#fff', boxShadow:'none' },
  penaltyEmpty: { fontSize:11, color:'var(--bk-fg-muted)', fontStyle:'italic' },

  penaltyRow: { display:'grid', gridTemplateColumns:'repeat(3, 1fr)', gap:8 },
  penaltyChip: { minHeight:60, borderRadius:14, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 2px var(--bk-line)', display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', gap:2, cursor:'pointer', padding:'4px 6px' },
  penaltyChipOn: { background:'var(--bk-penalty)', color:'#fff', boxShadow:'none' },
  penaltyChipNum: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:20, lineHeight:1 },
  penaltyChipLbl: { fontSize:10, opacity:0.85, textAlign:'center' },

  kingDetail: { background:'var(--bk-bg-raised)', margin:'8px 16px 0', borderRadius:14, padding:'10px 14px', display:'flex', flexDirection:'column', gap:8, boxShadow:'inset 0 0 0 2px var(--bk-king)' },
  kingRow: { display:'flex', justifyContent:'space-between', alignItems:'center' },
  kingLbl: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  seg: { display:'flex', background:'var(--bk-bg-sunken)', borderRadius:999, padding:3 },
  segBtn: { minHeight:36, padding:'0 14px', border:0, borderRadius:999, background:'transparent', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:13, cursor:'pointer' },
  segBtnOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)' },

  nextBtn: { margin:'14px 16px 28px', minHeight:60, borderRadius:16, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:18, cursor:'pointer' },
};

window.FinisseurStickScreen = FinisseurStickScreen;
