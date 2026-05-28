/* global React, DIcon, TopBar, PrimaryBtn, SecondaryBtn, Card, CardHeader */
// =====================================================================
// Match — Live-Match Screen, the "make it shine" of the app.
//   Tabs: Lobby (pre-game) | Live (in-game) | Result (post-game)
//   In Live: links Pitch-Diagram, rechts Score + Per-Throw Log
// =====================================================================

const { useState: useMatchState } = React;

function MatchScreen({ onRoute }) {
  const [stage, setStage] = useMatchState('live');  // lobby | live | result
  return (
    <>
      <TopBar
        eyebrow={stage === 'lobby' ? 'Match-Lobby' : stage === 'live' ? 'Match · LIVE' : 'Match · Ergebnis'}
        title={stage === 'lobby' ? 'Marc & Vinz vs. BKC United A' : stage === 'result' ? 'Sieg · 3 : 2' : 'Halbsatz 4 / 5'}
        subtitle={stage === 'lobby'
          ? 'BKC Friday League · KW 21 · Runde 4 · Court 2 · startet um 20:15'
          : stage === 'result'
            ? 'Marc & Vinz · 9 min Spielzeit · 28 Würfe · 4 Heli · 0 Strafkubbs'
            : 'BKC Friday League · KW 21 · Court 2 · läuft seit 4:12'}
        right={<>
          <div style={m.stageSwitch}>
            {[['lobby','Lobby'], ['live','Live'], ['result','Ergebnis']].map(([k, label]) => (
              <button key={k} style={{...m.stageBtn, ...(stage === k ? m.stageBtnOn : {})}} onClick={() => setStage(k)}>
                {label}
              </button>
            ))}
          </div>
        </>}
      />

      {stage === 'lobby'  && <Lobby  onRoute={onRoute} onStart={() => setStage('live')}/>}
      {stage === 'live'   && <Live   onRoute={onRoute} onFinish={() => setStage('result')}/>}
      {stage === 'result' && <Result onRoute={onRoute} onRestart={() => setStage('lobby')}/>}
    </>
  );
}

// =====================================================================
// LOBBY
// =====================================================================
function Lobby({ onRoute, onStart }) {
  return (
    <div style={m.lobbyWrap}>
      <div style={m.lobbyTeams}>
        <TeamCard side="left"
          name="Marc & Vinz"
          initials="MV"
          color="var(--kc-meadow-600)"
          elo={1283}
          record="3 W · 1 N"
          form={['W','W','L','W']}
          players={[
            { initials:'MB', name:'Marc B.', elo:1283 },
            { initials:'VL', name:'Vinz L.', elo:1241 },
          ]}
          ready/>
        <div style={m.lobbyVs}>
          <div style={m.lobbyVsBig}>vs.</div>
          <div style={m.lobbyVsMeta}>Best of 5 · 6 Stöcke</div>
          <div style={m.lobbyVsClock}>20:15</div>
          <div style={m.lobbyVsClockSub}>startet · Court 2</div>
        </div>
        <TeamCard side="right"
          name="BKC United A"
          initials="UA"
          color="var(--kc-stone-900)"
          elo={1305}
          record="3 W · 1 N"
          form={['W','L','W','W']}
          players={[
            { initials:'JT', name:'Jonas T.', elo:1305 },
            { initials:'AV', name:'Anna V.',  elo:1298 },
          ]}
          ready/>
      </div>

      <div style={m.lobbyGrid}>
        <Card padding={22}>
          <CardHeader eyebrow="Direkter Vergleich" title="Letzte 5 Begegnungen"/>
          <div style={m.h2hList}>
            {[
              { date:'KW 17', home:'Marc & Vinz', away:'United A', score:'1:3', win:false },
              { date:'KW 11', home:'Marc & Vinz', away:'United A', score:'3:2', win:true  },
              { date:'KW 04', home:'United A', away:'Marc & Vinz', score:'2:3', win:true  },
              { date:'Tessin', home:'Marc & Vinz', away:'United A', score:'0:3', win:false },
              { date:'Spring', home:'United A', away:'Marc & Vinz', score:'3:1', win:false },
            ].map((h, i) => (
              <div key={i} style={m.h2hRow}>
                <span style={m.h2hDate}>{h.date}</span>
                <span style={m.h2hTeam}>{h.home}</span>
                <span style={m.h2hScore}>{h.score}</span>
                <span style={m.h2hTeam}>{h.away}</span>
                <span style={{...m.h2hBadge, background: h.win ? 'var(--kc-meadow-100)' : 'var(--kc-stone-100)', color: h.win ? 'var(--kc-meadow-700)' : 'var(--kc-fg-muted)'}}>{h.win ? 'Sieg' : 'N'}</span>
              </div>
            ))}
          </div>
        </Card>

        <Card padding={22}>
          <CardHeader eyebrow="Vor dem Match" title="Match-Setup"/>
          <SetupRow label="Format"        value="Best of 5 · 6 Stöcke"/>
          <SetupRow label="Halbsatz-Limit" value="6 Stöcke"/>
          <SetupRow label="Heli-Tracking"  value="Ja"      tone="meadow"/>
          <SetupRow label="Strafkubb-Regel" value="Schwedisch"/>
          <SetupRow label="Court"          value="Court 2 · Bern Stadion"/>
          <SetupRow label="Schiedsrichter" value="Sandra K."/>
          <div style={{display:'flex', gap:10, marginTop:18}}>
            <PrimaryBtn icon={<DIcon.Target/>} onClick={onStart}>Match starten</PrimaryBtn>
            <SecondaryBtn tone="default">Setup anpassen</SecondaryBtn>
          </div>
        </Card>
      </div>
    </div>
  );
}

function TeamCard({ side, name, initials, color, elo, record, form, players, ready }) {
  return (
    <div style={{...m.teamCard, alignItems: side === 'right' ? 'flex-end' : 'flex-start'}}>
      <div style={{...m.teamAvatar, background:color}}>{initials}</div>
      <div style={m.teamName}>{name}</div>
      <div style={m.teamMeta}>
        <span><b>{elo}</b> ELO</span>
        <span>·</span>
        <span>{record}</span>
      </div>
      <div style={{display:'flex', gap:4, marginTop:8}}>
        {form.map((f, i) => (
          <span key={i} style={{...m.formCell, background: f === 'W' ? 'var(--kc-meadow-500)' : 'var(--kc-stone-200)', color: f === 'W' ? '#fff' : 'var(--kc-fg-muted)'}}>{f}</span>
        ))}
      </div>
      <div style={m.teamPlayers}>
        {players.map((p, i) => (
          <div key={i} style={m.teamPlayer}>
            <span style={m.teamPlayerAv}>{p.initials}</span>
            <span style={m.teamPlayerName}>{p.name}</span>
            <span style={m.teamPlayerElo}>{p.elo}</span>
          </div>
        ))}
      </div>
      {ready && <div style={m.readyTag}><span style={m.greenDot}/>Bereit</div>}
    </div>
  );
}

function SetupRow({ label, value, tone }) {
  return (
    <div style={m.setupRow}>
      <span style={m.setupLbl}>{label}</span>
      <span style={{...m.setupVal, color: tone === 'meadow' ? 'var(--kc-meadow-700)' : 'var(--kc-fg)'}}>{value}</span>
    </div>
  );
}

// =====================================================================
// LIVE
// =====================================================================
function Live({ onRoute, onFinish }) {
  return (
    <div style={m.liveWrap}>
      {/* HEADER STRIP — score */}
      <div style={m.scoreStrip}>
        <ScoreSide name="Marc & Vinz" sub="MB · VL" score={2} initials="MV" you/>
        <div style={m.scoreCenter}>
          <div style={m.scoreSet}>Halbsatz 4 / 5</div>
          <div style={m.scoreTime}>04:12</div>
          <div style={m.scoreState}>läuft</div>
        </div>
        <ScoreSide name="BKC United A" sub="JT · AV" score={1} initials="UA"/>
      </div>

      <div style={m.liveSplit}>
        {/* Pitch diagram */}
        <Card padding={20}>
          <CardHeader eyebrow="Wurffeld · Live-Status"
                      title={'Du wirfst · Stock 4 / 6'}
                      right={<span style={m.liveLayoutTag}>Aufstellung Standard</span>}/>
          <Pitch/>
          <div style={m.pitchLegend}>
            <span style={m.legendItem}><i style={{...m.legendCube, background:'var(--kc-meadow-500)'}}/>stehend</span>
            <span style={m.legendItem}><i style={{...m.legendCube, background:'var(--kc-stone-300)', transform:'rotate(45deg)'}}/>liegend</span>
            <span style={m.legendItem}><i style={{...m.legendCube, background:'var(--kc-wood-400)'}}/>Strafkubb</span>
            <span style={m.legendItem}><i style={{...m.legendCube, background:'var(--kc-king)', borderRadius:'50%'}}/>König</span>
          </div>
        </Card>

        {/* Right side */}
        <div style={m.liveRight}>
          {/* Big counter — Stock-zähler */}
          <Card padding={20}>
            <div style={m.counterHead}>
              <div>
                <div style={m.counterEyebrow}>Stock</div>
                <div style={m.counterMain}>
                  <span style={m.counterBig}>4<span style={m.counterUnit}>/6</span></span>
                  <div style={m.counterSide}>
                    <div style={m.counterSideRow}><span style={m.counterSideLbl}>Stehend</span><span style={m.counterSideVal}>3</span></div>
                    <div style={m.counterSideRow}><span style={m.counterSideLbl}>Strafkubb</span><span style={{...m.counterSideVal, color:'var(--kc-wood-500)'}}>1</span></div>
                    <div style={m.counterSideRow}><span style={m.counterSideLbl}>König</span><span style={{...m.counterSideVal, color:'var(--kc-king)'}}>steht</span></div>
                  </div>
                </div>
              </div>
              <button style={m.undoBtn}>
                <DIcon.Undo/> Letzten Wurf zurück
              </button>
            </div>
          </Card>

          {/* Action pad */}
          <div style={m.actionPad}>
            <ActionBtn label="Treffer" sub="Kubb getroffen" tone="hit"/>
            <ActionBtn label="Miss"    sub="Daneben"        tone="miss"/>
            <ActionBtn label="Heli"    sub="Hubschrauber-Wurf" tone="heli"/>
            <ActionBtn label="Strafe"  sub="König früh getroffen" tone="penalty"/>
          </div>

          {/* Live throw log */}
          <Card padding={0}>
            <div style={{padding:'14px 18px 4px'}}>
              <CardHeader eyebrow="Per-Wurf Log" title="Halbsatz 4"
                          right={<span style={m.runde}>22 Würfe · 4 Heli</span>}/>
            </div>
            <ul style={m.log}>
              {LOG.map((l, i) => (
                <li key={i} style={{...m.logRow, ...(i === 0 ? m.logRowLatest : {})}}>
                  <span style={m.logIdx}>#{l.idx}</span>
                  <span style={{...m.logIcon, background: TONES[l.type].bg, color: TONES[l.type].fg}}>{TONES[l.type].label}</span>
                  <span style={m.logSub}>{l.player} · {l.note}</span>
                  <span style={m.logTime}>{l.t}</span>
                </li>
              ))}
            </ul>
          </Card>

          <div style={m.endRow}>
            <PrimaryBtn icon={<DIcon.Stop/>} onClick={onFinish}>Halbsatz beenden</PrimaryBtn>
            <SecondaryBtn tone="ghost" icon={<DIcon.Pause/>}>Time-Out</SecondaryBtn>
          </div>
        </div>
      </div>
    </div>
  );
}

const TONES = {
  hit:     { bg:'var(--kc-meadow-100)', fg:'var(--kc-meadow-700)', label:'TREF' },
  miss:    { bg:'var(--kc-stone-100)',  fg:'var(--kc-fg-muted)',   label:'MISS' },
  heli:    { bg:'var(--kc-wood-100)',   fg:'var(--kc-wood-600)',   label:'HELI' },
  penalty: { bg:'#fae2e6',              fg:'var(--kc-penalty)',    label:'STRAF' },
  king:    { bg:'#fbe9c2',              fg:'var(--kc-wood-600)',   label:'KÖNG' },
};

const LOG = [
  { idx:22, player:'Marc B.', type:'hit',     note:'Reihenkubb rechts · 7 m', t:'4:12' },
  { idx:21, player:'Anna V.', type:'miss',    note:'Daneben · zu lang',        t:'3:58' },
  { idx:20, player:'Vinz L.', type:'heli',    note:'Heli erfolgreich · 8 m',    t:'3:41' },
  { idx:19, player:'Jonas T.', type:'hit',    note:'Mittelkubb · 6 m',          t:'3:24' },
  { idx:18, player:'Marc B.', type:'hit',     note:'Frontreihe · 5 m',          t:'3:08' },
  { idx:17, player:'Jonas T.', type:'penalty', note:'König vorzeitig getroffen', t:'2:51' },
  { idx:16, player:'Vinz L.', type:'miss',    note:'Streifte rechts',           t:'2:34' },
  { idx:15, player:'Anna V.', type:'hit',     note:'Rückkubb · 5 m',            t:'2:18' },
];

function Pitch() {
  // Pitch — 5m × 8m, rendered horizontally with Kubbs as squares
  const w = 720, h = 240, pad = 18;
  const innerW = w - 2*pad, innerH = h - 2*pad;
  const homeLineY  = pad + innerH * 0.85;
  const awayLineY  = pad + innerH * 0.15;
  const midY       = pad + innerH * 0.5;

  return (
    <div style={m.pitchWrap}>
      <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} preserveAspectRatio="xMidYMid meet" style={{display:'block'}}>
        {/* pitch background */}
        <rect x={pad} y={pad} width={innerW} height={innerH} fill="var(--kc-meadow-50)" stroke="var(--kc-meadow-200)" strokeWidth="1.5" rx="6"/>
        {/* center mid line */}
        <line x1={pad} x2={w-pad} y1={midY} y2={midY} stroke="var(--kc-stone-300)" strokeWidth="1" strokeDasharray="4 4"/>
        {/* baselines */}
        <line x1={pad} x2={w-pad} y1={homeLineY} y2={homeLineY} stroke="var(--kc-stone-900)" strokeWidth="1"/>
        <line x1={pad} x2={w-pad} y1={awayLineY} y2={awayLineY} stroke="var(--kc-stone-900)" strokeWidth="1"/>

        {/* away baseline kubbs (opponent) */}
        {[0.18, 0.30, 0.42, 0.58, 0.70, 0.82].map((x, i) => {
          const cx = pad + x * innerW;
          const cy = awayLineY;
          const knocked = [false, true, false, false, true, false][i];
          return <Kubb key={i} cx={cx} cy={cy} knocked={knocked} small/>;
        })}

        {/* home baseline kubbs */}
        {[0.18, 0.30, 0.42, 0.58, 0.70, 0.82].map((x, i) => {
          const cx = pad + x * innerW;
          const cy = homeLineY;
          const knocked = [false, false, true, false, false, false][i];
          return <Kubb key={'h'+i} cx={cx} cy={cy} knocked={knocked} small home/>;
        })}

        {/* center field kubbs (Strafkubb) */}
        <Kubb cx={pad + innerW * 0.35} cy={midY - 22} penalty/>
        <Kubb cx={pad + innerW * 0.62} cy={midY + 24} penalty knocked/>

        {/* King */}
        <g>
          <circle cx={pad + innerW * 0.5} cy={midY} r="14" fill="var(--kc-king)" stroke="var(--kc-wood-600)" strokeWidth="2"/>
          <path d={`M ${pad + innerW * 0.5 - 9} ${midY - 6} L ${pad + innerW * 0.5 - 5} ${midY - 16} L ${pad + innerW * 0.5} ${midY - 8} L ${pad + innerW * 0.5 + 5} ${midY - 16} L ${pad + innerW * 0.5 + 9} ${midY - 6} Z`} fill="var(--kc-wood-600)"/>
        </g>

        {/* labels */}
        <text x={pad+8} y={awayLineY - 6} fontFamily="var(--kc-font-mono)" fontSize="10" fill="var(--kc-fg-muted)" letterSpacing="0.04em">UNITED A</text>
        <text x={pad+8} y={homeLineY + 16} fontFamily="var(--kc-font-mono)" fontSize="10" fill="var(--kc-fg-muted)" letterSpacing="0.04em">MARC &amp; VINZ</text>
        <text x={w - pad - 80} y={midY + 4} fontFamily="var(--kc-font-mono)" fontSize="10" fill="var(--kc-fg-muted)" letterSpacing="0.06em" textAnchor="end">5 m × 8 m · Mittellinie</text>
      </svg>
    </div>
  );
}

function Kubb({ cx, cy, knocked, penalty, home, small }) {
  const size = small ? 14 : 18;
  const fill = penalty ? 'var(--kc-wood-400)' : home ? 'var(--kc-meadow-600)' : 'var(--kc-meadow-500)';
  if (knocked) {
    return <rect x={cx - size/2 - 2} y={cy - size/4} width={size + 4} height={size/2} rx="2" fill="var(--kc-stone-300)" stroke="var(--kc-stone-400)" strokeWidth="1"/>;
  }
  return <rect x={cx - size/2} y={cy - size/2} width={size} height={size} rx="2" fill={fill} stroke="var(--kc-stone-900)" strokeOpacity="0.15" strokeWidth="1"/>;
}

function ScoreSide({ name, sub, score, initials, you }) {
  return (
    <div style={{...m.scoreSide, ...(you ? m.scoreSideYou : {})}}>
      <div style={{...m.scoreAvatar, background: you ? 'var(--kc-meadow-600)' : 'var(--kc-stone-900)'}}>{initials}</div>
      <div style={m.scoreNameCol}>
        <div style={m.scoreName}>{name}</div>
        <div style={m.scoreSub}>{sub}</div>
      </div>
      <div style={m.scoreNum}>{score}</div>
    </div>
  );
}

function ActionBtn({ label, sub, tone }) {
  const tones = {
    hit:     { bg:'var(--kc-hit)',     fg:'#fff' },
    miss:    { bg:'var(--kc-miss)',    fg:'#fff' },
    heli:    { bg:'var(--kc-heli)',    fg:'var(--kc-stone-900)' },
    penalty: { bg:'var(--kc-penalty)', fg:'#fff' },
  }[tone];
  return (
    <button style={{...m.actionBtn, background:tones.bg, color:tones.fg}}>
      <span style={m.actionLbl}>{label}</span>
      <span style={m.actionSub}>{sub}</span>
    </button>
  );
}

// =====================================================================
// RESULT
// =====================================================================
function Result({ onRoute, onRestart }) {
  return (
    <div style={m.resultWrap}>
      <Card padding={28}>
        <div style={m.resultHero}>
          <div style={m.resultBigSide}>
            <div style={m.resultName}>Marc & Vinz</div>
            <div style={m.resultBig}>3</div>
            <div style={m.resultBadge}>SIEG</div>
          </div>
          <div style={m.resultColon}>:</div>
          <div style={{...m.resultBigSide, opacity:0.55}}>
            <div style={m.resultName}>BKC United A</div>
            <div style={{...m.resultBig, color:'var(--kc-fg-muted)'}}>2</div>
            <div style={m.resultMeta}>Best of 5 · 6 Stöcke · 9:42 min</div>
          </div>
        </div>
        <div style={m.resultStats}>
          <Stat label="Treffer"      home="18 / 28" away="14 / 27"/>
          <Stat label="Trefferrate"  home="64 %"    away="52 %"   homeBetter/>
          <Stat label="Heli erfolgreich" home="4 / 5" away="2 / 3"  homeBetter/>
          <Stat label="Strafkubbs"   home="0"       away="2"       homeBetter/>
          <Stat label="Schnellster Halbsatz" home="1:42" away="—"  homeBetter/>
          <Stat label="ELO-Bewegung"  home="+18"    away="−15"     homeBetter/>
        </div>
      </Card>

      <div style={m.resultSplit}>
        <Card padding={20}>
          <CardHeader eyebrow="Halbsatz-Verlauf" title="5 Halbsätze · 3:2"/>
          <div style={m.setRow}>
            {[
              { n:1, home:6, away:4, won:true,  time:'1:42' },
              { n:2, home:5, away:6, won:false, time:'2:08' },
              { n:3, home:6, away:3, won:true,  time:'1:54' },
              { n:4, home:4, away:6, won:false, time:'2:21' },
              { n:5, home:6, away:5, won:true,  time:'1:37' },
            ].map(s => (
              <div key={s.n} style={{...m.setCard, ...(s.won ? m.setCardWon : m.setCardLost)}}>
                <div style={m.setCardLabel}>Halbsatz {s.n}</div>
                <div style={m.setCardScore}>{s.home}:{s.away}</div>
                <div style={m.setCardTime}>{s.time}</div>
              </div>
            ))}
          </div>
        </Card>

        <Card padding={20}>
          <CardHeader eyebrow="Auswirkung" title="Liga-Tabelle"/>
          <div style={m.impact}>
            <div style={m.impactRow}>
              <span style={m.impactRank}>2.</span>
              <span style={m.impactTeam}>Marc & Vinz</span>
              <span style={m.impactPts}>9 → 12</span>
              <span style={m.impactDelta}>▲ 1</span>
            </div>
            <div style={m.impactRow}>
              <span style={m.impactRank}>4.</span>
              <span style={m.impactTeam}>BKC United A</span>
              <span style={m.impactPts}>9 → 9</span>
              <span style={{...m.impactDelta, color:'var(--kc-miss)'}}>▼ 2</span>
            </div>
          </div>
          <hr style={m.thinLine}/>
          <div style={{display:'flex', gap:10, flexWrap:'wrap'}}>
            <PrimaryBtn icon={<DIcon.Chevron/>} onClick={() => onRoute('tournament')}>Zur Tabelle</PrimaryBtn>
            <SecondaryBtn tone="default" onClick={onRestart}>Revanche</SecondaryBtn>
            <SecondaryBtn tone="ghost">Match teilen</SecondaryBtn>
          </div>
        </Card>
      </div>
    </div>
  );
}

function Stat({ label, home, away, homeBetter }) {
  return (
    <div style={m.statCol}>
      <div style={m.statLbl}>{label}</div>
      <div style={m.statRow}>
        <span style={{...m.statVal, color: homeBetter ? 'var(--kc-meadow-700)' : 'var(--kc-fg)', fontWeight: homeBetter ? 800 : 700}}>{home}</span>
        <span style={m.statSep}>·</span>
        <span style={{...m.statVal, color:'var(--kc-fg-muted)'}}>{away}</span>
      </div>
    </div>
  );
}

// ---------- Styles ----------
const m = {
  stageSwitch: { display:'flex', gap:4, background:'var(--kc-bg-sunken)', padding:4, borderRadius:999 },
  stageBtn: { minHeight:36, padding:'0 14px', borderRadius:999, border:0, background:'transparent', color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:13, cursor:'pointer' },
  stageBtnOn: { background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },

  // LOBBY
  lobbyWrap: { padding:'24px 32px 32px', display:'flex', flexDirection:'column', gap:20 },
  lobbyTeams: { display:'grid', gridTemplateColumns:'1fr auto 1fr', gap:24, alignItems:'center', padding:'28px 32px', borderRadius:20, background:'var(--kc-bg-raised)', boxShadow:'var(--kc-shadow-1)' },
  teamCard: { display:'flex', flexDirection:'column', gap:6 },
  teamAvatar: { width:80, height:80, borderRadius:20, color:'#fff', display:'grid', placeItems:'center', fontFamily:'var(--kc-font-display)', fontWeight:800, fontSize:28, letterSpacing:'-0.02em', fontVariationSettings:'"opsz" 72' },
  teamName: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:28, letterSpacing:'-0.025em', marginTop:6, fontVariationSettings:'"opsz" 72' },
  teamMeta: { display:'flex', gap:8, fontSize:13, color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-mono)' },
  formCell: { width:22, height:22, borderRadius:5, fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:700, display:'grid', placeItems:'center' },
  teamPlayers: { display:'flex', flexDirection:'column', gap:6, marginTop:14, width:'100%', maxWidth:280 },
  teamPlayer: { display:'flex', alignItems:'center', gap:10, padding:'8px 10px', borderRadius:10, background:'var(--kc-bg-sunken)' },
  teamPlayerAv: { width:28, height:28, borderRadius:8, background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)', fontSize:11, fontWeight:700, display:'grid', placeItems:'center' },
  teamPlayerName: { fontWeight:600, fontSize:13, flex:1 },
  teamPlayerElo: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)' },
  readyTag: { display:'inline-flex', alignItems:'center', gap:6, marginTop:10, fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-meadow-700)' },
  greenDot: { width:8, height:8, borderRadius:999, background:'var(--kc-meadow-500)' },

  lobbyVs: { display:'flex', flexDirection:'column', alignItems:'center', gap:4, color:'var(--kc-fg-muted)' },
  lobbyVsBig: { fontFamily:'var(--kc-font-display)', fontSize:64, fontWeight:700, color:'var(--kc-fg)', letterSpacing:'-0.04em', lineHeight:1, fontVariationSettings:'"opsz" 96' },
  lobbyVsMeta: { fontFamily:'var(--kc-font-mono)', fontSize:11, letterSpacing:'0.06em', textTransform:'uppercase' },
  lobbyVsClock: { fontFamily:'var(--kc-font-ui)', fontSize:34, fontWeight:800, color:'var(--kc-meadow-600)', marginTop:14, fontVariantNumeric:'tabular-nums' },
  lobbyVsClockSub: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.06em', textTransform:'uppercase' },

  lobbyGrid: { display:'grid', gridTemplateColumns:'1.2fr 1fr', gap:18 },
  h2hList: { display:'flex', flexDirection:'column', gap:2, marginTop:6 },
  h2hRow: { display:'grid', gridTemplateColumns:'80px 1fr 60px 1fr 60px', gap:10, alignItems:'center', padding:'10px 6px', borderTop:'1px solid var(--kc-line)' },
  h2hDate: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.04em' },
  h2hTeam: { fontWeight:600, fontSize:13 },
  h2hScore: { fontFamily:'var(--kc-font-mono)', fontWeight:700, fontSize:13, textAlign:'center' },
  h2hBadge: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:700, letterSpacing:'0.06em', textTransform:'uppercase', padding:'2px 8px', borderRadius:4, textAlign:'center' },

  setupRow: { display:'flex', justifyContent:'space-between', alignItems:'center', padding:'12px 0', borderTop:'1px solid var(--kc-line)' },
  setupLbl: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  setupVal: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:14 },

  // LIVE
  liveWrap: { padding:'20px 32px 32px', display:'flex', flexDirection:'column', gap:18 },
  scoreStrip: { display:'grid', gridTemplateColumns:'1fr auto 1fr', gap:18, padding:'18px 24px', borderRadius:18, background:'var(--kc-stone-900)', color:'var(--kc-chalk-50)' },
  scoreSide: { display:'flex', alignItems:'center', gap:14 },
  scoreSideYou: { },
  scoreAvatar: { width:52, height:52, borderRadius:14, color:'#fff', display:'grid', placeItems:'center', fontWeight:800, fontSize:18, fontFamily:'var(--kc-font-display)' },
  scoreNameCol: { display:'flex', flexDirection:'column', minWidth:0 },
  scoreName: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:22, letterSpacing:'-0.02em', fontVariationSettings:'"opsz" 36' },
  scoreSub: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-stone-300)' },
  scoreNum: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:84, letterSpacing:'-0.04em', lineHeight:1, fontVariantNumeric:'tabular-nums', marginLeft:'auto' },
  scoreCenter: { display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', gap:4, color:'var(--kc-stone-300)' },
  scoreSet: { fontFamily:'var(--kc-font-mono)', fontSize:11, letterSpacing:'0.08em', textTransform:'uppercase' },
  scoreTime: { fontFamily:'var(--kc-font-ui)', fontWeight:700, fontSize:32, color:'var(--kc-wood-400)', letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },
  scoreState: { fontFamily:'var(--kc-font-mono)', fontSize:10, color:'var(--kc-wood-400)', letterSpacing:'0.1em', textTransform:'uppercase' },

  liveSplit: { display:'grid', gridTemplateColumns:'1.1fr 1fr', gap:18, alignItems:'flex-start' },
  liveLayoutTag: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.06em', textTransform:'uppercase' },
  pitchWrap: { borderRadius:10, overflow:'hidden', background:'var(--kc-meadow-50)', marginTop:8 },
  pitchLegend: { display:'flex', flexWrap:'wrap', gap:14, marginTop:12 },
  legendItem: { display:'flex', alignItems:'center', gap:6, fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)' },
  legendCube: { width:11, height:11, display:'inline-block' },

  liveRight: { display:'flex', flexDirection:'column', gap:16 },
  counterHead: { display:'flex', justifyContent:'space-between', alignItems:'flex-start', gap:14 },
  counterEyebrow: { fontFamily:'var(--kc-font-mono)', fontSize:11, fontWeight:600, letterSpacing:'0.1em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  counterMain: { display:'flex', alignItems:'baseline', gap:24, marginTop:4 },
  counterBig: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:96, lineHeight:0.85, letterSpacing:'-0.05em', color:'var(--kc-meadow-700)', fontVariantNumeric:'tabular-nums' },
  counterUnit: { fontSize:32, fontWeight:600, color:'var(--kc-fg-muted)', marginLeft:4 },
  counterSide: { display:'flex', flexDirection:'column', gap:4, paddingTop:8 },
  counterSideRow: { display:'flex', justifyContent:'space-between', gap:20, fontFamily:'var(--kc-font-mono)', fontSize:12 },
  counterSideLbl: { color:'var(--kc-fg-muted)' },
  counterSideVal: { fontWeight:700, color:'var(--kc-fg)' },
  undoBtn: { background:'transparent', border:0, color:'var(--kc-fg-muted)', fontFamily:'var(--kc-font-mono)', fontSize:12, display:'flex', alignItems:'center', gap:6, cursor:'pointer', padding:'6px 8px', borderRadius:8 },

  actionPad: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:10 },
  actionBtn: { border:0, borderRadius:14, padding:'18px 20px', textAlign:'left', cursor:'pointer', boxShadow:'var(--kc-shadow-1)', display:'flex', flexDirection:'column', gap:2 },
  actionLbl: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:22, letterSpacing:'-0.02em', fontVariationSettings:'"opsz" 36' },
  actionSub: { fontFamily:'var(--kc-font-ui)', fontSize:12, fontWeight:500, opacity:0.85 },

  runde: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', letterSpacing:'0.06em', textTransform:'uppercase' },
  log: { listStyle:'none', padding:0, margin:0, maxHeight:260, overflowY:'auto' },
  logRow: { display:'grid', gridTemplateColumns:'40px 56px 1fr auto', gap:10, alignItems:'center', padding:'10px 18px', borderTop:'1px solid var(--kc-line)' },
  logRowLatest: { background:'var(--kc-meadow-50)' },
  logIdx: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)' },
  logIcon: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:700, letterSpacing:'0.06em', padding:'4px 6px', borderRadius:4, textAlign:'center' },
  logSub: { fontSize:13 },
  logTime: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', fontVariantNumeric:'tabular-nums' },

  endRow: { display:'flex', gap:10, justifyContent:'flex-end' },

  // RESULT
  resultWrap: { padding:'24px 32px 32px', display:'flex', flexDirection:'column', gap:18 },
  resultHero: { display:'flex', alignItems:'center', justifyContent:'center', gap:28, padding:'18px 0' },
  resultBigSide: { textAlign:'center', display:'flex', flexDirection:'column', alignItems:'center', gap:4 },
  resultName: { fontFamily:'var(--kc-font-display)', fontWeight:700, fontSize:22, letterSpacing:'-0.02em', fontVariationSettings:'"opsz" 36' },
  resultBig: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:160, lineHeight:0.85, letterSpacing:'-0.05em', color:'var(--kc-meadow-600)', fontVariantNumeric:'tabular-nums' },
  resultBadge: { fontFamily:'var(--kc-font-mono)', fontSize:12, fontWeight:700, letterSpacing:'0.1em', textTransform:'uppercase', color:'var(--kc-meadow-700)', background:'var(--kc-meadow-100)', padding:'4px 10px', borderRadius:6 },
  resultColon: { fontFamily:'var(--kc-font-ui)', fontWeight:600, fontSize:120, color:'var(--kc-fg-muted)', lineHeight:0.85, letterSpacing:'-0.05em' },
  resultMeta: { fontFamily:'var(--kc-font-mono)', fontSize:11, color:'var(--kc-fg-muted)', marginTop:6 },

  resultStats: { display:'grid', gridTemplateColumns:'repeat(6, 1fr)', gap:14, marginTop:14, paddingTop:18, borderTop:'1px solid var(--kc-line)' },
  statCol: { display:'flex', flexDirection:'column', gap:6 },
  statLbl: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase', color:'var(--kc-fg-muted)' },
  statRow: { display:'flex', alignItems:'baseline', gap:6 },
  statVal: { fontFamily:'var(--kc-font-ui)', fontSize:18, letterSpacing:'-0.02em', fontVariantNumeric:'tabular-nums' },
  statSep: { color:'var(--kc-fg-muted)' },

  resultSplit: { display:'grid', gridTemplateColumns:'1.4fr 1fr', gap:18 },
  setRow: { display:'grid', gridTemplateColumns:'repeat(5, 1fr)', gap:10, marginTop:10 },
  setCard: { padding:'12px 10px', borderRadius:12, textAlign:'center', display:'flex', flexDirection:'column', gap:2 },
  setCardWon: { background:'var(--kc-meadow-100)', color:'var(--kc-meadow-700)' },
  setCardLost: { background:'var(--kc-stone-100)', color:'var(--kc-fg-muted)' },
  setCardLabel: { fontFamily:'var(--kc-font-mono)', fontSize:10, fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase' },
  setCardScore: { fontFamily:'var(--kc-font-ui)', fontWeight:800, fontSize:28, letterSpacing:'-0.03em', fontVariantNumeric:'tabular-nums' },
  setCardTime: { fontFamily:'var(--kc-font-mono)', fontSize:11 },

  impact: { display:'flex', flexDirection:'column', gap:6 },
  impactRow: { display:'grid', gridTemplateColumns:'32px 1fr auto 40px', gap:10, alignItems:'center', padding:'10px 4px', borderTop:'1px solid var(--kc-line)' },
  impactRank: { fontFamily:'var(--kc-font-mono)', fontWeight:600, color:'var(--kc-fg-muted)' },
  impactTeam: { fontWeight:600 },
  impactPts: { fontFamily:'var(--kc-font-mono)', fontWeight:700, fontVariantNumeric:'tabular-nums' },
  impactDelta: { fontFamily:'var(--kc-font-mono)', fontSize:12, fontWeight:700, color:'var(--kc-meadow-600)', textAlign:'right' },
  thinLine: { border:0, borderTop:'1px solid var(--kc-line)', margin:'14px 0' },
};

window.MatchScreen = MatchScreen;
