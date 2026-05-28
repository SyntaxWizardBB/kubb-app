/* global React, BK */
const { useState } = React;
const { Icon } = BK;

// =====================================================================
// Screen: Onboarding Tour (4 slides) — AUDIT §2.4
//   - K+Crown vignette per slide (meadow disc + wood crown accent)
//   - Title (display, 28px) + body (15px, fg-muted)
//   - Top-right "Überspringen" link, bottom CTA "Weiter" / "Los geht's"
//   - Dot indicator: current dot stretches to a pill, past dots stay
//     filled at meadow-500, future dots are stone-200
// =====================================================================
const SLIDES = [
  {
    glyph: 'target',
    title: 'Sniper-Training',
    body: 'Wurf-Konstanz trainieren — 4 bis 8 m Distanz, eigene Sessions, eigene Stats.',
  },
  {
    glyph: 'crown',
    title: 'Finisseur',
    body: 'Das Match-Endspiel üben. 6 Stöcke, Field-, Base- und Königs-Phase.',
  },
  {
    glyph: 'cup',
    title: 'Turniere & Ligen',
    body: 'Turniere veranstalten, Spielpläne live verfolgen, Saisontabellen lesen.',
  },
  {
    glyph: 'group',
    title: 'Mit Freunden trainieren',
    body: 'Teams gründen, Freunde einladen, gemeinsam besser werden.',
  },
];

function OnboardingScreen({ onDone, initialIndex = 0 }) {
  const [i, setI] = useState(initialIndex);
  const slide = SLIDES[i];
  const isLast = i === SLIDES.length - 1;

  function next() {
    if (isLast) {
      onDone && onDone();
      return;
    }
    setI(i + 1);
  }

  return (
    <div style={o.screen}>
      <header style={o.header}>
        <span style={{width: 90}} aria-hidden="true"/>
        <div style={o.dots} role="tablist">
          {SLIDES.map((_, idx) => (
            <span
              key={idx}
              style={{
                ...o.dot,
                width: idx === i ? 24 : 8,
                background:
                  idx <= i ? 'var(--kc-meadow-500)' : 'var(--kc-stone-200)',
              }}
            />
          ))}
        </div>
        <button style={o.skip} onClick={() => onDone && onDone()}>
          Überspringen
        </button>
      </header>

      <main style={o.body}>
        <Vignette glyph={slide.glyph}/>
        <h1 style={o.title}>{slide.title}</h1>
        <p style={o.copy}>{slide.body}</p>
      </main>

      <footer style={o.footer}>
        <button style={o.cta} onClick={next}>
          {isLast ? "Los geht's" : 'Weiter'}
        </button>
      </footer>
    </div>
  );
}

// K+Crown vignette — meadow disc with the mode glyph and a wood-coloured
// crown accent perched on top. Mirrors the Flutter `_Vignette` widget.
function Vignette({ glyph }) {
  return (
    <div style={o.vignette}>
      <div style={o.disc}>
        <GlyphIcon name={glyph}/>
      </div>
      <div style={o.crown} aria-hidden="true">
        <CrownIcon/>
      </div>
    </div>
  );
}

function GlyphIcon({ name }) {
  // Inline SVGs so the screen renders standalone without depending on
  // an Icon symbol map. Stroke is meadow-700 to match Flutter.
  const stroke = 'var(--kc-meadow-700)';
  switch (name) {
    case 'target':
      return (
        <svg width="72" height="72" viewBox="0 0 24 24" fill="none"
             stroke={stroke} strokeWidth="2" strokeLinecap="round">
          <circle cx="12" cy="12" r="9"/>
          <circle cx="12" cy="12" r="5"/>
          <circle cx="12" cy="12" r="1.5" fill={stroke}/>
        </svg>
      );
    case 'crown':
      return (
        <svg width="72" height="72" viewBox="0 0 24 24" fill="none"
             stroke={stroke} strokeWidth="2" strokeLinejoin="round">
          <path d="M3 8 6 16h12l3-8-5 4-4-7-4 7-5-4z"/>
        </svg>
      );
    case 'cup':
      return (
        <svg width="72" height="72" viewBox="0 0 24 24" fill="none"
             stroke={stroke} strokeWidth="2" strokeLinejoin="round">
          <path d="M7 4h10v4a5 5 0 0 1-10 0V4z"/>
          <path d="M5 6H3a3 3 0 0 0 4 3"/>
          <path d="M19 6h2a3 3 0 0 1-4 3"/>
          <path d="M9 20h6"/>
          <path d="M12 13v7"/>
        </svg>
      );
    case 'group':
      return (
        <svg width="72" height="72" viewBox="0 0 24 24" fill="none"
             stroke={stroke} strokeWidth="2" strokeLinejoin="round"
             strokeLinecap="round">
          <circle cx="9" cy="9" r="3"/>
          <circle cx="17" cy="10" r="2.5"/>
          <path d="M3 19c0-3 3-5 6-5s6 2 6 5"/>
          <path d="M15 19c0-2 2-3.5 4-3.5s2.5 1.5 2.5 3.5"/>
        </svg>
      );
    default:
      return null;
  }
}

function CrownIcon() {
  return (
    <svg width="32" height="32" viewBox="0 0 24 24" fill="var(--kc-wood-400)"
         stroke="var(--kc-wood-600)" strokeWidth="1.4" strokeLinejoin="round">
      <path d="M3 8 6 16h12l3-8-5 4-4-7-4 7-5-4z"/>
    </svg>
  );
}

const o = {
  screen: {
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    background: 'var(--kc-bg)',
    color: 'var(--kc-fg)',
    fontFamily: 'var(--kc-font-ui)',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '54px 8px 8px',
  },
  dots: { display: 'flex', alignItems: 'center', gap: 6 },
  dot: {
    height: 8,
    borderRadius: 999,
    transition: 'width 200ms ease-out, background 200ms ease-out',
  },
  skip: {
    width: 90,
    minHeight: 32,
    background: 'transparent',
    border: 0,
    color: 'var(--kc-fg-muted)',
    fontFamily: 'inherit',
    fontWeight: 600,
    fontSize: 14,
    cursor: 'pointer',
    textAlign: 'right',
  },
  body: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '0 24px',
    textAlign: 'center',
  },
  vignette: {
    position: 'relative',
    width: 168,
    height: 168,
    marginBottom: 24,
  },
  disc: {
    width: 160,
    height: 160,
    margin: '8px auto 0',
    borderRadius: '50%',
    background: 'var(--kc-meadow-100)',
    display: 'grid',
    placeItems: 'center',
    boxShadow: '0 6px 24px rgba(58,124,46,0.18)',
  },
  crown: {
    position: 'absolute',
    top: -4,
    left: '50%',
    transform: 'translateX(-50%)',
  },
  title: {
    fontFamily: 'var(--kc-font-display)',
    fontWeight: 800,
    fontSize: 28,
    letterSpacing: '-0.02em',
    margin: '0 0 12px',
  },
  copy: {
    fontSize: 15,
    lineHeight: 1.5,
    color: 'var(--kc-fg-muted)',
    margin: 0,
    maxWidth: 320,
  },
  footer: { padding: '12px 20px 20px' },
  cta: {
    width: '100%',
    minHeight: 56,
    border: 0,
    borderRadius: 16,
    background: 'var(--kc-meadow-600)',
    color: 'var(--kc-on-primary)',
    fontFamily: 'var(--kc-font-display)',
    fontWeight: 700,
    fontSize: 17,
    letterSpacing: '-0.01em',
    cursor: 'pointer',
    boxShadow: 'var(--kc-shadow-2)',
  },
};

window.OnboardingScreen = OnboardingScreen;
