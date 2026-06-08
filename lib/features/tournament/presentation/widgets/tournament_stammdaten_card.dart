import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_detail_screen.dart'
    show tournamentUrlOpenerProvider;
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_card.dart'
    show formatLabel;
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// H2 — shared, reusable Stammdaten widget. Renders ALL configured master
/// data (B3.1–B3.4) of a tournament in a compact, design-system-conform way.
///
/// This is pure client UI: it reads from the already-fetched
/// [TournamentDetailHeader] (its `matchFormatConfig` + `setup` map) and holds
/// no state, no server/RPC, no migration logic. Unset / NULL / blank fields are
/// fully omitted — an empty section renders nothing.
///
/// Used by the normal tournament detail screen AND, via the same detail route,
/// by the upcoming-tournaments detail view (same card), so it must render for a
/// non-live tournament too.
class TournamentStammdatenCard extends ConsumerWidget {
  const TournamentStammdatenCard({required this.header, super.key});

  /// The tournament header carrying `matchFormatConfig` (B3.1/B3.2) and the
  /// raw P6 `setup` map (B3.3/B3.4).
  final TournamentDetailHeader header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _coreCard(context, l),
        ..._koPhaseCard(context, l),
        ..._metaCards(context, ref, l),
      ],
    );
  }

  // ---- Kern (B3.1 / B3.2) -------------------------------------------------

  Widget _coreCard(BuildContext context, AppLocalizations l) {
    final h = header;
    final cfg = h.matchFormatConfig;

    // Team size as a range; collapse to a single value when fixed.
    final teamSizeLabel = h.maxTeamSize > h.teamSize
        ? l.tournamentDetailTeamSizeRange(h.teamSize, h.maxTeamSize)
        : l.tournamentDetailTeamSizeFixed(h.teamSize);

    // Round time: canonical `round_time_seconds`, with fallbacks to the
    // legacy `time_limit_seconds` (seconds) and `round_time_minutes`.
    final roundTimeMinutes = _roundTimeMinutes(cfg);

    final scoringLabel = switch (h.scoring) {
      TournamentScoring.ekc => l.tournamentDetailScoringEkc,
      TournamentScoring.classic => l.tournamentDetailScoringClassic,
    };

    final rows = <Widget>[
      _row(context, l.tournamentDetailFormat, formatLabel(h.format, l)),
      _row(context, l.tournamentDetailTeamSize, teamSizeLabel),
      _row(context, l.tournamentDetailScoring, scoringLabel),
      if (_num(cfg['sets_to_win']) != null)
        _row(context, l.tournamentDetailSetsToWin, '${_num(cfg['sets_to_win'])}'),
      if (_num(cfg['max_sets']) != null)
        _row(context, l.tournamentDetailMaxSets, '${_num(cfg['max_sets'])}'),
      if (roundTimeMinutes != null)
        _row(context, l.tournamentDetailRoundTime,
            l.tournamentDetailMinutes(roundTimeMinutes)),
      if (_num(cfg['basekubbs_per_side']) != null)
        _row(context, l.tournamentDetailBasekubbs,
            '${_num(cfg['basekubbs_per_side'])}'),
      ..._tiebreakRows(context, l, cfg),
      if (_breakMinutes(cfg) != null)
        _row(context, l.tournamentDetailBreakBetween,
            l.tournamentDetailMinutes(_breakMinutes(cfg)!)),
    ];

    // The core card always has at least Format / Team-Grösse / Wertung, so it
    // always renders.
    return _card(context, l.tournamentDetailStammdaten, rows);
  }

  /// Tiebreak-set rows: only when explicitly enabled. When a threshold is set
  /// it is surfaced as minutes; otherwise just an "An" marker.
  List<Widget> _tiebreakRows(
      BuildContext context, AppLocalizations l, Map<String, Object?> cfg) {
    if (cfg['tiebreak_enabled'] != true) return const [];
    final after = _num(cfg['tiebreak_after_seconds']);
    final value = after != null
        ? l.tournamentDetailTiebreakAfter((after / 60).round())
        : l.tournamentDetailRuleOn;
    return [_row(context, l.tournamentDetailTiebreak, value)];
  }

  // ---- KO / Phase (B3.3) --------------------------------------------------

  List<Widget> _koPhaseCard(BuildContext context, AppLocalizations l) {
    final s = header.setup;
    final rows = <Widget>[];

    final bracketType = _str(s['bracket_type']);
    if (bracketType != null) {
      final label = switch (bracketType) {
        'double_elimination' => l.tournamentDetailBracketDouble,
        'single_elimination' => l.tournamentDetailBracketSingle,
        _ => bracketType,
      };
      rows.add(_row(context, l.tournamentDetailBracketType, label));
    }

    final koTiebreak = _str(s['ko_tiebreak_method']);
    if (koTiebreak != null) {
      final label = switch (koTiebreak) {
        'mighty_finisher_shootout' => l.tournamentDetailKoTiebreakMighty,
        'classic_kingtoss_removal' => l.tournamentDetailKoTiebreakClassic,
        _ => koTiebreak,
      };
      rows.add(_row(context, l.tournamentDetailKoTiebreakMethod, label));
    }

    final mighty = s['mighty_finisher_quali'];
    if (mighty is Map && mighty['enabled'] == true) {
      final slots = _num(mighty['slots']);
      rows.add(_row(
          context,
          l.tournamentDetailMightyFinisher,
          slots != null
              ? l.tournamentDetailMightyFinisherSlots(slots.toInt())
              : l.tournamentDetailRuleOn));
    }

    final ko = s['ko_config'];
    if (ko is Map && _num(ko['qualifier_count']) != null) {
      rows.add(_row(context, l.tournamentDetailKoSetup,
          l.tournamentDetailKoQualifiers((_num(ko['qualifier_count'])!).toInt())));
    }

    final pool = s['pool_phase_config'];
    if (pool is Map) {
      final groups = _num(pool['group_count']);
      final perGroup = _num(pool['qualifiers_per_group']);
      if (groups != null && perGroup != null) {
        rows.add(_row(
            context,
            l.tournamentDetailPoolConfig,
            l.tournamentDetailPoolConfigValue(
                groups.toInt(), perGroup.toInt())));
      }
    }

    return [_cardIfAny(context, l.tournamentDetailKoPhaseHeading, rows)];
  }

  // ---- P6-Metadaten (B3.4) ------------------------------------------------

  /// Assembles the read-only meta/setup cards from the header `setup` map.
  /// Every row is guarded behind a non-null / non-blank check so unset wizard
  /// fields stay hidden, and an all-empty card disappears entirely.
  List<Widget> _metaCards(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) {
    final h = header;
    final s = h.setup;

    // --- Veranstaltung (Ort / Adresse) ---
    final location = _str(s['location']);
    final address = _str(s['venue_address']);
    final infoCard = _cardIfAny(context, l.tournamentDetailInfoHeading, [
      if (location != null)
        _row(context, l.tournamentDetailLocation, location),
      if (address != null)
        _row(context, l.tournamentDetailVenueAddress, address),
    ]);

    // --- Termine ---
    final eventStart = _dateTime(s['event_starts_at']);
    final regCloses = _dateTime(s['registration_closes_at']);
    final checkin = _dateTime(s['checkin_until']);
    final datesCard = _cardIfAny(context, l.tournamentDetailDatesHeading, [
      if (eventStart != null)
        _row(context, l.tournamentDetailEventStart, eventStart),
      if (regCloses != null)
        _row(context, l.tournamentDetailRegistrationCloses, regCloses),
      if (checkin != null)
        _row(context, l.tournamentDetailCheckinUntil, checkin),
    ]);

    // --- Gebühr & Zahlung ---
    final feeCents = s['entry_fee_cents'];
    final currency = _str(s['currency']) ?? 'CHF';
    final payments = _stringList(s['payment_methods']);
    final feeCard = _cardIfAny(context, l.tournamentDetailFeeHeading, [
      if (feeCents is num && feeCents > 0)
        _row(context, l.tournamentDetailEntryFee,
            _money(feeCents.toInt(), currency)),
      if (payments.isNotEmpty)
        _row(context, l.tournamentDetailPaymentMethods, payments.join(', ')),
    ]);

    // --- Kontakt ---
    final contactName = _str(s['contact_name']);
    final contactPhone = _str(s['contact_phone']);
    final contactCard = _cardIfAny(context, l.tournamentDetailContactHeading, [
      if (contactName != null)
        _row(context, l.tournamentDetailContactName, contactName),
      if (contactPhone != null)
        _row(context, l.tournamentDetailContactPhone, contactPhone),
    ]);

    // --- Infos für Teilnehmer ---
    final infoFood = _str(s['info_food']);
    final infoTravel = _str(s['info_travel']);
    final infoAccom = _str(s['info_accommodation']);
    final weather = _str(s['weather_note']);
    final infoTextsCard =
        _cardIfAny(context, l.tournamentDetailInfoTextsHeading, [
      if (infoFood != null)
        _row(context, l.tournamentDetailInfoFood, infoFood),
      if (infoTravel != null)
        _row(context, l.tournamentDetailInfoTravel, infoTravel),
      if (infoAccom != null)
        _row(context, l.tournamentDetailInfoAccommodation, infoAccom),
      if (weather != null)
        _row(context, l.tournamentDetailWeatherNote, weather),
    ]);

    // --- Regel-Varianten ---
    final rv = s['rule_variants'];
    final rules = <Widget>[];
    if (rv is Map) {
      String onOff(Object? v) =>
          v == true ? l.tournamentDetailRuleOn : l.tournamentDetailRuleOff;
      rules
        ..add(_row(context, l.tournamentDetailRuleDiggy, onOff(rv['diggy'])))
        ..add(_row(
            context, l.tournamentDetailRuleSureshot, onOff(rv['sureshot'])))
        ..add(_row(context, l.tournamentDetailRuleStrafkubb,
            onOff(rv['strafkubb_off_baseline'])));
      final opening = _str(rv['opening_rule']);
      if (opening != null) {
        rules.add(_row(context, l.tournamentDetailRuleOpening, opening));
      }
    }
    final rulesCard =
        _cardIfAny(context, l.tournamentDetailRulesHeading, rules);

    // --- Veranstalter & Liga ---
    // Guarded like every other meta card: the club / fun-tournament row only
    // renders when a club is actually set OR at least one other org field
    // (leagues / consolation) carries info, so the whole card disappears for
    // a bare tournament. Format/KO live in the core / KO-phase cards above.
    final orgRows = <Widget>[];
    final clubId = _str(h.clubId);
    final leagues = (s['league_categories'] is List)
        ? (s['league_categories']! as List)
            .map((e) => e?.toString().trim().toUpperCase() ?? '')
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];
    if (leagues.isNotEmpty) {
      orgRows.add(_row(context, l.tournamentDetailLeagueCategories,
          leagues.join(', ')));
    }
    final consolationName = _consolationName(s);
    if (consolationName != null) {
      orgRows.add(_row(
          context, l.tournamentDetailConsolationLabel, consolationName));
    }
    if (clubId != null) {
      orgRows.insert(0, _row(context, l.tournamentDetailClubLabel, clubId));
    } else if (orgRows.isNotEmpty) {
      orgRows.insert(
          0,
          _row(context, l.tournamentDetailClubLabel,
              l.tournamentDetailFunTournament));
    }
    final orgCard =
        _cardIfAny(context, l.tournamentDetailOrganizationHeading, orgRows);

    // --- Dokumente (PDF-Download) ---
    final rulesPdf = _str(s['rules_pdf_url']);
    final siteMapPdf = _str(s['site_map_pdf_url']);
    final docRows = <Widget>[
      if (rulesPdf != null)
        _PdfDownloadButton(label: l.tournamentDetailRulesPdf, url: rulesPdf),
      if (siteMapPdf != null)
        _PdfDownloadButton(
            label: l.tournamentDetailSiteMapPdf, url: siteMapPdf),
    ];
    final docsCard =
        _cardIfAny(context, l.tournamentDetailDocumentsHeading, docRows);

    return [
      infoCard,
      datesCard,
      feeCard,
      contactCard,
      infoTextsCard,
      rulesCard,
      orgCard,
      docsCard,
    ];
  }

  // ---- helpers ------------------------------------------------------------

  /// Round time in whole minutes, reading the canonical
  /// `round_time_seconds` first, then the legacy `time_limit_seconds`
  /// (seconds) and `round_time_minutes`. Null when none is set.
  int? _roundTimeMinutes(Map<String, Object?> cfg) {
    final secs = _num(cfg['round_time_seconds']) ?? _num(cfg['time_limit_seconds']);
    if (secs != null) return (secs / 60).round();
    final mins = _num(cfg['round_time_minutes']);
    return mins?.toInt();
  }

  int? _breakMinutes(Map<String, Object?> cfg) {
    final secs = _num(cfg['break_between_matches_seconds']);
    if (secs == null || secs <= 0) return null;
    return (secs / 60).round();
  }
}

// ---- shared formatting / chrome -----------------------------------------

// Font sizes match the existing detail-screen `_row`/`_card` chrome 1:1 so the
// shared card stays visually consistent with the rest of the tournament detail
// screen. Kept as named constants instead of bare literals.
const double _kRowLabelFontSize = 13;
const double _kRowValueFontSize = 14;
const double _kCardHeadingFontSize = 11;

num? _num(Object? v) => v is num ? v : null;

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

List<String> _stringList(Object? v) => v is List
    ? v
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList()
    : const <String>[];

/// Formats an ISO-8601 timestamp into a compact `dd.MM.yyyy HH:mm` label.
/// Returns null on absent or unparseable input so the row is skipped.
String? _dateTime(Object? raw) {
  final s = _str(raw);
  if (s == null) return null;
  final dt = DateTime.tryParse(s)?.toLocal();
  if (dt == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// Formats an integer cents amount + currency into e.g. `CHF 10.00`.
String _money(int cents, String currency) {
  final major = (cents / 100).toStringAsFixed(2);
  return '$currency $major';
}

/// The configured consolation/Trostturnier name. Null/blank when unset.
String? _consolationName(Map<String, Object?> setup) {
  final c = setup['consolation_bracket'];
  if (c is! Map) return null;
  return _str(c['name']);
}

Widget _row(BuildContext context, String label, String value) {
  final tokens = Theme.of(context).extension<KubbTokens>()!;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
    child: Row(children: [
      Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: _kRowLabelFontSize, color: tokens.fgMuted))),
      Text(value,
          style: TextStyle(
              fontSize: _kRowValueFontSize,
              fontWeight: FontWeight.w700,
              color: tokens.fg)),
    ]),
  );
}

/// Card chrome matching the rest of the detail screen.
Widget _card(BuildContext context, String heading, List<Widget> children) {
  final tokens = Theme.of(context).extension<KubbTokens>()!;
  return Container(
    padding: const EdgeInsets.all(KubbTokens.space4),
    decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(heading.toUpperCase(),
          style: TextStyle(
              fontSize: _kCardHeadingFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.88,
              color: tokens.fgMuted)),
      const SizedBox(height: KubbTokens.space2),
      ...children,
    ]),
  );
}

/// Builds a card only when at least one row is present; an empty list yields
/// nothing (no empty header, no empty row). Spaced above the previous card.
Widget _cardIfAny(BuildContext context, String heading, List<Widget> rows) {
  if (rows.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: KubbTokens.space5),
    child: _card(context, heading, rows),
  );
}

/// A touch-friendly download button that opens the public Storage URL of an
/// uploaded tournament PDF via the injectable [tournamentUrlOpenerProvider].
class _PdfDownloadButton extends ConsumerWidget {
  const _PdfDownloadButton({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
      child: SizedBox(
        height: KubbTokens.touchMin,
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(label),
          ),
          onPressed: () async {
            final open = ref.read(tournamentUrlOpenerProvider);
            final l = AppLocalizations.of(context);
            final uri = Uri.tryParse(url);
            var ok = false;
            if (uri != null) {
              try {
                ok = await open(uri);
              } on Object {
                ok = false;
              }
            }
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(l.tournamentDetailPdfOpenError),
                  backgroundColor: KubbTokens.miss));
            }
          },
        ),
      ),
    );
  }
}
