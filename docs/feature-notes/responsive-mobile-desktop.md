# Feature note: Mobile vs. Desktop differentiation

Captured 2026-05-02 nach erstem F1-Test-Feedback. Aktuell ist die App **Mobile-First** designed (per ADR-0008 + `docs/design/colors_and_type.css` Design-System). Desktop-Targets (Linux + zukünftig Web/macOS/Windows) brauchen eine eigene UI-Variante — soll mit Claude Design separat erarbeitet werden, bevor die Implementierung dran ist.

## Aktueller Stand (F1)

- **Mobile-First Layout** durchgehend: KubbAppBar, Bottom-Sheets, FAB (Material 3 24/24), Tap-Pads min 84 dp
- Linux- und Web-Desktop laufen mit dem **gleichen Mobile-Layout** — funktioniert, sieht aber "Mobile auf grossem Screen" aus, nicht nativ Desktop
- Screens haben aktuell keine `BreakpointBuilder` oder `MediaQuery.of(context).size.width`-Abfragen
- Phone-spezifische Patterns (Sheet von unten, FAB unten rechts, Vollbild-Onboarding) sind in der Mobile-Welt richtig, am Desktop suboptimal

## Was Desktop anders braucht (Brainstorm — wird mit Claude Design verfeinert)

### Layout-Patterns
- **Sidebar-Navigation** statt Bottom-Sheet/FAB — Persistent links eingeklappt
- **Master-Detail** statt Voll-Bildschirm-Wechsel — Sniper-Liste links, Detail rechts
- **Mehrere Sessions parallel sichtbar** — z.B. Stats + Aktive Session nebeneinander
- **Keyboard-Shortcuts** für Hit/Miss/Heli (statt Tap-Pads) — Spacebar = Hit, X = Miss, etc.
- **Rechts-Click-Menüs** statt Long-Press
- **Resizable Window** mit Min-Breite (z.B. 800 dp)

### Komponenten-Adaption
- **AppBar**: Desktop hat eigene Title-Bar (Window-Buttons, Drag-Region) — kein Status-Bar-Padding
- **Bottom-Sheets**: am Desktop besser **modale Dialoge** zentriert
- **TapPads**: ersetzt durch Buttons + Keyboard-Shortcuts. TapPads sind Touch-Optimierung, am Desktop irrelevant
- **Counter**: bleibt prominent, aber kleiner (Desktop-Screens sind grösser, Hierarchie nimmt ab)
- **HomeScreen**: statt 3 vertikale Karten → Grid mit Recent + Stats + Tournament-Übersicht side-by-side
- **Settings**: statt Modal → eigener Settings-Screen mit Sidebar-Navigation

### Welche Targets entscheiden was?
- **Mobile** (Phone, kleine Tablets <600 dp): aktuelles Mobile-Layout
- **Tablet** (600–1024 dp): Mobile-Layout mit grosszügigerem Spacing — kein eigener Layer in F1
- **Desktop** (>1024 dp): eigene Layout-Variante (Sidebar + Master-Detail)

Breakpoint-Schwelle vermutlich bei `1024 dp` (klassische Tablet/Desktop-Grenze).

## Empfohlener Implementierungs-Ansatz (für später, nicht jetzt)

1. **Phase 1 — Design**: Claude Design Mockups für Desktop-Variante (HomeScreen, Sniper, Profile, Settings) — separates Bundle in `docs/design/desktop/`
2. **Phase 2 — Architektur**: ADR für "Responsive Layout Strategy". Optionen:
   - **Option A**: ein gemeinsames Widget pro Screen mit `LayoutBuilder` der zwischen `_MobileLayout` und `_DesktopLayout` wechselt
   - **Option B**: getrennte Widget-Bäume `lib/features/.../presentation/mobile/` vs `desktop/` — Routing entscheidet je nach Plattform/Breakpoint
   - **Option C**: Helper-Pakete wie `flutter_adaptive_scaffold` (Material 3 adaptive)
3. **Phase 3 — Implementation**: pro Screen einen Refactor-Task. Profile + Onboarding zuerst (kleinste Footprint), dann komplexere Screens.

## Plattform-Detection

Aktuell wird **kein** Platform-Channel benutzt. Für Desktop-Detection:
- `Theme.of(context).platform` (TargetPlatform) — funktioniert für UI-Anpassungen
- `defaultTargetPlatform` aus `package:flutter/foundation.dart` für Globals
- Kombination mit `MediaQuery.sizeOf(context).width` für Breakpoints (auch grosser Tablet ist "Desktop-like")

## Constraints für die Mobile-Variante (F1 + Folge-Features)

- KEINE Desktop-spezifischen Annahmen einbauen (kein `Tooltip` weil Desktop-Hover, etc.)
- Aber: kein Mobile-only-Code der Desktop bricht (z.B. `MediaQuery.of(context).viewInsets.bottom` für Keyboard ist OK, am Desktop einfach 0)
- Touch-Targets bleiben min 48 dp — auch am Desktop akzeptabel, "comfortable" reicht

## Open Questions (für Claude-Design-Session und nachfolgende ADR)

- Ist "Tablet" eine eigene Layout-Variante oder Mobile-mit-Spacing?
- Braucht Desktop einen separaten Light/Dark-Theme-Layer (anderes Spacing, andere Typo-Skala)?
- Wie soll High-Contrast-Mode am Desktop aussehen — gleich wie Mobile, oder gibt's Desktop-Conventions (z.B. Windows-High-Contrast-Theme respektieren)?
- Web-Spezifika: Browser-Tab-Title, URL-Routing, Browser-Back-Button — sind das eigene Tickets oder Teil von "Desktop"?

## Status

- **Aktuell**: nur Mobile-Layout, läuft auf Linux/Web/Phone gleich
- **Nächster Schritt**: Claude Design Session für Desktop-Mockups (Owner-Aktion)
- **Implementierung**: nach M3 oder M4 (nachdem Tournament-Setup steht — der grosse Desktop-Use-Case)
