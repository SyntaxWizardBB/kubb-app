/* global React, DIcon, TopBar, PrimaryBtn, SecondaryBtn, Card, CardHeader */
// =====================================================================
// FinisseurStick — Per-Stick Eingabe-Screen für Desktop.
//   Pendant zu mobile/FinisseurStickScreen.jsx, aber als 3-Spalten-Layout:
//     Left (340) : Stock-Liste mit Pips & Aggregat
//     Center (flex) : aktiver Stock — Feldkubbs, Toggles, Strafkubbs, König
//     Right (320) : Live-Preview des Felds + Quick-Stats
// =====================================================================

const { useState: useFsState } = React;

const FS_CONFIG = { field: 7, base: 3 };

function FinisseurStickScreen({ onRoute }) {
  const empty = () => ({ field:0, eightM:false, p1:0, p2:0, heli:false, king:null });
  const [sticks, setSticks] = useFsState([
    { field:4, eightM:false, p1:0, p2:0, heli:false, king:null },
    { field:2, eightM:false, p1:0, p2:0, heli:true,  king:null },
    { field:1, eightM:false, p1:0, p2:0, heli:false, king:null },
    { field:0, eightM:true,  p1:0, p2:0, heli:false, king:null },
    empty(),
    empty(),
  ]);
  const [current, setCurrent] = useFsState(4);

  const prior = sticks.slice(0, current);
  const fieldDownPrior = prior.reduce((a, s) => a + s.field, 0);
  const baseDownPrior  = prior.reduce((a, s) => a + (s.eightM ? 1 : 0), 0);
  const remFieldBefore = Math.max(0, FS_CONFIG.field - fieldDownPrior);
  const remBaseBefore  = Math.max(0, FS_CONFIG.base  - baseDownPrior);

  const fieldDownTotal = sticks.reduce((a, s) => a + s.field, 0);
  const baseDownTotal  = sticks.reduce((a, s) => a + (s.eightM ? 1 : 0), 0);
  const remField = Math.max(0, FS_CONFIG.field - fieldDownTotal);
  const remBase  = Math.max(0, FS_CONFIG.base  - baseDownTotal);

  const stick = sticks[current];

  const update = (patch) => setSticks(prev => prev.map((s, i) => i === current ? { ...s, ...patch } : s));
  const setHeli = (on) => on
    ? update({ heli:true, field:0, eightM:false, p1:0, p2:0, king:null })
    : update({ heli:false });

  const eightMPossible = remBaseBefore > 0;
  const fieldDownIfApplied = fieldDownPrior + stick.field;
  const baseDownIfApplied  = baseDownPrior + (stick.eightM ? 1 : 0);
  const allDown   = fieldDownIfApplied >= FS_CONFIG.field && baseDownIfApplied >= FS_CONFIG.base;
  const lastStick = current === 5;
  const kingPossible = (allDown || lastStick) && !stick.heli;

  const fieldMaxThisStick = remFieldBefore;
  const fieldOptions = Array.from({length: fieldMaxThisStick + 1}, (_, n) => n);

  return (
    <>
      <TopBar
        eyebrow={`Finisseur · ${FS_CONFIG.field}/${FS_CONFIG.base} · live`}
        title={`Stock ${current + 1} von 6`}
        subtitle={`Halbsatz läuft · ${fieldDownTotal} von ${FS_CONFIG.field} Feldkubbs umgeworfen · ${baseDownTotal} von ${FS_CONFIG.base} Basis getroffen`}
        right={<>
          <SecondaryBtn icon={<DIcon.Undo/>} tone="ghost" size="sm" onClick={() => current>0 && setCurrent(current-1)}>Vorheriger Stock</SecondaryBtn>
          <SecondaryBtn icon={<DIcon.Pause/>} tone="default">Pause</SecondaryBtn>
          <PrimaryBtn icon={<DIcon.Stop/>} onClick={() => onRoute && onRoute('summary')}>Halbsatz beenden</PrimaryBtn>
        </>}
      />

      <div style={fs.split}>
        {/* LEFT — Stock-Liste */}
        <aside style={fs.aside}>
          <Card padding={18}>
            <div style={fs.cardHead}>
              <span style={fs.eyebrow}>6 Stöcke</span>
              <span style={fs.runde}>Halbsatz #4</span>
            </div>
            <div style={fs.stickList}>
              {sticks.map((s, i) => {
                const active = i === current;
                const done   = i < current;
                const tone =
                  s.heli ? 'heli' :
                  s.king ? 'king' :
                  (s.p1 + s.p2) > 0 ? 'penalty' :
                  (s.field > 0 || s.eightM) ? 'hit' :
                  done ? 'empty-done' : 'pending';
                return (
                  <button key={i}
                          style={{...fs.stickRow, ...(active ? fs.stickRowActive : {})}}
                          onClick={() => setCurrent(i)}>
                    <span style={fs.stickIdx}>{i+1}</span>
                    <span style={{...fs.stickPip, background: TONE_COLOR[tone]}}/>
                    <div style={fs.stickBody}>
                      <div style={fs.stickHead}>
                        {active && <span style={fs.activeTag}>aktiv</span>}
                        {!active && done && <span style={fs.doneTag}>fertig</span>}
                        {!active && !done && <span style={fs.pendingTag}>offen</span>}
                      </div>
                      <div style={fs.stickSummary}>
                        {summaryText(s)}
                      </div>
                    </div>
                    <span style={fs.stickChev}><DIcon.Chevron/></span>
                  </button>
                );
              })}
            </div>
          </Card>

          <Card padding={18}>
            <div style={fs.eyebrow}>Verbleibend</div>
            <div style={fs.remGrid}>
              <div style={fs.remCell}>
                <span style={fs.remLbl}>Feldkubbs</span>
                <span style={fs.remVal}>{remField}<small style={fs.remMax}>/{FS_CONFIG.field}</small></span>
              </div>
              <div style={fs.remCell}>
                <span style={fs.remLbl}>Basis</span>
                <span style={{...fs.remVal, color:'var(--kc-wood-500)'}}>{remBase}<small style={fs.remMax}>/{FS_CONFIG.base}</small></span>
              </div>
            </div>
          </Card>
        </aside>

        {/* CENTER — Input */}
        <main style={fs.main}>
          <Card padding={22}>
            <div style={fs.centerHead}>
              <div>
                <div style={fs.eyebrow}>Aktiver Stock</div>
                <h3 style={fs.centerTitle}>Stock {current + 1} · was passiert?</h3>
              </div>
              <div style={fs.kbdHints}>
                <kbd style={fs.kbd}>0</kbd>…<kbd style={fs.kbd}>{fieldMaxThisStick}</kbd>
                <span style={fs.kbdLbl}>Feldkubbs</span>
                <kbd style={fs.kbd}>H</kbd><span style={fs.kbdLbl}>Heli</span>
                <kbd style={fs.kbd}>K</kbd><span style={fs.kbdLbl}>König</span>
              </div>
            </div>

            {/* Feldkubbs */}
            <div style={fs.sec}>
              <div style={fs.secHead}>
                <span style={fs.secLbl}>Feldkubbs umgeworfen</span>
                <span style={fs.secMeta}>0 – {fieldMaxThisStick}</span>
              </div>
              {fieldMaxThisStick === 0 ? (
                <div style={fs.empty}>Keine Feldkubbs mehr offen — wähle 8 m oder Königswurf.</div>
              ) : (
                <div style={fs.fieldRow}>
                  {fieldOptions.map(n => (
                    <button key={n}
                            style={{...fs.fieldChip, ...(stick.field === n && !stick.heli ? fs.fieldChipOn : {}), ...(stick.heli ? fs.disabled : {})}}
                            disabled={stick.heli}
                            onClick={() => !stick.heli && update({ field:n })}>
                      <span style={fs.fieldChipN}>{n}</span>
                      <span style={fs.fieldChipLbl}>{n === 1 ? 'Kubb' : 'Kubbs'}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Toggles */}
            <div style={fs.sec}>
              <div style={fs.secHead}>
                <span style={fs.secLbl}>Zusätzliche Outcomes</span>
              </div>
              <div style={fs.toggleGrid}>
                {eightMPossible && (
                  <Toggle on={stick.eightM && !stick.heli}
                          disabled={stick.heli}
                          tone="wood"
                          label="8 m-Treffer"
                          sub="Wurf auf Basiskubb"
                          onClick={() => update({ eightM: !stick.eightM })}/>
                )}
                <Toggle on={stick.heli}
                        tone="heli"
                        label="Helikopter"
                        sub="ungültig, Stock weg"
                        onClick={() => setHeli(!stick.heli)}/>
                {kingPossible && (
                  <Toggle on={!!stick.king}
                          tone="king"
                          label="Königswurf"
                          sub={stick.king ? `${stick.king.style} · ${stick.king.hit ? 'Treffer' : 'verfehlt'}` : 'am Ende des Halbsatzes'}
                          onClick={() => update({ king: stick.king ? null : { hit:true, style:'oben' } })}/>
                )}
              </div>
            </div>

            {/* König-Detail */}
            {stick.king && !stick.heli && (
              <div style={fs.kingDetail}>
                <div style={fs.kingHead}><DIcon.King/> Königswurf · Details</div>
                <div style={fs.kingGrid}>
                  <Segmented label="Position"
                             value={stick.king.style}
                             options={['oben', 'unten']}
                             onChange={v => update({ king: { ...stick.king, style: v } })}/>
                  <Segmented label="Outcome"
                             value={stick.king.hit ? 'Treffer' : 'verfehlt'}
                             options={['Treffer', 'verfehlt']}
                             onChange={v => update({ king: { ...stick.king, hit: v === 'Treffer' } })}/>
                </div>
              </div>
            )}

            {/* Strafkubbs (nur Stock 1) */}
            {!stick.heli && current === 0 && FS_CONFIG.base > 0 && (
              <div style={fs.sec}>
                <div style={fs.secHead}>
                  <span style={fs.secLbl}>Strafkubbs (vom letzten Halbsatz)</span>
                  <span style={fs.secMeta}>{stick.p1 + stick.p2} / {FS_CONFIG.base} umgeworfen</span>
                </div>
                <div style={fs.penaltyCol}>
                  <PenaltyRow label="1× geworfen" sub="erster Strafkubb"
                              value={stick.p1}
                              max={Math.max(0, FS_CONFIG.base - stick.p2)}
                              onChange={v => update({ p1: v })}/>
                  <PenaltyRow label="2× geworfen" sub="zweiter Strafkubb"
                              value={stick.p2}
                              max={Math.max(0, FS_CONFIG.base - stick.p1)}
                              onChange={v => update({ p2: v })}/>
                </div>
              </div>
            )}

            <div style={fs.navRow}>
              <SecondaryBtn icon={<DIcon.Undo/>} tone="ghost"
                            onClick={() => current > 0 && setCurrent(current - 1)}>
                ← Stock {current}
              </SecondaryBtn>
              <PrimaryBtn
                onClick={() => current < 5
                  ? setCurrent(current + 1)
                  : onRoute && onRoute('summary')}>
                {current < 5 ? `Weiter zu Stock ${current + 2}` : 'Halbsatz beenden'}
              </PrimaryBtn>
            </div>
          </Card>
        </main>

        {/* RIGHT — Pitch + Stats */}
        <aside style={fs.right}>
          <Card padding={18}>
            <div style={fs.eyebrow}>Live-Feld</div>
            <PitchPreview field={FS_CONFIG.field} base={FS_CONFIG.base}
                          fieldDown={fieldDownTotal} baseDown={baseDownTotal}
                          kingDown={sticks.some(s => s.king?.hit)}/>
          </Card>

          <Card padding={18}>
            <div style={fs.eyebrow}>Halbsatz-Statistik</div>
            <div style={fs.statsList}>
              <Stat label="Stöcke verwendet" value={`${current + (stick.field>0||stick.eightM||stick.heli||stick.king ? 1 : 0)} / 6`}/>
              <Stat label="Helikopter"        value={sticks.filter(s => s.heli).length}/>
              <Stat label="Strafkubbs"        value={sticks[0].p1 + sticks[0].p2}/>
              <Stat label="Spielzeit"         value="3:48" mono/>
              <Stat label="∅ pro Stock"       value="58 s" mono muted/>
            </div>
          </Card>

          <Card padding={18}>
            <div style={fs.eyebrow}>Tipp</div>
            <p style={fs.tipText}>
              Du brauchst noch <b>{remField + remBase} Treffer + König</b>, um sauber zu finishen. Mit {6 - current - 1} verbleibenden Stöcken ist das machbar — versuche eine Doppelreihe.
            </p>
          </Card>
        </aside>
      </div>
    </>
  );
}

// ---------- Sub ----------
function summaryText(s) {
  if (s.heli) return 'Helikopter — Stock verworfen';
  if (s.king) return `König · ${s.king.style} · ${s.king.hit ? 'Treffer' : 'verfehlt'}`;
  const parts = [];
  if (s.field > 0)  parts.push(`${s.field} Feldkubb${s.field === 1 ? '' : 's'}`);
  if (s.eightM)     parts.push('8 m-Treffer');
  if (s.p1 + s.p2 > 0) parts.push(`${s.p1 + s.p2} Straf`);
  return parts.length ? parts.join(' · ') : '— leer —';
}

function Toggle({ on, disabled, tone, label, sub, onClick }) {
  const onStyles = {
    heli: { background:'var(--kc-heli)',    color:'var(--kc-stone-900)' },
    king: { background:'var(--kc-king)',    color:'var(--kc-stone-900)' },
    wood: { background:'var(--kc-wood-500)', color:'#fff' },
    default:{ background:'var(--kc-meadow-600)', color:'#fff' },
  };
  return (
    <button style={{
      ...fs.toggle,
      ...(on ? onStyles[tone || 'default'] : {}),
      ...(disabled ? fs.disabled : {}),
    }} disabled={disabled} onClick={onClick}>
      <span style={fs.toggleLbl}>{label}</span>
      <span style={fs.toggleSub}>{sub}</span>
    </button>
  );
}

function Segmented({ label, value, options, onChange }) {
  return (
    <div style={fs.segWrap}>
      <span style={fs.segLbl}>{label}</span>
      <div style={fs.seg}>
        {options.map(o => (
          <button key={o}
                  style={{...fs.segBtn, ...(value === o ? fs.segBtnOn : {})}}
                  onClick={() => onChange(o)}>{o}</button>
        ))}
      </div>
    </div>
  );
}

function PenaltyRow({ label, sub, value, max, onChange }) {
  const v = Math.max(0, Math.min(max, value || 0));
  const chips = Array.from({length: max + 1}, (_, n) => n);
  return (
    <div style={fs.penalty}>
      <div style={fs.penaltyHead}>
        <div>
          <span style={fs.penaltyLbl}>{label}</span>
          <span style={fs.penaltySub}> · {sub}</span>
        </div>
        <span style={fs.penaltyVal}>{v}<small style={{color:'var(--kc-fg-muted)', fontWeight:600}}> / {max}</small></span>
      </div>
      {max === 0 ? (
        <div style={fs.empty}>nicht mehr möglich</div>
      ) : (
        <div style={fs.penaltyChips}>
          {chips.map(n => (
            <button key={n}
                    onClick={() => onChange(n)}
                    style={{...fs.penChip, ...(n === v ? fs.penChipOn : {})}}>
              {n}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function Stat({ label, value, mono, muted }) {
  return (
    <div style={fs.stat}>
      <span style={fs.statLbl}>{label}</span>
      <span style={{...(mono ? fs.statValMono : fs.statVal), color: muted ? 'var(--kc-fg-muted)' : 'var(--kc-fg)'}}>{value}</span>
    </div>
  );
}

function PitchPreview({ field, base, fieldDown, baseDown, kingDown }) {
  // Top row: field kubbs (in field), Bottom row: base kubbs (on baseline)
  const w = 260, h = 220, pad = 12;
  const fRow = 60, bRow = h - 50, midY = h * 0.5;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} style={{marginTop:10}}>
      <rect x={pad} y={pad} width={w - 2*pad} height={h - 2*pad}
            fill="var(--kc-meadow-50)" stroke="var(--kc-meadow-200)" strokeWidth="1.5" rx="6"/>
      {/* Mid line */}
      <line x1={pad} x2={w-pad} y1={midY} y2={midY} stroke="var(--kc-stone-300)" strokeWidth="1" strokeDasharray="3 4"/>
      {/* Field kubbs */}
      {Array.from({length: field}).map((_, i) => {
        const x = pad + 16 + (i * ((w - 2*pad - 32) / (field - 1 || 1)));
        const knocked = i < fieldDown;
        return knocked
          ? <rect key={'f'+i} x={x-7} y={fRow-3} width={14} height={6} rx="2" fill="var(--kc-stone-300)" stroke="var(--kc-stone-400)"/>
          : <rect key={'f'+i} x={x-6} y={fRow-10} width={12} height={20} rx="2" fill="var(--kc-wood-400)" stroke="var(--kc-wood-600)" strokeWidth="1.5"/>;
      })}
      {/* Base kubbs */}
      {Array.from({length: base}).map((_, i) => {
        const x = pad + 30 + (i * ((w - 2*pad - 60) / (base - 1 || 1)));
        const knocked = i < baseDown;
        return knocked
          ? <rect key={'b'+i} x={x-8} y={bRow-3} width={16} height={6} rx="2" fill="var(--kc-stone-300)" stroke="var(--kc-stone-400)"/>
          : <rect key={'b'+i} x={x-7} y={bRow-14} width={14} height={28} rx="2" fill="var(--kc-wood-300)" stroke="var(--kc-wood-500)" strokeWidth="1.5"/>;
      })}
      {/* King */}
      <circle cx={w/2} cy={midY} r="12" fill={kingDown ? 'var(--kc-stone-300)' : 'var(--kc-king)'} stroke="var(--kc-wood-600)" strokeWidth="2"/>
      {!kingDown && <path d={`M ${w/2 - 6} ${midY - 4} L ${w/2 - 3} ${midY - 10} L ${w/2} ${midY - 5} L ${w/2 + 3} ${midY - 10} L ${w/2 + 6} ${midY - 4} Z`} fill="var(--kc-wood-600)"/>}
      <text x={pad + 6} y={fRow - 12} fontFamily="var(--kc-font-mono)" fontSize="9" fill="var(--kc-fg-muted)" letterSpacing="0.04em">FELD · {field}</text>
      <text x={pad + 6} y={bRow + 22} fontFamily="var(--kc-font-mono)" fontSize="9" fill="var(--kc-fg-muted)" letterSpacing="0.04em">BASIS · {base}</text>
    </svg>
  );
}

const TONE_COLOR = {
  hit:        'var(--kc-meadow-500)',
  heli:       'var(--kc-heli)',
  penalty:    'var(--kc-penalty)',
  king:       'var(--kc-king)',
  pending:    'var(--kc-stone-200)',
  'empty-done': 'var(--kc-stone-300)',
};

// ---------- Styles ----------
const fs = {
  split: { display:'grid', gridTemplateColumns:'340px 1fr 320px', gap:18, padding:'24px 32px 32px', minHeight:0 },
  aside: { display:'flex', flexDirection:'column', gap:14, minWidth:0 },
  main:  { display:'flex', flexDirection:'column', gap:14, minWidth:0 },
  right: { display:'flex', flexDirection:'column', gap:14, minWidth:0 },

  cardHead: { display:'flex', justifyContent:'space-between', alignItems:'baseline', marginBottom:10 },
  eyebrow: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.1em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  runde:   { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.06em', textTransform:'uppercase' },

  stickList: { display:'flex', flexDirection:'column', gap:4 },
  stickRow: { display:'grid', gridTemplateColumns:'24px 12px 1fr 16px', gap:10, alignItems:'center', padding:'10px 12px', borderRadius:10, background:'transparent', border:0, color:'var(--kc-fg)', cursor:'pointer', textAlign:'left', boxShadow:'inset 0 0 0 1.5px transparent' },
  stickRowActive: { background:'var(--kc-bg-sunken)', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-900)' },
  stickIdx: { fontFamily:'var(--kc-font-mono)', fontSize:13, fontWeight:700, color:'var(--kc-fg-muted)' },
  stickPip: { width:8, height:36, borderRadius:3 },
  stickBody: { display:'flex', flexDirection:'column', gap:1, minWidth:0 },
  stickHead: { display:'flex', alignItems:'center', gap:8 },
  activeTag: { fontFamily:'var(--kc-font-mono)', fontSize:9, fontWeight:700, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-chalk-50)', background:'var(--kc-stone-900)', padding:'2px 6px', borderRadius:4 },
  doneTag: { fontFamily:'var(--kc-font-mono)', fontSize:9, fontWeight:700, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-meadow-700)' },
  pendingTag: { fontFamily:'var(--kc-font-mono)', fontSize:9, fontWeight:700, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-subtle)' },
  stickSummary: { fontFamily:'var(--kc-font-ui)', fontWeight:500, fontSize:13, color:'var(--kc-fg-muted)', overflow:'hidden', whiteSpace:'nowrap', textOverflow:'ellipsis' },
  stickChev: { color:'var(--kc-fg-subtle)' },

  remGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:10, marginTop:8 },
  remCell: { padding:'8px 10px', borderRadius:10, background:'var(--kc-bg-sunken)' },
  remLbl: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-fg-muted)', display:'block' },
  remVal: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:36, letterSpacing:'-0.03em', lineHeight:1, fontVariantNumeric:'tabular-nums', color:'var(--kc-meadow-700)', marginTop:4, display:'inline-flex', alignItems:'baseline' },
  remMax: { fontSize:14, fontWeight:600, color:'var(--kc-fg-muted)', marginLeft:2 },

  centerHead: { display:'flex', justifyContent:'space-between', alignItems:'flex-end', gap:14, marginBottom:14 },
  centerTitle: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:22, letterSpacing:'-0.015em', margin:'4px 0 0' },
  kbdHints: { display:'flex', alignItems:'center', gap:6, fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', flexWrap:'wrap', justifyContent:'flex-end' },
  kbd: { display:'inline-grid', placeItems:'center', minWidth:22, height:22, padding:'0 4px', borderRadius:5, background:'var(--kc-bg-sunken)', boxShadow:'inset 0 0 0 1px var(--kc-line)', fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:700, color:'var(--kc-fg)' },
  kbdLbl: { color:'var(--kc-fg-muted)' },

  sec: { marginTop:18 },
  secHead: { display:'flex', justifyContent:'space-between', alignItems:'baseline', marginBottom:10 },
  secLbl: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  secMeta: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-subtle)' },
  empty: { padding:'14px 16px', borderRadius:10, background:'var(--kc-bg-sunken)', color:'var(--kc-fg-muted)', fontStyle:'italic', fontSize:13 },

  fieldRow: { display:'grid', gridTemplateColumns:'repeat(auto-fill, minmax(86px, 1fr))', gap:8 },
  fieldChip: { minHeight:72, padding:'8px 12px', borderRadius:14, border:0, background:'var(--kc-bg-sunken)', color:'var(--kc-fg)', display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', gap:2, cursor:'pointer', boxShadow:'inset 0 0 0 1.5px transparent' },
  fieldChipOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)', boxShadow:'none' },
  fieldChipN: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:32, letterSpacing:'-0.03em', lineHeight:1, fontVariantNumeric:'tabular-nums' },
  fieldChipLbl: { fontFamily:'var(--kc-font-mono)', fontSize:10, letterSpacing:'0.06em', textTransform:'uppercase', opacity:0.7 },

  toggleGrid: { display:'grid', gridTemplateColumns:'repeat(auto-fit, minmax(180px, 1fr))', gap:10 },
  toggle: { textAlign:'left', padding:'14px 16px', minHeight:72, border:0, borderRadius:14, background:'var(--kc-bg-sunken)', color:'var(--kc-fg)', display:'flex', flexDirection:'column', justifyContent:'center', gap:2, cursor:'pointer', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-200)' },
  toggleLbl: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:18, letterSpacing:'-0.015em', fontVariationSettings:'"opsz" 36' },
  toggleSub: { fontFamily:'var(--kc-font-ui)', fontSize:12, opacity:0.8 },
  disabled: { opacity:0.35, pointerEvents:'none' },

  kingDetail: { marginTop:14, padding:'14px 16px', borderRadius:14, background:'var(--kc-wood-50)', boxShadow:'inset 0 0 0 1.5px var(--kc-king)' },
  kingHead: { display:'flex', alignItems:'center', gap:8, fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:16, color:'var(--kc-wood-600)', marginBottom:10 },
  kingGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:14 },
  segWrap: { display:'flex', flexDirection:'column', gap:6 },
  segLbl: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  seg: { display:'flex', background:'var(--kc-bg-raised)', borderRadius:999, padding:3, gap:0 },
  segBtn: { flex:1, minHeight:36, padding:'0 12px', border:0, borderRadius:999, background:'transparent', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer' },
  segBtnOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  penaltyCol: { display:'flex', flexDirection:'column', gap:10 },
  penalty: { padding:'12px 16px', borderRadius:12, background:'var(--kc-bg-sunken)' },
  penaltyHead: { display:'flex', justifyContent:'space-between', alignItems:'baseline', marginBottom:8 },
  penaltyLbl: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14 },
  penaltySub: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)' },
  penaltyVal: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:22, fontVariantNumeric:'tabular-nums', letterSpacing:'-0.02em' },
  penaltyChips: { display:'flex', gap:6, flexWrap:'wrap' },
  penChip: { minWidth:44, minHeight:40, padding:'0 12px', borderRadius:8, border:0, background:'var(--kc-bg-raised)', color:'var(--kc-fg)', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-200)', fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:15, fontVariantNumeric:'tabular-nums', cursor:'pointer' },
  penChipOn: { background:'var(--kc-penalty)', color:'#fff', boxShadow:'none' },

  navRow: { display:'flex', justifyContent:'space-between', alignItems:'center', marginTop:22, paddingTop:18, borderTop:'1px solid var(--kc-line)' },

  // right
  statsList: { display:'flex', flexDirection:'column', gap:0, marginTop:8 },
  stat: { display:'flex', justifyContent:'space-between', alignItems:'baseline', padding:'8px 0', borderTop:'1px solid var(--kc-line)' },
  statLbl: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.04em' },
  statVal: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:16, fontVariantNumeric:'tabular-nums' },
  statValMono: { fontFamily:'var(--kc-font-mono)', fontWeight:600, fontSize:14, fontVariantNumeric:'tabular-nums' },

  tipText: { margin:'10px 0 0', fontSize:13, color:'var(--kc-fg-muted)', lineHeight:1.5 },
};

window.FinisseurStickScreen = FinisseurStickScreen;
