/* global React, BK */
const { Icon, AppBar } = BK;

// =====================================================================
// Screen: Session Summary (post-session)
//   - Sniper: keine separate "Würfe"-Zeile (steckt im Verdict);
//             Treffer / Miss / Heli (richtig geschrieben)
//   - Wenn Sniper-Session über mehrere Distanzen geht, werden diese
//     einzeln aufgelistet (8.0 m | 6.5 m | 4.0 m je mit Hits/Miss/Heli)
//   - Finisseur: Königswurf, Strafkubbs, Heli, Dauer
// =====================================================================
function SummaryScreen({ kind = '8m', data, onSave, onDiscard, onBack, onRestart }) {
  // Default sample data for the kit canvas
  const d = data || (kind === '8m'
    ? {
        // multi-distance sample
        breakdown: [
          { distance: 8.0, hits: 18, misses: 9, helis: 1 },
          { distance: 6.5, hits: 7,  misses: 4, helis: 0 },
          { distance: 4.0, hits: 3,  misses: 1, helis: 0 },
        ],
        duration: '14:32',
      }
    : { config:'7/3', success:true, sticksUsed:5, kingHit:true, kingStyle:'oben', penalties:0, helis:0, duration:'4:12' });

  // Aggregate sniper totals from breakdown OR flat data
  const sniperTotals = (() => {
    if (kind !== '8m') return null;
    if (d.breakdown && d.breakdown.length) {
      const t = d.breakdown.reduce((a, b) => ({
        hits:   a.hits   + b.hits,
        misses: a.misses + b.misses,
        helis:  a.helis  + b.helis,
      }), { hits:0, misses:0, helis:0 });
      return t;
    }
    return { hits: d.hits||0, misses: d.misses||0, helis: d.helis||0 };
  })();

  const total8m = sniperTotals ? sniperTotals.hits + sniperTotals.misses + sniperTotals.helis : 0;
  const rate    = total8m ? Math.round(100 * sniperTotals.hits / total8m) : 0;
  const multi   = kind === '8m' && d.breakdown && d.breakdown.length > 1;
  const distLabel = (() => {
    if (kind !== '8m') return null;
    if (multi) {
      const ds = d.breakdown.map(b => b.distance.toFixed(1) + ' m');
      return ds.join(' · ');
    }
    if (d.breakdown && d.breakdown.length === 1) return d.breakdown[0].distance.toFixed(1) + ' m';
    return (d.distance || 8).toFixed(1) + ' m';
  })();

  return (
    <div style={su.screen}>
      <AppBar
        eyebrow="Session beendet"
        title={kind === '8m' ? `Sniper · ${distLabel}` : `Finisseur · ${d.config}`}
        onBack={onBack}
      />

      {/* Verdict */}
      <div style={{...su.verdict, background: kind === '8m' ? 'var(--bk-meadow-500)' : (d.success ? 'var(--bk-meadow-500)' : 'var(--bk-stone-700)')}}>
        {kind === '8m' ? (
          <>
            <div style={su.verdictBigNum}>{rate}<span style={{fontSize:'40%'}}> %</span></div>
            <div style={su.verdictSub}>Trefferquote · {total8m} Würfe in {d.duration}</div>
          </>
        ) : (
          <>
            <div style={su.verdictTag}>{d.success ? 'Sauber finished' : 'Nicht geschafft'}</div>
            <div style={su.verdictBigNum}>{d.sticksUsed}<span style={{fontSize:'40%'}}> / 6</span></div>
            <div style={su.verdictSub}>Stöcke benötigt · {d.duration}</div>
          </>
        )}
      </div>

      {/* Body */}
      <div style={su.body}>
        {kind === '8m' ? (
          multi ? (
            <>
              <div style={su.section}>Pro Distanz</div>
              <div style={su.distList}>
                {d.breakdown.map((b, i) => {
                  const t = b.hits + b.misses + b.helis;
                  const r = t ? Math.round(100 * b.hits / t) : 0;
                  return (
                    <div key={i} style={su.distRow}>
                      <div style={su.distHead}>
                        <span style={su.distMeters}>{b.distance.toFixed(1)} m</span>
                        <span style={su.distRate}>{r} %</span>
                      </div>
                      <div style={su.distNumbers}>
                        <Pill tone="hit"  label="Treffer" value={b.hits}/>
                        <Pill tone="miss" label="Miss"    value={b.misses}/>
                        <Pill tone="heli" label="Heli"    value={b.helis} dim={b.helis === 0}/>
                      </div>
                    </div>
                  );
                })}
              </div>
              <div style={{height:6}}/>
              <Row label="Dauer" value={d.duration} mono/>
            </>
          ) : (
            <>
              <Row label="Treffer"     value={sniperTotals.hits}   tone="hit"/>
              <Row label="Miss"        value={sniperTotals.misses} tone="miss"/>
              <Row label="Heli"        value={sniperTotals.helis}  tone={sniperTotals.helis ? 'heli' : 'muted'}/>
              <Row label="Dauer"       value={d.duration} mono/>
            </>
          )
        ) : (
          <>
            <Row label="Königswurf"
                 value={d.kingHit ? `${d.kingStyle} durch · Treffer` : 'verfehlt'}
                 tone={d.kingHit ? 'hit' : 'miss'}/>
            <Row label="Strafkubbs" value={d.penalties} tone={d.penalties ? 'penalty' : 'muted'}/>
            <Row label="Heli"       value={d.helis} tone={d.helis ? 'heli' : 'muted'}/>
            <Row label="Dauer"      value={d.duration} mono/>
          </>
        )}
      </div>

      {/* Actions — Verwerfen + Speichern gleich gross, dann Neue Session */}
      <div style={su.actions}>
        <button style={su.discard} onClick={onDiscard}>Verwerfen</button>
        <button style={su.save} onClick={onSave}>Speichern</button>
      </div>
      <button style={su.restart} onClick={onRestart}>
        <span style={{display:'inline-flex', alignItems:'center', gap:8}}>
          <Icon.Plus2/> Neue Session starten
        </span>
      </button>
      <div style={{height:24}}/>
    </div>
  );
}

function Row({ label, value, tone, mono }) {
  const color =
    tone === 'hit'     ? 'var(--bk-hit)' :
    tone === 'miss'    ? 'var(--bk-miss)' :
    tone === 'heli'    ? 'var(--bk-heli)' :
    tone === 'penalty' ? 'var(--bk-penalty)' :
    tone === 'muted'   ? 'var(--bk-fg-muted)' :
    'var(--bk-fg)';
  return (
    <div style={su.row}>
      <span style={su.rowLbl}>{label}</span>
      <span style={{...(mono ? su.rowMono : su.rowVal), color}}>{value}</span>
    </div>
  );
}

function Pill({ tone, label, value, dim }) {
  const color =
    tone === 'hit'  ? 'var(--bk-hit)' :
    tone === 'miss' ? 'var(--bk-miss)' :
    tone === 'heli' ? 'var(--bk-heli)' :
    'var(--bk-fg)';
  return (
    <div style={{...su.pill, opacity: dim ? 0.5 : 1}}>
      <span style={su.pillLbl}>{label}</span>
      <span style={{...su.pillVal, color}}>{value}</span>
    </div>
  );
}

const su = {
  screen: { display:'flex', flexDirection:'column', height:'100%', background:'var(--bk-bg)', color:'var(--bk-fg)', fontFamily:'var(--bk-font-body)', overflowY:'auto' },

  verdict: { margin:'10px 16px 14px', borderRadius:20, padding:'22px 18px 18px', color:'var(--bk-chalk-50)', display:'flex', flexDirection:'column', alignItems:'center', gap:4 },
  verdictTag: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', opacity:0.85 },
  verdictBigNum: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:90, lineHeight:0.9, letterSpacing:'-0.04em', fontVariantNumeric:'tabular-nums' },
  verdictSub: { fontSize:13, opacity:0.85, marginTop:2 },

  body: { padding:'4px 16px', flex:1, overflowY:'auto' },

  section: { fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)', padding:'4px 0 8px' },

  // Multi-distance breakdown
  distList: { display:'flex', flexDirection:'column', gap:8 },
  distRow: { background:'var(--bk-bg-raised)', borderRadius:14, padding:'12px 14px', display:'flex', flexDirection:'column', gap:10 },
  distHead: { display:'flex', justifyContent:'space-between', alignItems:'baseline' },
  distMeters: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:22, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },
  distRate: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:18, color:'var(--bk-meadow-600)', fontVariantNumeric:'tabular-nums' },
  distNumbers: { display:'grid', gridTemplateColumns:'repeat(3, 1fr)', gap:6 },
  pill: { display:'flex', flexDirection:'column', alignItems:'center', gap:2, padding:'8px 6px', background:'var(--bk-bg)', borderRadius:10 },
  pillLbl: { fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' },
  pillVal: { fontFamily:'var(--bk-font-display)', fontWeight:800, fontSize:22, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },

  // Single-distance row
  row: { display:'flex', justifyContent:'space-between', alignItems:'baseline', padding:'12px 0', borderBottom:'1px solid var(--bk-line)' },
  rowLbl: { fontSize:14, color:'var(--bk-fg-muted)' },
  rowVal: { fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:22, fontVariantNumeric:'tabular-nums' },
  rowMono: { fontFamily:'var(--bk-font-mono)', fontWeight:500, fontSize:17, fontVariantNumeric:'tabular-nums' },

  actions: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:10, padding:'10px 16px 8px' },
  discard: { minHeight:54, borderRadius:14, border:0, background:'var(--bk-danger)', color:'var(--bk-on-danger)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer' },
  save:    { minHeight:54, borderRadius:14, border:0, background:'var(--bk-primary)', color:'var(--bk-on-primary)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:17, cursor:'pointer' },
  restart: { margin:'4px 16px 0', minHeight:54, borderRadius:14, border:0, background:'var(--bk-bg-raised)', color:'var(--bk-fg)', boxShadow:'inset 0 0 0 2px var(--bk-line-strong)', fontFamily:'var(--bk-font-display)', fontWeight:700, fontSize:16, cursor:'pointer', display:'flex', alignItems:'center', justifyContent:'center', gap:8 },
};

window.SummaryScreen = SummaryScreen;
