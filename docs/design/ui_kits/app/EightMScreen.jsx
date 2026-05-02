/* global React, BK */
const { useState } = React;
const { Icon, AppBar } = BK;

// =====================================================================
// Screen: Sniper-Training (vormals 8m-Modus)
// Eye-Toggle: blendet NUR die getätigten Würfe aus (Treffer/Miss/Heli).
// Distanz, eingestellte Zielzahl und "remaining" bleiben sichtbar.
// =====================================================================
function SniperTrainingScreen({ onBack, onFinish }) {
  const [hits, setHits]       = useState(11);
  const [misses, setMisses]   = useState(6);
  const [helis, setHelis]     = useState(0);
  const [distance, setDistance] = useState(8.0);
  const [target, setTarget]   = useState(50);    // optional target throws
  const [showSheet, setShowSheet] = useState(false);
  const [hideMade, setHideMade] = useState(false);

  const total = hits + misses + helis;
  const remaining = target ? Math.max(0, target - total) : null;

  const tap = (setter, delta, min = 0) => () => {
    setter(v => Math.max(min, v + delta));
    if (navigator.vibrate) navigator.vibrate(8);
  };

  return (
    <div style={s.screen}>
      <AppBar
        eyebrow="Sniper-Training"
        title={`${distance.toFixed(1)} m`}
        onBack={onBack}
        right={
          <div style={{display:'flex'}}>
            <button style={s.iconBtn} onClick={() => setHideMade(v => !v)} aria-label={hideMade ? 'Treffer einblenden' : 'Treffer ausblenden'} aria-pressed={hideMade}>
              {hideMade ? <Icon.EyeOff/> : <Icon.Eye/>}
            </button>
            <button style={s.iconBtn} onClick={() => setShowSheet(true)} aria-label="Einstellungen"><Icon.Settings/></button>
          </div>
        }
      />

      {/* Counter strip — Made counters versteckt wenn hideMade */}
      <section style={s.counterStrip}>
        {hideMade ? (
          <>
            <Stat label="Treffer" value="—" tone="hit" masked/>
            <Stat label="Miss" value="—" tone="miss" masked/>
            <Stat label="Heli" value="—" tone="heli" masked/>
          </>
        ) : (
          <>
            <Stat label="Treffer" value={hits} tone="hit" />
            <Stat label="Miss" value={misses} tone="miss" />
            <Stat label="Heli" value={helis} tone="heli" muted={helis === 0} />
          </>
        )}
      </section>

      {/* Remaining IMMER sichtbar (wenn Ziel gesetzt) */}
      {target && (
        <div style={s.remaining}>
          <span>noch</span>
          <span style={s.remainingNum}>{remaining}</span>
          <span>Würfe · von {target}</span>
        </div>
      )}

      {hideMade && (
        <div style={s.hiddenHint}>
          <Icon.EyeOff/>
          <span>Trefferzahl verdeckt — du wirfst blind.</span>
        </div>
      )}

      {/* Tap-Pad — primary input */}
      <section style={s.padGrid}>
        <PadButton label="Hit" sign="+" tone="hit" onClick={tap(setHits, +1)} />
        <PadButton label="Hit" sign="−" tone="ghost" onClick={tap(setHits, -1)} />
        <PadButton label="Miss" sign="+" tone="miss" onClick={tap(setMisses, +1)} />
        <PadButton label="Miss" sign="−" tone="ghost" onClick={tap(setMisses, -1)} />
        <PadButton label="Heli" sign="+" tone="heli" onClick={tap(setHelis, +1)} />
        <PadButton label="Heli" sign="−" tone="ghost" onClick={tap(setHelis, -1)} />
      </section>

      <button style={s.endBtn} onClick={onFinish}>Session beenden</button>

      {showSheet && (
        <SettingsSheet
          distance={distance}
          target={target}
          onChange={(d, t) => { setDistance(d); setTarget(t); }}
          onClose={() => setShowSheet(false)}
        />
      )}
    </div>
  );
}

// ---- bits ----
function Stat({ label, value, tone, muted, masked }) {
  const color =
    tone === 'hit'  ? 'var(--bk-hit)'  :
    tone === 'miss' ? 'var(--bk-miss)' :
    tone === 'heli' ? 'var(--bk-heli)' :
    'var(--bk-fg)';
  return (
    <div style={{display:'flex', flexDirection:'column', gap:2, opacity: muted ? 0.45 : 1}}>
      <span style={s.statLbl}>{label}</span>
      <span style={{...s.statVal, color: masked ? 'var(--bk-fg-subtle)' : color}}>{value}</span>
    </div>
  );
}

function PadButton({ label, sign, tone, onClick }) {
  const styles = {
    hit:   { background: 'var(--bk-hit)',  color: '#fff' },
    miss:  { background: 'var(--bk-miss)', color: '#fff' },
    heli:  { background: 'var(--bk-heli)', color: 'var(--bk-stone-900)' },
    ghost: { background: 'var(--bk-bg-raised)', color: 'var(--bk-fg)', boxShadow: 'inset 0 0 0 2px var(--bk-line)' },
  }[tone];
  return (
    <button style={{...s.pad, ...styles}} onClick={onClick}>
      <span style={s.padLbl}>{label}</span>
      <span style={s.padSign}>{sign}</span>
    </button>
  );
}

function SettingsSheet({ distance, target, onChange, onClose }) {
  const [d, setD] = useState(distance);
  const [t, setT] = useState(target);
  return (
    <div style={s.sheetBackdrop} onClick={onClose}>
      <div style={s.sheet} onClick={e => e.stopPropagation()}>
        <div style={s.sheetGrabber}/>
        <div style={s.sheetHead}>
          <h2 style={s.sheetTitle}>Einstellungen</h2>
          <button style={s.iconBtn} onClick={onClose}><Icon.Close/></button>
        </div>

        <label style={s.field}>
          <span style={s.fieldLabel}>Distanz</span>
          <span style={s.fieldValue}>{d.toFixed(1)} m</span>
        </label>
        <input type="range" min="4" max="8" step="0.5" value={d}
               onChange={e => setD(parseFloat(e.target.value))}
               style={s.range}/>
        <div style={s.tickRow}>
          {[4,5,6,7,8].map(n => <span key={n} style={{...s.tick, color: Math.round(d) === n ? 'var(--bk-fg)' : 'var(--bk-fg-muted)'}}>{n}.0</span>)}
        </div>

        <label style={s.field}>
          <span style={s.fieldLabel}>Ziel-Wurfzahl</span>
          <span style={s.fieldValue}>{t || 'kein Ziel'}</span>
        </label>
        <div style={s.targetRow}>
          {[null, 25, 50, 100, 200].map((n, i) => (
            <button key={i}
                    style={{...s.targetChip, ...(t === n ? s.targetChipOn : {})}}
                    onClick={() => setT(n)}>
              {n ?? '∞'}
            </button>
          ))}
        </div>

        <button style={s.applyBtn} onClick={() => { onChange(d, t); onClose(); }}>Übernehmen</button>
      </div>
    </div>
  );
}

// ---- styles ----
const s = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)' },
  topbar: { display:'flex', alignItems:'center', justifyContent:'space-between', padding:'54px 12px 6px' },
  iconBtn: { width:48, height:48, display:'grid', placeItems:'center', background:'transparent', border:0, borderRadius:12, color:'var(--bk-fg)', cursor:'pointer' },
  topTitle: { textAlign:'center', display:'flex', flexDirection:'column', gap:2 },
  topEyebrow: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  topDistance: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:28, lineHeight:1, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },

  counterStrip: { display:'grid', gridTemplateColumns:'repeat(3, 1fr)', gap:8, padding:'10px 16px 4px' },
  statLbl: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  statVal: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:38, lineHeight:1, letterSpacing:'-0.03em', fontVariantNumeric:'tabular-nums' },

  remaining: { display:'flex', justifyContent:'center', alignItems:'baseline', gap:10, padding:'12px 16px 0', color:'var(--bk-fg-muted)', fontSize:14 },
  remainingNum: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:34, color:'var(--bk-fg)', letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },

  padGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:10, padding:'18px 16px 12px', flex:1, alignContent:'center' },
  pad: { minHeight:84, borderRadius:18, border:0, fontFamily:'var(--bk-font-display)', fontWeight:700, display:'flex', alignItems:'center', justifyContent:'space-between', padding:'0 22px', cursor:'pointer' },
  padLbl: { fontSize:20 },
  padSign: { fontSize:36, fontWeight:800, lineHeight:1 },

  endBtn: { margin:'0 16px 16px', minHeight:48, borderRadius:12, border:0, background:'transparent', color:'var(--bk-fg-muted)', fontFamily:'var(--bk-font-display)', fontSize:15, fontWeight:600, cursor:'pointer', textDecoration:'underline', textUnderlineOffset:4 },
  hiddenHint: { display:'flex', alignItems:'center', justifyContent:'center', gap:8, padding:'10px 16px 0', color:'var(--bk-fg-muted)', fontSize:13 },

  // sheet
  sheetBackdrop: { position:'absolute', inset:0, background:'rgba(12,11,7,0.45)', display:'flex', alignItems:'flex-end', zIndex:10 },
  sheet: { width:'100%', background:'var(--bk-bg-raised)', borderTopLeftRadius:24, borderTopRightRadius:24, padding:'10px 18px 32px', display:'flex', flexDirection:'column', gap:10 },
  sheetGrabber: { width:36, height:4, background:'var(--bk-stone-200)', borderRadius:999, alignSelf:'center', marginBottom:6 },
  sheetHead: { display:'flex', alignItems:'center', justifyContent:'space-between' },
  sheetTitle: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:22, margin:0, letterSpacing:'-0.02em' },
  field: { display:'flex', justifyContent:'space-between', alignItems:'baseline', marginTop:6 },
  fieldLabel: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  fieldValue: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:22, fontVariantNumeric:'tabular-nums' },
  range: { width:'100%', accentColor:'var(--bk-meadow-500)', height:4 },
  tickRow: { display:'flex', justifyContent:'space-between', fontFamily:'var(--bk-font-mono)', fontSize:11, marginTop:-2 },
  tick: {},
  targetRow: { display:'flex', gap:8, flexWrap:'wrap', marginTop:6 },
  targetChip: { minHeight:48, padding:'0 18px', borderRadius:999, border:0, background:'var(--bk-bg-sunken)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-display)', fontWeight:600, fontSize:15, cursor:'pointer' },
  targetChipOn: { background:'var(--bk-stone-900)', color:'var(--bk-chalk-50)' },
  applyBtn: { marginTop:14, minHeight:54, borderRadius:14, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer' },
};

window.SniperTrainingScreen = SniperTrainingScreen;
// keep backward export for existing references
window.EightMScreen = SniperTrainingScreen;
