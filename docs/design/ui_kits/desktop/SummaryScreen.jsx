/* global React, DIcon, TopBar, PrimaryBtn, SecondaryBtn, Card, CardHeader */
// =====================================================================
// Summary — Session-Ergebnis, parallel zu mobile/SummaryScreen.
//   Sniper: Trefferquote als hero, multi-distance breakdown
//   Finisseur: Stöcke-genutzt + Königswurf, Strafkubbs etc.
//   Linke Spalte: Verdict-Card mit grosser Zahl
//   Rechte Spalte: Detail-Tabelle + Actions
// =====================================================================

const { useState: useSumState } = React;

function SummaryScreen({ onRoute, kind: kindProp }) {
  const [kind, setKind] = useSumState(kindProp || 'sniper');   // 'sniper' | 'finisseur'

  // Mock data
  const sniperData = {
    breakdown: [
      { distance: 8.0, hits: 18, misses: 9, helis: 1 },
      { distance: 6.5, hits: 7,  misses: 4, helis: 0 },
      { distance: 4.0, hits: 3,  misses: 1, helis: 0 },
    ],
    duration: '14:32',
    startedAt: '18:04',
  };
  const finData = {
    config: '7 / 3',
    success: true,
    sticksUsed: 5,
    kingHit: true,
    kingStyle: 'oben',
    penalties: 0,
    helis: 0,
    duration: '4:12',
    startedAt: '19:42',
  };

  const d = kind === 'sniper' ? sniperData : finData;

  const sniperTotals = kind === 'sniper'
    ? d.breakdown.reduce((a, b) => ({
        hits:   a.hits   + b.hits,
        misses: a.misses + b.misses,
        helis:  a.helis  + b.helis,
      }), { hits:0, misses:0, helis:0 })
    : null;
  const total = sniperTotals ? sniperTotals.hits + sniperTotals.misses + sniperTotals.helis : 0;
  const rate  = total ? Math.round(100 * sniperTotals.hits / total) : 0;

  return (
    <>
      <TopBar
        eyebrow="Session beendet · gerade eben"
        title={kind === 'sniper' ? 'Sniper-Session · Übersicht' : 'Finisseur · Sauber gefinisht'}
        subtitle={kind === 'sniper'
          ? `${d.breakdown.length} Distanzen · ${total} Würfe · gestartet ${d.startedAt} · gespielt ${d.duration}`
          : `Konfig ${d.config} · 6 Stöcke max · gestartet ${d.startedAt} · gespielt ${d.duration}`}
        right={<>
          <div style={su.kindSwitch}>
            {[['sniper','Sniper'], ['finisseur','Finisseur']].map(([k, lbl]) => (
              <button key={k} style={{...su.kindBtn, ...(kind===k ? su.kindBtnOn : {})}} onClick={() => setKind(k)}>{lbl}</button>
            ))}
          </div>
        </>}
      />

      <div style={su.body}>
        {/* Verdict hero strip */}
        <div style={{...su.verdict, background: kind === 'sniper' ? 'var(--kc-meadow-600)' : (d.success ? 'var(--kc-meadow-600)' : 'var(--kc-stone-700)')}}>
          <div style={su.verdictLeft}>
            <div style={su.verdictEyebrow}>
              {kind === 'sniper' ? 'Trefferquote · Session' : (d.success ? 'Sauber gefinisht' : 'Nicht geschafft')}
            </div>
            {kind === 'sniper' ? (
              <div style={su.verdictBig}>
                {rate}<span style={su.verdictUnit}>%</span>
              </div>
            ) : (
              <div style={su.verdictBig}>
                {d.sticksUsed}<span style={su.verdictUnit}>/ 6</span>
              </div>
            )}
            <div style={su.verdictSub}>
              {kind === 'sniper'
                ? `${total} Würfe · ${sniperTotals.hits} Treffer · ${sniperTotals.misses} Miss · ${sniperTotals.helis} Heli`
                : `Königswurf ${d.kingHit ? `· ${d.kingStyle} durch` : 'verfehlt'} · ${d.penalties} Strafkubbs · ${d.helis} Heli`}
            </div>
          </div>
          <div style={su.verdictRight}>
            <div style={su.miniRow}><span style={su.miniLbl}>Dauer</span><span style={su.miniVal}>{d.duration}</span></div>
            <div style={su.miniRow}><span style={su.miniLbl}>Start</span><span style={su.miniVal}>{d.startedAt}</span></div>
            {kind === 'sniper'
              ? <div style={su.miniRow}><span style={su.miniLbl}>Würfe/min</span><span style={su.miniVal}>{(total/14.5).toFixed(1)}</span></div>
              : <div style={su.miniRow}><span style={su.miniLbl}>ELO</span><span style={su.miniVal}>+8</span></div>}
          </div>
        </div>

        <div style={su.split}>
          {/* Detail */}
          <div style={su.col}>
            {kind === 'sniper' ? (
              <Card padding={0}>
                <div style={{padding:'18px 22px 8px'}}>
                  <CardHeader eyebrow="Aufschlüsselung" title="Pro Distanz"
                              right={<span style={su.runde}>{d.breakdown.length} Blöcke</span>}/>
                </div>
                <table style={su.table}>
                  <thead>
                    <tr>
                      <th style={{...su.th, textAlign:'left'}}>Distanz</th>
                      <th style={{...su.th, textAlign:'left'}}>Quote</th>
                      <th style={{...su.th, textAlign:'right'}}>Treffer</th>
                      <th style={{...su.th, textAlign:'right'}}>Miss</th>
                      <th style={{...su.th, textAlign:'right'}}>Heli</th>
                      <th style={{...su.th, textAlign:'right'}}>Würfe</th>
                    </tr>
                  </thead>
                  <tbody>
                    {d.breakdown.map((b, i) => {
                      const t = b.hits + b.misses + b.helis;
                      const r = t ? Math.round(100 * b.hits / t) : 0;
                      return (
                        <tr key={i}>
                          <td style={su.td}><span style={su.distMeters}>{b.distance.toFixed(1)} m</span></td>
                          <td style={su.td}>
                            <div style={su.distTrack}>
                              <div style={{...su.distFill, width:`${r}%`}}/>
                              <span style={su.distRateOver}>{r} %</span>
                            </div>
                          </td>
                          <td style={{...su.td, textAlign:'right'}}><span style={{...su.numCell, color:'var(--kc-hit)'}}>{b.hits}</span></td>
                          <td style={{...su.td, textAlign:'right'}}><span style={{...su.numCell, color:'var(--kc-miss)'}}>{b.misses}</span></td>
                          <td style={{...su.td, textAlign:'right'}}><span style={{...su.numCell, color: b.helis ? 'var(--kc-heli)' : 'var(--kc-fg-subtle)'}}>{b.helis}</span></td>
                          <td style={{...su.td, textAlign:'right'}}><span style={su.tdN}>{t}</span></td>
                        </tr>
                      );
                    })}
                    <tr style={{background:'var(--kc-bg-sunken)'}}>
                      <td style={{...su.td, fontFamily:'var(--kc-font-mono)', fontSize:11, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-fg-muted)'}}>Gesamt</td>
                      <td style={su.td}><span style={{...su.distMeters, color:'var(--kc-meadow-700)'}}>{rate} %</span></td>
                      <td style={{...su.td, textAlign:'right'}}><span style={su.totalCell}>{sniperTotals.hits}</span></td>
                      <td style={{...su.td, textAlign:'right'}}><span style={su.totalCell}>{sniperTotals.misses}</span></td>
                      <td style={{...su.td, textAlign:'right'}}><span style={su.totalCell}>{sniperTotals.helis}</span></td>
                      <td style={{...su.td, textAlign:'right'}}><span style={su.totalCell}>{total}</span></td>
                    </tr>
                  </tbody>
                </table>
              </Card>
            ) : (
              <Card padding={22}>
                <CardHeader eyebrow="Verlauf · 5 Stöcke benötigt" title="Per-Stick Log"/>
                <div style={su.stickList}>
                  {[
                    { i:1, label:'4 Feldkubbs', t:'1:42', tone:'hit' },
                    { i:2, label:'2 Feldkubbs + 1 Heli', t:'1:08', tone:'heli' },
                    { i:3, label:'1 Feldkubb', t:'1:54', tone:'hit' },
                    { i:4, label:'8 m – Basis getroffen', t:'2:12', tone:'hit' },
                    { i:5, label:'König · oben durch · Treffer', t:'0:32', tone:'king' },
                    { i:6, label:'nicht benötigt', t:'—', tone:'skipped' },
                  ].map(s => (
                    <div key={s.i} style={{...su.stickRow, ...(s.tone === 'skipped' ? {opacity:0.4} : {})}}>
                      <span style={su.stickIdx}>Stock {s.i}</span>
                      <span style={{...su.stickPip, background: PIP[s.tone]}}/>
                      <span style={su.stickLabel}>{s.label}</span>
                      <span style={su.stickTime}>{s.t}</span>
                    </div>
                  ))}
                </div>
              </Card>
            )}

            <Card padding={20}>
              <CardHeader eyebrow="Auswirkung" title="Statistik aktualisiert"/>
              <div style={su.impactGrid}>
                <Impact label="Saison-Quote" before="62 %" after="64 %" delta="+2 %" up/>
                <Impact label={kind==='sniper' ? 'Streak 8 m' : 'Sauber-Quote'} before={kind==='sniper'?'18':'58 %'} after={kind==='sniper'?'22':'63 %'} delta={kind==='sniper'?'+4':'+5 %'} up/>
                <Impact label="ELO" before="1275" after="1283" delta="+8" up/>
                <Impact label={kind==='sniper'?'4 m Treffer':'Königs-Quote'} before={kind==='sniper'?'93 %':'71 %'} after={kind==='sniper'?'94 %':'73 %'} delta={kind==='sniper'?'+1 %':'+2 %'} up/>
              </div>
            </Card>
          </div>

          {/* Actions side */}
          <div style={su.col}>
            <Card padding={22}>
              <CardHeader eyebrow="Aktionen" title="Was möchtest du tun?"/>
              <div style={su.actionList}>
                <PrimaryBtn icon={<DIcon.Plus/>} size="lg" onClick={() => onRoute && onRoute('dashboard')}>Speichern & weiter</PrimaryBtn>
                <SecondaryBtn tone="default" icon={<DIcon.Plus/>} onClick={() => onRoute && onRoute('training')}>Speichern + neue Session</SecondaryBtn>
                <SecondaryBtn tone="ghost" onClick={() => onRoute && onRoute('stats')}>Zu deiner Statistik</SecondaryBtn>
                <hr style={su.thinLine}/>
                <SecondaryBtn tone="ghost" icon={<DIcon.Undo/>}>Letzten Wurf bearbeiten</SecondaryBtn>
                <button style={su.discardBtn} onClick={() => onRoute && onRoute('dashboard')}>Verwerfen — nicht speichern</button>
              </div>
            </Card>

            <Card padding={20}>
              <CardHeader eyebrow="Teilen" title="Club & Freunde"/>
              <p style={su.shareNote}>
                Schick dein Ergebnis an dein Team oder poste in den Club-Channel.
              </p>
              <div style={su.shareRow}>
                <button style={su.shareChip}><span style={su.shareAv}>VL</span><span>Vinz</span></button>
                <button style={su.shareChip}><span style={su.shareAv}>PG</span><span>Pia</span></button>
                <button style={su.shareChip}><span style={su.shareAv}>TK</span><span>Tobi</span></button>
                <button style={{...su.shareChip, background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)'}}><span>BKC</span></button>
              </div>
            </Card>
          </div>
        </div>
      </div>
    </>
  );
}

function Impact({ label, before, after, delta, up }) {
  return (
    <div style={su.impact}>
      <div style={su.impactLbl}>{label}</div>
      <div style={su.impactRow}>
        <span style={su.impactBefore}>{before}</span>
        <span style={su.impactArrow}>→</span>
        <span style={su.impactAfter}>{after}</span>
      </div>
      <span style={{...su.impactDelta, color: up ? 'var(--kc-meadow-600)' : 'var(--kc-miss)'}}>{up ? '▲' : '▼'} {delta}</span>
    </div>
  );
}

const PIP = {
  hit:     'var(--kc-meadow-500)',
  heli:    'var(--kc-heli)',
  penalty: 'var(--kc-penalty)',
  king:    'var(--kc-king)',
  skipped: 'var(--kc-stone-200)',
};

const su = {
  kindSwitch: { display:'flex', gap:4, background:'var(--kc-bg-sunken)', padding:4, borderRadius:999 },
  kindBtn: { minHeight:36, padding:'0 14px', borderRadius:999, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer' },
  kindBtnOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  body: { padding:'24px 40px 48px', display:'flex', flexDirection:'column', gap:20, maxWidth:1280 },

  verdict: { borderRadius:20, padding:'28px 32px', color:'var(--kc-chalk-50)', display:'flex', justifyContent:'space-between', alignItems:'center', gap:32, minHeight:180 },
  verdictLeft: { flex:1, minWidth:0 },
  verdictEyebrow: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:700, letterSpacing:'0.1em', textTransform:'uppercase', opacity:0.85 },
  verdictBig: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:128, lineHeight:0.85, letterSpacing:'-0.05em', marginTop:6, fontVariantNumeric:'tabular-nums', display:'flex', alignItems:'baseline', gap:14 },
  verdictUnit: { fontSize:32, fontWeight:600, opacity:0.7, letterSpacing:'-0.02em' },
  verdictSub: { fontSize:15, opacity:0.9, marginTop:12, maxWidth:600 },

  verdictRight: { display:'flex', flexDirection:'column', gap:10, minWidth:200, alignItems:'stretch' },
  miniRow: { display:'flex', justifyContent:'space-between', alignItems:'baseline', padding:'8px 0', borderTop:'1px solid rgba(255,255,255,0.18)' },
  miniLbl: { fontFamily:'var(--kc-font-mono)', fontSize:11, letterSpacing:'0.06em', textTransform:'uppercase', opacity:0.7 },
  miniVal: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:18, fontVariantNumeric:'tabular-nums', letterSpacing:'-0.02em' },

  split: { display:'grid', gridTemplateColumns:'1.6fr 1fr', gap:18 },
  col:   { display:'flex', flexDirection:'column', gap:18, minWidth:0 },

  table: { width:'100%', borderCollapse:'collapse', fontFamily:'var(--kc-font-ui)' },
  th: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--kc-fg-muted)', padding:'8px 22px', textAlign:'right', borderTop:'1px solid var(--kc-line)' },
  td: { padding:'12px 22px', borderTop:'1px solid var(--kc-line)' },
  distMeters: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:18, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },
  distTrack: { position:'relative', height:24, background:'var(--kc-stone-100)', borderRadius:6, overflow:'hidden', minWidth:120 },
  distFill: { height:'100%', background:'linear-gradient(90deg, var(--kc-meadow-400), var(--kc-meadow-600))' },
  distRateOver: { position:'absolute', inset:0, display:'grid', placeItems:'center', fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:700, color:'var(--kc-fg)', mixBlendMode:'difference', filter:'invert(1)' },
  numCell: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:16, fontVariantNumeric:'tabular-nums' },
  totalCell: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:16, fontVariantNumeric:'tabular-nums' },
  tdN: { fontFamily:'var(--kc-font-mono)', fontSize:13, color:'var(--kc-fg-muted)' },

  stickList: { display:'flex', flexDirection:'column', marginTop:8 },
  stickRow: { display:'grid', gridTemplateColumns:'80px 14px 1fr auto', gap:14, alignItems:'center', padding:'12px 0', borderTop:'1px solid var(--kc-line)' },
  stickIdx: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  stickPip: { width:10, height:10, borderRadius:3 },
  stickLabel: { fontWeight:600, fontSize:14 },
  stickTime: { fontFamily:'var(--kc-font-mono)', fontSize:12, color:'var(--kc-fg-muted)', fontVariantNumeric:'tabular-nums' },

  impactGrid: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:12, marginTop:8 },
  impact: { padding:'12px 14px', borderRadius:12, background:'var(--kc-bg-sunken)', display:'flex', flexDirection:'column', gap:4 },
  impactLbl: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  impactRow: { display:'flex', alignItems:'baseline', gap:8 },
  impactBefore: { fontFamily:'var(--kc-font-mono)', fontSize:13, color:'var(--kc-fg-muted)', fontVariantNumeric:'tabular-nums' },
  impactArrow: { fontFamily:'var(--kc-font-mono)', fontSize:13, color:'var(--kc-fg-muted)' },
  impactAfter: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:22, fontVariantNumeric:'tabular-nums', letterSpacing:'-0.02em' },
  impactDelta: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:700 },

  actionList: { display:'flex', flexDirection:'column', gap:10, marginTop:8 },
  thinLine: { border:0, borderTop:'1px solid var(--kc-line)', margin:'8px 0' },
  discardBtn: { padding:'12px 14px', borderRadius:10, border:0, background:'transparent', color:'var(--kc-miss)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer', textAlign:'left', textDecoration:'underline', textUnderlineOffset:3 },

  shareNote: { color:'var(--kc-fg-muted)', fontSize:13, lineHeight:1.5, margin:'8px 0 12px' },
  shareRow: { display:'flex', gap:8, flexWrap:'wrap' },
  shareChip: { display:'inline-flex', alignItems:'center', gap:8, padding:'8px 14px 8px 8px', borderRadius:999, border:0, background:'var(--kc-bg-sunken)', color:'var(--kc-fg)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer' },
  shareAv: { width:24, height:24, borderRadius:999, background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)', fontSize:10, fontWeight:700, display:'grid', placeItems:'center' },

  runde: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.06em', textTransform:'uppercase' },
};

window.SummaryScreen = SummaryScreen;
