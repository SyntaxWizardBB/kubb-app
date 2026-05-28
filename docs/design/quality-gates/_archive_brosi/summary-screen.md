# Quality-Gate: Summary Screen

**Quelle**: docs/design/ui_kits/app/SummaryScreen.jsx
**Flutter-Pendant**: lib/features/training/presentation/summary_screen.dart
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (top-down)

Der Summary-Screen kommt nach einer Trainings-Session in zwei Modi:
- kind: '8m' (Sniper-Summary): Hit-Rate als Hauptzahl, optional Multi-Distanz-Breakdown.
- kind: 'finisseur': Stoecke-Verbrauch als Hauptzahl, Koenig/Strafkubb/Heli/Dauer als Detail.

1. AppBar (shared) — Eyebrow "Session beendet", Title:
   - Sniper: "Sniper · 8.0 m" (single) oder "Sniper · 8.0 m · 6.5 m · 4.0 m" (multi).
   - Finisseur: "Finisseur · 7/3".
2. Verdict-Banner — margin 10/16/14, borderRadius 20, padding 22/18/18.
   - Sniper / Finisseur-success: meadow500 background, chalk50 text.
   - Finisseur-fail: stone700 background.
   - Sniper-Content: Big number {rate} Display 90px weight 800 (lineHeight 0.9, -0.04em, tabular-nums), Suffix " %" 40% Groesse. Sub-Text 13px opacity 0.85: "Trefferquote · {total8m} Wuerfe in {duration}".
   - Finisseur-Content: Verdict-Tag ("Sauber finished" / "Nicht geschafft") Eyebrow-Style 11/600/0.85. Big number {sticksUsed} Display 90px, Suffix " / 6". Sub "Stoecke benoetigt · {duration}".
3. Body (padding 4/16, scrollable).
   - Sniper Multi-Distance (wenn breakdown.length > 1):
     - Section-Header "Pro Distanz".
     - Dist-List flex-column gap 8.
     - Pro Distanz Container bgRaised borderRadius 14 padding 12/14 gap 10:
       - distHead: Meters "8.0 m" Display 22 weight 800 + Rate "58 %" Display 18 weight 700 in meadow600.
       - distNumbers grid 3 gap 6: Drei Pills (Treffer/Miss/Heli).
       - Pill: flex-column center gap 2, padding 8/6, bg tokens.bg, borderRadius 10. Label 10 caps muted, Value Display 22 weight 800 tabular-nums. Tone-Color hit/miss/heli.
     - Dauer-Row unten (Mono).
   - Sniper Single-Distance: 4 Rows (Treffer/Miss/Heli/Dauer).
   - Finisseur: 4 Rows (Koenigswurf/Strafkubbs/Heli/Dauer).
   - Row-Pattern: flex space-between baseline, padding 12 vertical, borderBottom 1px line. Label 14 muted, Value Display 22 weight 700 tabular-nums (Tone-Color), Dauer Mono 17 weight 500.
4. Actions — grid 1fr/1fr gap 10, padding 10/16/8.
   - Discard: minHeight 54, borderRadius 14, background tokens.danger (miss), color onDanger, Display 17 weight 700, "Verwerfen".
   - Save: gleich, background primary, "Speichern".
5. Restart-Button — margin 4/16/0, minHeight 54, borderRadius 14, background bgRaised, boxShadow inset 0 0 0 2px lineStrong, Display 16 weight 700. Icon.Plus2 + "Neue Session starten".
6. Bottom-Spacer 24px.

### Farben (Token-Namen)

- Verdict Sniper/Finisseur-success: KubbTokens.meadow500
- Verdict Finisseur-fail: KubbTokens.stone700
- Verdict-Text: KubbTokens.chalk50
- Pill hit: KubbTokens.hit (#2D6324)
- Pill miss: KubbTokens.miss (#B73A2A)
- Pill heli: KubbTokens.heli (#C08A33)
- Row tone penalty: KubbTokens.penalty (#8A1F3D)
- Row tone muted: tokens.fgMuted
- Dist-Rate (Header): KubbTokens.meadow600
- Save-Btn: tokens.primary / tokens.onPrimary
- Discard-Btn: tokens.danger / tokens.onDanger (full-fill, NICHT outlined)
- Restart-Btn Background: tokens.bgRaised, Inset-Border 2px tokens.lineStrong

### Typografie

| Bereich | Font | Size | Weight |
|---|---|---|---|
| Verdict-Big-Number | Display | 90 | 800 (-0.04em, lineHeight 0.9, tabular-nums) |
| Verdict-Tag (Finisseur) | Body | 11 | 600 (caps, 0.08em, opacity 0.85) |
| Verdict-Sub | Body | 13 | — (opacity 0.85) |
| Dist-Meters | Display | 22 | 800 (-0.02em, tabular-nums) |
| Dist-Rate | Display | 18 | 700 (tabular-nums, meadow600) |
| Pill-Label | Body | 10 | 600 (caps, muted) |
| Pill-Value | Display | 22 | 800 (-0.02em, tabular-nums) |
| Row-Label | Body | 14 | — (muted) |
| Row-Value | Display | 22 | 700 (tabular-nums) |
| Row-Value Mono (Dauer) | Mono | 17 | 500 (tabular-nums) |
| Save-/Discard-Btn | Display | 17 | 700 |
| Restart-Btn | Display | 16 | 700 |

### Spacing / Radius / Shadows

- Verdict margin 10/16/14, Body padding 4/16.
- Dist-Row padding 12/14 gap 10.
- Pill padding 8/6 gap 2.
- Row padding 12 vertikal.
- Actions padding 10/16/8 gap 10.
- Restart margin 4/16/0.
- Verdict-Banner: 20.
- Dist-Row Container: 14.
- Pill: 10.
- Save/Discard/Restart-Btn: 14.
- Shadows: keine, nur Inset-Border am Restart.

### Icons

- Icon.Plus2 (20px) im Restart-Button.
- Icon.Back in shared AppBar.

## Komponenten-Inventar

| Sub-Komponente | Aufgabe | Wiederverwendbar | Props |
|---|---|---|---|
| SummaryScreen | Screen-Root | nein | kind, data, onSave, onDiscard, onBack, onRestart |
| Row | Label-Value-Row mit Tone-Switch | inline | label, value, tone?, mono? |
| Pill | Stat-Pill in Multi-Distance-Breakdown | inline (Kandidat fuer shared) | tone, label, value, dim? |

Wiederverwendbar:
- Pill → Kandidat fuer KubbStatPill-Widget.
- Verdict / FinisseurVerdict → Kandidat fuer KubbVerdictBanner mit Tone-Switch.

## Interaktions-Pattern

- Tap-Targets ≥ 48dp.
- Hover/Pressed-States: Material InkWell-Default reicht.
- Loading-States: Flutter summarySessionProvider AsyncValue → Spinner. JSX hat keinen Loading (Demo-Daten).
- Empty-States: nicht relevant — Session existiert per Definition.
- Error-States: Flutter _ErrorView zeigt Text(e.toString()) + OK-Button — verbesserungswuerdig.
- Navigation:
  - Back → vorheriger Screen.
  - Save → context.go('/').
  - Discard → repository.discard(), dann context.go('/').
  - Restart → neue Session mit denselben Parametern, navigiert zu /training/<mode>/session/<newId>.
- Multi-Distance-Logic: kind '8m' + breakdown.length > 1 → multi-mode. Flutter _SniperBody hat KEIN Breakdown — Mismatch.

## Accessibility-Hinweise

- Kontrast Verdict-meadow500 + chalk50 ~4.6:1 (AA fuer grossen Text).
- Verdict-stone700 + chalk50 ~9:1.
- Pill-Tone-Colors auf bg (chalk50): Miss ~5:1, Hit ~7:1, Heli ~3.3:1 (Heli Pill-Value gross 22/800 ok; Pill-Label klein 10px ist muted, Kontrast pruefen).
- Discard miss + chalk50 ~5:1 AA.
- Tabular-Numerals durchgaengig.
- Reader-Labels: Big-Numbers brauchen Semantics-Label ("Trefferquote 64 Prozent").

## Quality-Gate-Checkliste

- [ ] AppBar mit Eyebrow "Session beendet", Title kind-abhaengig.
- [ ] Verdict-Banner als rounded borderRadius-20-Card mit meadow500/stone700 Background, Display 90px.
- [ ] Sniper-Verdict: {rate} % + "Trefferquote · {wuerfe} Wuerfe in {duration}".
- [ ] Finisseur-Verdict: Tag + {sticksUsed} / 6 + "Stoecke benoetigt · {duration}".
- [ ] Sniper Multi-Distance-Breakdown wenn mehrere Distanzen.
- [ ] Sniper Single-Distance: 4 Rows (Treffer/Miss/Heli/Dauer), Heli verstecken wenn 0 (settings-driven).
- [ ] Finisseur: 4 Rows (Koenigswurf/Strafkubbs/Heli/Dauer) plus Modus-Row.
- [ ] Row borderBottom 1px line, Label 14 muted + Value Display 22 weight 700 tone-coloured.
- [ ] Dauer als Mono.
- [ ] Actions-Grid: Discard links (danger fill) + Save rechts (primary), gleich gross.
- [ ] Restart-Button outlined mit Plus2-Icon.
- [ ] Alle Tokens aus KubbTokens.
- [ ] Tabular-Numerals.
- [ ] Touch-Targets ≥ 48dp.
- [ ] Loading + Error States.
- [ ] Keine UUID-Substrings im Title.
- [ ] i18n via AppLocalizations.

## Bekannte Abweichungen (Flutter aktuell vs. Design)

1. Verdict-Banner fehlt visuell: Flutter rendert die Hit-Rate als 84px Display-Text auf tokens.fg (Stone-900 auf Chalk-50) OHNE Card-Container. JSX zeigt prominent farbigen Banner. **Wesentlicher Visual-Mismatch.**
2. Multi-Distance-Breakdown fehlt komplett: Flutter _SniperBody rendert keine breakdown-Logik. JSX-Spec sieht das als Standard. **Implementierungs-Luecke.**
3. Title-Format unterschiedlich: JSX-Title "Sniper · 8.0 m"; Flutter-Title statisch l.summaryTitle. Empfehlung: Distanz in AppBar-Title heben.
4. Finisseur-Verdict-Color-Logic: Flutter macht Tag-Color-Switch; JSX macht Banner-Background-Switch (meadow vs. stone700). Mismatch.
5. Discard/Save-Layout: Flutter rendert Save als FilledButton oben, dann Verwerfen unter, dann Restart als TextButton. JSX rendert Discard und Save in Grid 1fr/1fr gleich gross, dann Restart als Outlined. **Layout-Mismatch.**
6. Discard-Button-Color: JSX nutzt danger als full-fill Background. Flutter macht OutlinedButton(foregroundColor: danger). **Visual-Mismatch.**
7. Restart-Button-Style: JSX bgRaised + 2px lineStrong inset + Plus2-Icon + Label. Flutter TextButton ohne Icon. **Visual-Mismatch.**
8. Finisseur-Body-Detail: Flutter rendert mehr Detail-Rows als JSX (Penalty, LongDubbie, Heli, Modus) — Settings-driven. JSX hat fixe 4-Row-Liste. Pruefen ob Settings-Toggles im Design vorgesehen waren.
9. _FinisseurVerdict Overstick-Subtitle ist Flutter-Erweiterung — gut, im Design ergaenzen.
10. AppBar automaticallyImplyLeading false — kein Back-Button. JSX hat Back. Flutter ist vermutlich richtig (man verlaesst Summary nur via Save/Discard/Restart).
11. Pill-Widget fuer Multi-Distance ist Flutter-only nicht vorhanden, weil Breakdown-Feature fehlt.
12. Sniper-Session-Detail Flutter zeigt _Row(label: summaryDistance) — bei Single-Distance einzige Distanz-Anzeige; bei Multi-Distance wuerde Breakdown das ersetzen.
