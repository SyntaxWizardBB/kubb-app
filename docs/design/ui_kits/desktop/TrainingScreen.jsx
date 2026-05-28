/* global React, DIcon, TopBar, PrimaryBtn, SecondaryBtn, Card */
// =====================================================================
// Training — Live Sniper-Session, Master/Detail-Pattern.
//   Linke Spalte (340): Session-Konfig (Modus, Distanz, Ziel, History)
//   Rechte Spalte (flex): grosser Live-Counter + Tap-Pad
//   Inspiriert von EightMScreen.jsx (mobile), aber als Desktop-Layout.
// =====================================================================

const { useState, useMemo } = React;

function TrainingScreen({ onRoute }) {
  const [mode, setMode]         = useState('sniper');   // 'sniper' | 'finisseur'
  const [distance, setDistance] = useState(8.0);
  const [target, setTarget]     = useState(50);
  const [hits, setHits]         = useState(11);
  const [misses, setMisses]     = useState(6);
  const [helis, setHelis]       = useState(0);
  const [hidden, setHidden]     = useState(false);

  const total = hits + misses + helis;
  const remaining = target ? Math.max(0, target - total) : null;
  const rate = total ? Math.round(100 * hits / total) : 0;

  const tap = (setter, delta, min=0) => () => setter(v => Math.max(min, v + delta));

  return (
    <>
      <TopBar
        eyebrow={mode === 'sniper' ? 'Sniper-Training · live' : 'Finisseur · live'}
        title={mode === 'sniper' ? `${distance.toFixed(1)} m Distanz` : 'Match-Endspiel'}
        subtitle={`Session ${(hits+misses+helis) > 0 ? 'läuft' : 'bereit'} · gestartet 18:04 · ${total} Würfe protokolliert`}
        right={<>
          <SecondaryBtn icon={<DIcon.Undo/>} tone="ghost" size="sm">Letzten Wurf rückgängig</SecondaryBtn>
          <SecondaryBtn icon={hidden ? null : <DIcon.Pause/>} tone="default" onClick={() => setHidden(v => !v)}>
            {hidden ? 'Treffer einblenden' : 'Blind werfen'}
          </SecondaryBtn>
          <PrimaryBtn icon={<DIcon.Stop/>}>Session beenden</PrimaryBtn>
        </>}
      />

      <div style={t.split}>
        {/* LEFT — config + history */}
        <aside style={t.aside}>
          <Card padding={18}>
            <div style={t.modeLabel}>Modus</div>
            <div style={t.modeRow}>
              <button style={{...t.modeChip, ...(mode==='sniper' ? t.modeChipOn : {})}} onClick={() => setMode('sniper')}>
                <DIcon.Target/><span>Sniper</span>
              </button>
              <button style={{...t.modeChip, ...(mode==='finisseur' ? t.modeChipOn : {})}} onClick={() => setMode('finisseur')}>
                <DIcon.King/><span>Finisseur</span>
              </button>
            </div>
          </Card>

          {mode === 'sniper' ? (
            <Card padding={18}>
              <div style={t.fieldHead}>
                <span style={t.fieldLbl}>Distanz</span>
                <span style={t.fieldVal}>{distance.toFixed(1)} m</span>
              </div>
              <input type="range" min="4" max="8" step="0.5" value={distance}
                     onChange={e => setDistance(parseFloat(e.target.value))}
                     style={t.range}/>
              <div style={t.tickRow}>
                {[4,5,6,7,8].map(n => (
                  <span key={n} style={{...t.tick, color: Math.round(distance) === n ? 'var(--kc-fg)' : 'var(--kc-fg-muted)', fontWeight: Math.round(distance) === n ? 700 : 500}}>{n}.0</span>
                ))}
              </div>

              <hr style={t.thinLine}/>
              <div style={t.fieldHead}>
                <span style={t.fieldLbl}>Ziel-Wurfzahl</span>
                <span style={t.fieldVal}>{target ?? '∞'}</span>
              </div>
              <div style={t.chipRow}>
                {[null, 25, 50, 100, 200].map((n, i) => (
                  <button key={i}
                          style={{...t.chip, ...(target === n ? t.chipOn : {})}}
                          onClick={() => setTarget(n)}>
                    {n ?? '∞'}
                  </button>
                ))}
              </div>
            </Card>
          ) : (
            <Card padding={18}>
              <div style={t.fieldHead}>
                <span style={t.fieldLbl}>Konfiguration</span>
                <span style={t.fieldVal}>7 / 3</span>
              </div>
              <div style={t.chipRow}>
                {['7/3','5/5','10/0','3/5','Eigen…'].map((c, i) => (
                  <button key={i}
                          style={{...t.chip, ...(i === 0 ? t.chipOn : {})}}>
                    {c}
                  </button>
                ))}
              </div>
              <hr style={t.thinLine}/>
              <div style={t.fieldHead}>
                <span style={t.fieldLbl}>Halbsatz-Limit</span>
                <span style={t.fieldVal}>6 Stöcke</span>
              </div>
              <div style={t.chipRow}>
                {['4','5','6','8'].map((c, i) => (
                  <button key={i}
                          style={{...t.chip, ...(i === 2 ? t.chipOn : {})}}>
                    {c}
                  </button>
                ))}
              </div>
            </Card>
          )}

          <Card padding={18}>
            <div style={t.histHead}>
              <span style={t.modeLabel}>Aktueller Lauf</span>
              <span style={t.histMeta}>{total} Würfe</span>
            </div>
            <div style={t.histStrip}>
              {HISTORY.map((h, i) => (
                <span key={i} style={{...t.histCell, ...(t.histTone[h] || {})}} title={h}/>
              ))}
            </div>
            <div style={t.legendRow}>
              <span style={t.legendItem}><i style={{...t.legendDot, background:'var(--kc-hit)'}}/>Treffer</span>
              <span style={t.legendItem}><i style={{...t.legendDot, background:'var(--kc-miss)'}}/>Miss</span>
              <span style={t.legendItem}><i style={{...t.legendDot, background:'var(--kc-heli)'}}/>Heli</span>
            </div>
          </Card>
        </aside>

        {/* RIGHT — live counter + tap pad */}
        <main style={t.main}>
          {/* Counter strip */}
          <div style={t.counters}>
            <CounterCell label="Trefferrate" value={hidden ? '—' : `${rate}`} unit="%" tone="hit" big masked={hidden}/>
            <CounterCell label="Treffer"     value={hidden ? '—' : hits}   unit="" tone="hit" masked={hidden}/>
            <CounterCell label="Miss"        value={hidden ? '—' : misses} unit="" tone="miss" masked={hidden}/>
            <CounterCell label="Heli"        value={hidden ? '—' : helis}  unit="" tone="heli" muted={helis===0} masked={hidden}/>
          </div>

          {remaining !== null && (
            <div style={t.remaining}>
              <span>noch</span>
              <span style={t.remainingNum}>{remaining}</span>
              <span>Würfe · von {target}</span>
              <div style={t.progress}>
                <div style={{...t.progressFill, width:`${Math.min(100, (total/target)*100)}%`}}/>
              </div>
            </div>
          )}

          {hidden && (
            <div style={t.hiddenHint}>
              <DIcon.Bell/>
              <span>Trefferzahl verdeckt — du wirfst blind. Pro Wurf: Hit / Miss / Heli. Quote erscheint nach „Session beenden".</span>
            </div>
          )}

          {/* Tap pad */}
          <div style={t.padGrid}>
            <PadCell label="Treffer"  hint="space · 1" tone="hit"  big plus  onClick={tap(setHits, +1)}/>
            <PadCell label="Miss"     hint="m · 2"     tone="miss" big plus  onClick={tap(setMisses, +1)}/>
            <PadCell label="Heli"     hint="h · 3"     tone="heli" big plus  onClick={tap(setHelis, +1)}/>
            <PadCell label="Treffer"  hint="−"         tone="ghost" minus onClick={tap(setHits, -1)}/>
            <PadCell label="Miss"     hint="−"         tone="ghost" minus onClick={tap(setMisses, -1)}/>
            <PadCell label="Heli"     hint="−"         tone="ghost" minus onClick={tap(setHelis, -1)}/>
          </div>

          <div style={t.footRow}>
            <div style={t.footMeta}>
              <span><b>{total}</b> Würfe</span>
              <span><b>{(total * 1.2 / 60).toFixed(1)}</b> min</span>
              <span><b>{rate}%</b> live</span>
            </div>
            <div style={{display:'flex', gap:10}}>
              <SecondaryBtn icon={<DIcon.Pause/>}>Pause</SecondaryBtn>
              <SecondaryBtn tone="ghost" onClick={() => onRoute('dashboard')}>Abbrechen ohne Speichern</SecondaryBtn>
            </div>
          </div>
        </main>
      </div>
    </>
  );
}

// ---------- Bits ----------
function CounterCell({ label, value, unit, tone, big, muted, masked }) {
  const color =
    masked     ? 'var(--kc-fg-subtle)' :
    tone==='hit'  ? 'var(--kc-hit)'  :
    tone==='miss' ? 'var(--kc-miss)' :
    tone==='heli' ? 'var(--kc-heli)' :
    'var(--kc-fg)';
  return (
    <div style={{...t.counter, opacity: muted ? 0.4 : 1}}>
      <span style={t.counterLbl}>{label}</span>
      <span style={{...t.counterVal, color, fontSize: big ? 96 : 72}}>
        {value}{unit && <span style={t.counterUnit}>{unit}</span>}
      </span>
    </div>
  );
}

function PadCell({ label, hint, tone, big, plus, minus, onClick }) {
  const styles = {
    hit:   { background:'var(--kc-hit)',  color:'#fff' },
    miss:  { background:'var(--kc-miss)', color:'#fff' },
    heli:  { background:'var(--kc-heli)', color:'var(--kc-stone-900)' },
    ghost: { background:'var(--kc-bg-raised)', color:'var(--kc-fg)', boxShadow:'inset 0 0 0 1.5px var(--kc-stone-200)' },
  }[tone];
  return (
    <button style={{...t.pad, ...(big ? t.padBig : t.padSmall), ...styles}} onClick={onClick}>
      <div style={t.padLeft}>
        <span style={t.padLbl}>{label}</span>
        {hint && <span style={t.padHint}>{hint}</span>}
      </div>
      <span style={t.padSign}>{plus ? '+' : minus ? '−' : ''}</span>
    </button>
  );
}

const HISTORY = [
  'hit','hit','miss','hit','hit','miss','hit','miss','hit','hit',
  'hit','heli','hit','miss','hit','hit','hit','miss','hit','hit',
  'miss','hit','hit','hit','heli','miss','hit','hit','miss','hit',
  'hit','hit','miss','hit','hit','hit','hit'
];

const t = {
  split: { display:'grid', gridTemplateColumns:'340px 1fr', gap:20, padding:'24px 32px 32px', height:'calc(100% - 130px)' },
  aside: { display:'flex', flexDirection:'column', gap:14, overflowY:'auto', paddingRight:4 },
  main:  { display:'flex', flexDirection:'column', gap:18, minWidth:0 },

  modeLabel: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.1em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  modeRow: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:8, marginTop:8 },
  modeChip: { minHeight:52, padding:'0 12px', borderRadius:12, border:0, background:'var(--kc-bg-sunken)', color:'var(--kc-fg)', display:'flex', alignItems:'center', justifyContent:'center', gap:8, fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14, cursor:'pointer', boxShadow:'inset 0 0 0 1.5px transparent' },
  modeChipOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  fieldHead: { display:'flex', justifyContent:'space-between', alignItems:'baseline' },
  fieldLbl:  { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.1em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  fieldVal:  { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:24, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },
  range: { width:'100%', accentColor:'var(--kc-meadow-500)', marginTop:10 },
  tickRow: { display:'flex', justifyContent:'space-between', fontFamily:'var(--kc-font-mono)', fontSize:11, marginTop:2 },
  tick: {},
  thinLine: { border:0, borderTop:'1px solid var(--kc-line)', margin:'14px 0' },

  chipRow: { display:'flex', gap:6, flexWrap:'wrap', marginTop:8 },
  chip: { minHeight:38, padding:'0 14px', borderRadius:999, border:0, background:'var(--kc-bg-sunken)', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer', fontVariantNumeric:'tabular-nums' },
  chipOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  histHead: { display:'flex', justifyContent:'space-between', alignItems:'baseline' },
  histMeta: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)' },
  histStrip: { display:'grid', gridTemplateColumns:'repeat(20, 1fr)', gap:3, marginTop:10 },
  histCell: { width:'100%', aspectRatio:'1 / 1', borderRadius:3, background:'var(--kc-stone-100)' },
  histTone: {
    hit:  { background:'var(--kc-hit)' },
    miss: { background:'var(--kc-miss)' },
    heli: { background:'var(--kc-heli)' },
  },
  legendRow: { display:'flex', gap:14, marginTop:10 },
  legendItem: { display:'flex', alignItems:'center', gap:6, fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)' },
  legendDot: { width:10, height:10, borderRadius:3, display:'inline-block' },

  counters: { display:'grid', gridTemplateColumns:'1.6fr 1fr 1fr 1fr', gap:14, padding:'4px 0' },
  counter: { background:'var(--kc-bg-raised)', borderRadius:16, padding:'14px 20px', display:'flex', flexDirection:'column', gap:4, boxShadow:'var(--kc-shadow-1)' },
  counterLbl: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  counterVal: { fontFamily:'var(--kc-font-ui)', fontWeight:800, lineHeight:0.9, letterSpacing:'-0.04em', fontVariantNumeric:'tabular-nums' },
  counterUnit: { fontSize:24, fontWeight:600, color:'var(--kc-fg-muted)', marginLeft:4 },

  remaining: { display:'flex', alignItems:'center', gap:14, padding:'12px 18px', borderRadius:14, background:'var(--kc-bg-sunken)', color:'var(--kc-fg-muted)', fontSize:14 },
  remainingNum: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:32, color:'var(--kc-fg)', letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },
  progress: { flex:1, height:8, background:'var(--kc-stone-100)', borderRadius:999, overflow:'hidden' },
  progressFill: { height:'100%', background:'var(--kc-meadow-500)', borderRadius:999 },

  hiddenHint: { display:'flex', alignItems:'center', gap:10, padding:'10px 14px', borderRadius:12, background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)', fontSize:13 },

  padGrid: { display:'grid', gridTemplateColumns:'repeat(3, 1fr)', gridTemplateRows:'1fr 1fr', gap:14, flex:1 },
  pad: { border:0, borderRadius:18, fontFamily:'var(--kc-font-ui)', display:'flex', alignItems:'center', justifyContent:'space-between', padding:'0 24px', cursor:'pointer', boxShadow:'var(--kc-shadow-1)' },
  padBig: { minHeight:160 },
  padSmall: { minHeight:80 },
  padLeft: { display:'flex', flexDirection:'column', gap:4, textAlign:'left' },
  padLbl: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:28, letterSpacing:'-0.02em', fontVariationSettings:'"opsz" 36' },
  padHint: { fontFamily:'var(--kc-font-mono)', fontSize:11, opacity:0.8, letterSpacing:'0.04em' },
  padSign: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:64, lineHeight:1, opacity:0.9 },

  footRow: { display:'flex', justifyContent:'space-between', alignItems:'center', paddingTop:4 },
  footMeta: { display:'flex', gap:18, fontFamily:'var(--kc-font-mono)', fontSize:13, color:'var(--kc-fg-muted)' },
};

window.TrainingScreen = TrainingScreen;
