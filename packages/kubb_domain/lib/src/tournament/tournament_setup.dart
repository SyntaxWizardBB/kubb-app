import 'package:meta/meta.dart';

/// P6 tournament-setup value objects (Phase 0: data model).
///
/// These mirror the JSONB columns added in the
/// `20261001000001_tournament_setup_fields` migration. Every type is an
/// immutable value object with round-tripping `toJson`/`fromJson` using
/// the SAME snake_case keys as the SQL side, so the wire contract stays
/// in lock-step. Validation that the wizard surfaces lives in
/// `TournamentConfigDraft.validate`; reusable invariants live here as
/// instance `issues()` helpers.

// ---- League categories (A/B/C, multi-select) --------------------------

/// League tier a tournament counts for. A tournament may target several
/// at once (e.g. "A & B"), so callers hold a `List<LeagueCategory>`.
enum LeagueCategory {
  a('A'),
  b('B'),
  c('C');

  const LeagueCategory(this.wire);

  /// Stored value in `tournaments.league_categories`.
  final String wire;

  static LeagueCategory fromWire(String value) =>
      LeagueCategory.values.firstWhere(
        (c) => c.wire == value,
        orElse: () => throw ArgumentError.value(
            value, 'value', 'unknown league category'),
      );
}

// ---- Match format spec (per phase) ------------------------------------

/// Match rules for one phase (prelim or KO). Decision "Vorrunde + KO
/// getrennt": the prelim phase and the KO phase each carry their own
/// spec. [finalNoTiebreak] is only meaningful on the KO spec and covers
/// the common "ab Halbfinale ohne Tiebreak" rule without a full
/// per-KO-round model.
@immutable
final class MatchFormatSpec {
  const MatchFormatSpec({
    required this.setsToWin,
    required this.maxSets,
    required this.timeLimitSeconds,
    this.tiebreakEnabled = true,
    this.tiebreakAfterSeconds,
    this.breakBetweenMatchesSeconds = 0,
    this.basekubbsPerSide = 5,
    this.finalNoTiebreak = false,
  });

  factory MatchFormatSpec.fromJson(Map<String, Object?> json) =>
      MatchFormatSpec(
        setsToWin: (json['sets_to_win']! as num).toInt(),
        maxSets: (json['max_sets']! as num).toInt(),
        timeLimitSeconds: (json['time_limit_seconds']! as num).toInt(),
        tiebreakEnabled: json['tiebreak_enabled'] as bool? ?? true,
        tiebreakAfterSeconds: (json['tiebreak_after_seconds'] as num?)?.toInt(),
        breakBetweenMatchesSeconds:
            (json['break_between_matches_seconds'] as num?)?.toInt() ?? 0,
        basekubbsPerSide: (json['basekubbs_per_side'] as num?)?.toInt() ?? 5,
        finalNoTiebreak: json['final_no_tiebreak'] as bool? ?? false,
      );

  final int setsToWin;
  final int maxSets;

  /// Hard time limit for a match. After this the running throw round is
  /// finished and the current score is recorded.
  final int timeLimitSeconds;

  /// Whether a tiebreak is played at all in this phase.
  final bool tiebreakEnabled;

  /// When the tiebreak is triggered (< [timeLimitSeconds]). Null when
  /// [tiebreakEnabled] is false.
  final int? tiebreakAfterSeconds;

  /// Configured break between consecutive matches (organiser planning).
  final int breakBetweenMatchesSeconds;

  final int basekubbsPerSide;

  /// KO-only: skip the tiebreak from a configured late stage (final /
  /// semis). Ignored for the prelim spec.
  final bool finalNoTiebreak;

  /// Reusable invariants; the draft aggregates these for the wizard.
  List<String> issues() {
    final out = <String>[];
    if (setsToWin < 1 || setsToWin > 4) {
      out.add('Sätze zum Sieg muss zwischen 1 und 4 liegen.');
    }
    if (maxSets < 2 * setsToWin - 1) {
      out.add('Max. Sätze muss mindestens ${2 * setsToWin - 1} sein.');
    }
    if (timeLimitSeconds < 60) {
      out.add('Zeitlimit muss mindestens eine Minute sein.');
    }
    if (tiebreakEnabled) {
      final after = tiebreakAfterSeconds;
      if (after == null || after < 60) {
        out.add('Tiebreak-Zeit muss mindestens eine Minute sein.');
      } else if (after > timeLimitSeconds) {
        out.add('Tiebreak-Zeit darf nicht über dem Zeitlimit liegen.');
      }
    }
    if (breakBetweenMatchesSeconds < 0) {
      out.add('Pause zwischen Matches darf nicht negativ sein.');
    }
    if (basekubbsPerSide < 1) {
      out.add('Basiskubbs pro Seite muss mindestens 1 sein.');
    }
    return out;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'sets_to_win': setsToWin,
        'max_sets': maxSets,
        'time_limit_seconds': timeLimitSeconds,
        'tiebreak_enabled': tiebreakEnabled,
        'tiebreak_after_seconds': tiebreakAfterSeconds,
        'break_between_matches_seconds': breakBetweenMatchesSeconds,
        'basekubbs_per_side': basekubbsPerSide,
        'final_no_tiebreak': finalNoTiebreak,
      };

  MatchFormatSpec copyWith({
    int? setsToWin,
    int? maxSets,
    int? timeLimitSeconds,
    bool? tiebreakEnabled,
    int? tiebreakAfterSeconds,
    int? breakBetweenMatchesSeconds,
    int? basekubbsPerSide,
    bool? finalNoTiebreak,
  }) =>
      MatchFormatSpec(
        setsToWin: setsToWin ?? this.setsToWin,
        maxSets: maxSets ?? this.maxSets,
        timeLimitSeconds: timeLimitSeconds ?? this.timeLimitSeconds,
        tiebreakEnabled: tiebreakEnabled ?? this.tiebreakEnabled,
        tiebreakAfterSeconds: tiebreakAfterSeconds ?? this.tiebreakAfterSeconds,
        breakBetweenMatchesSeconds:
            breakBetweenMatchesSeconds ?? this.breakBetweenMatchesSeconds,
        basekubbsPerSide: basekubbsPerSide ?? this.basekubbsPerSide,
        finalNoTiebreak: finalNoTiebreak ?? this.finalNoTiebreak,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchFormatSpec &&
          other.setsToWin == setsToWin &&
          other.maxSets == maxSets &&
          other.timeLimitSeconds == timeLimitSeconds &&
          other.tiebreakEnabled == tiebreakEnabled &&
          other.tiebreakAfterSeconds == tiebreakAfterSeconds &&
          other.breakBetweenMatchesSeconds == breakBetweenMatchesSeconds &&
          other.basekubbsPerSide == basekubbsPerSide &&
          other.finalNoTiebreak == finalNoTiebreak;

  @override
  int get hashCode => Object.hash(
        setsToWin,
        maxSets,
        timeLimitSeconds,
        tiebreakEnabled,
        tiebreakAfterSeconds,
        breakBetweenMatchesSeconds,
        basekubbsPerSide,
        finalNoTiebreak,
      );
}

// ---- Rule variants ----------------------------------------------------

/// The per-tournament rule toggles every organiser mail states. The
/// `scoring` (ekc/classic) choice stays its own draft/column field.
@immutable
final class RuleVariants {
  const RuleVariants({
    this.sureshot = false,
    this.diggy = false,
    this.openingRule = '2-4-6',
    this.strafkubbOffBaseline = true,
  });

  factory RuleVariants.fromJson(Map<String, Object?> json) => RuleVariants(
        sureshot: json['sureshot'] as bool? ?? false,
        diggy: json['diggy'] as bool? ?? false,
        openingRule: json['opening_rule'] as String? ?? '2-4-6',
        strafkubbOffBaseline: json['strafkubb_off_baseline'] as bool? ?? true,
      );

  /// false (default) = king may be felled normally from the front.
  final bool sureshot;

  /// Diggy / double-award-kubb rule active.
  final bool diggy;

  /// Anspielregel, e.g. "2-4-6".
  final String openingRule;

  /// Penalty kubb must stand at least one stick length off the baseline.
  final bool strafkubbOffBaseline;

  Map<String, Object?> toJson() => <String, Object?>{
        'sureshot': sureshot,
        'diggy': diggy,
        'opening_rule': openingRule,
        'strafkubb_off_baseline': strafkubbOffBaseline,
      };

  RuleVariants copyWith({
    bool? sureshot,
    bool? diggy,
    String? openingRule,
    bool? strafkubbOffBaseline,
  }) =>
      RuleVariants(
        sureshot: sureshot ?? this.sureshot,
        diggy: diggy ?? this.diggy,
        openingRule: openingRule ?? this.openingRule,
        strafkubbOffBaseline: strafkubbOffBaseline ?? this.strafkubbOffBaseline,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleVariants &&
          other.sureshot == sureshot &&
          other.diggy == diggy &&
          other.openingRule == openingRule &&
          other.strafkubbOffBaseline == strafkubbOffBaseline;

  @override
  int get hashCode =>
      Object.hash(sureshot, diggy, openingRule, strafkubbOffBaseline);
}

// ---- Pitch plan -------------------------------------------------------

/// How the available pitch numbers are derived.
enum PitchMode {
  range('range'),
  manual('manual');

  const PitchMode(this.wire);
  final String wire;

  static PitchMode fromWire(String value) => PitchMode.values.firstWhere(
        (m) => m.wire == value,
        orElse: () =>
            throw ArgumentError.value(value, 'value', 'unknown pitch mode'),
      );
}

/// How pitches are ordered relative to seeding strength.
enum PitchSortStrategy {
  /// Top-ranked players play on the lowest pitch numbers (organiser
  /// "Showcourt"-style ordering).
  topSeedsLowNumbers('top_seeds_low_numbers'),

  /// Organiser-defined manual order ([PitchPlan.order]).
  manual('manual');

  const PitchSortStrategy(this.wire);
  final String wire;

  static PitchSortStrategy fromWire(String value) =>
      PitchSortStrategy.values.firstWhere(
        (s) => s.wire == value,
        orElse: () => throw ArgumentError.value(
            value, 'value', 'unknown pitch sort strategy'),
      );
}

/// The pitch range/list a tournament occupies on a shared venue, plus
/// optional per-group assignment for the pool phase.
@immutable
final class PitchPlan {
  const PitchPlan({
    required this.mode,
    this.rangeFrom,
    this.rangeTo,
    this.numbers = const <int>[],
    this.order = const <int>[],
    this.sortStrategy = PitchSortStrategy.topSeedsLowNumbers,
    this.groupAssignment = const <String, List<int>>{},
  });

  factory PitchPlan.fromJson(Map<String, Object?> json) {
    final rawNumbers = (json['numbers'] as List?) ?? const <Object?>[];
    final rawOrder = (json['order'] as List?) ?? const <Object?>[];
    final rawGroups = (json['group_assignment'] as Map?) ?? const {};
    return PitchPlan(
      mode: PitchMode.fromWire(json['mode']! as String),
      rangeFrom: (json['range_from'] as num?)?.toInt(),
      rangeTo: (json['range_to'] as num?)?.toInt(),
      numbers: rawNumbers.map((e) => (e! as num).toInt()).toList(),
      order: rawOrder.map((e) => (e! as num).toInt()).toList(),
      sortStrategy: json['sort_strategy'] == null
          ? PitchSortStrategy.topSeedsLowNumbers
          : PitchSortStrategy.fromWire(json['sort_strategy']! as String),
      groupAssignment: rawGroups.map(
        (k, v) => MapEntry(
          k! as String,
          (v! as List).map((e) => (e! as num).toInt()).toList(),
        ),
      ),
    );
  }

  final PitchMode mode;
  final int? rangeFrom;
  final int? rangeTo;
  final List<int> numbers;
  final List<int> order;
  final PitchSortStrategy sortStrategy;
  final Map<String, List<int>> groupAssignment;

  /// Effective list of pitch numbers, honouring an explicit [order] when
  /// present. For [PitchMode.range] this expands `rangeFrom..rangeTo`.
  List<int> availablePitches() {
    final from = rangeFrom;
    final to = rangeTo;
    final base = switch (mode) {
      PitchMode.range => (from != null && to != null)
          ? <int>[for (var n = from; n <= to; n++) n]
          : const <int>[],
      PitchMode.manual => List<int>.of(numbers),
    };
    if (order.isEmpty) return base;
    final inOrder = order.where(base.contains).toList();
    final rest = base.where((n) => !order.contains(n));
    return <int>[...inOrder, ...rest];
  }

  List<String> issues() {
    final out = <String>[];
    switch (mode) {
      case PitchMode.range:
        final from = rangeFrom;
        final to = rangeTo;
        if (from == null || to == null) {
          out.add('Pitch-Bereich (von/bis) fehlt.');
        } else if (from < 1 || to < from) {
          out.add('Pitch-Bereich ist ungültig.');
        }
      case PitchMode.manual:
        if (numbers.isEmpty) {
          out.add('Mindestens eine Pitch-Nummer angeben.');
        } else if (numbers.toSet().length != numbers.length) {
          out.add('Pitch-Nummern dürfen sich nicht wiederholen.');
        }
    }
    return out;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'mode': mode.wire,
        'range_from': rangeFrom,
        'range_to': rangeTo,
        'numbers': numbers,
        'order': order,
        'sort_strategy': sortStrategy.wire,
        'group_assignment': groupAssignment.map(
          (k, v) => MapEntry(k, List<int>.of(v)),
        ),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchPlan &&
          other.mode == mode &&
          other.rangeFrom == rangeFrom &&
          other.rangeTo == rangeTo &&
          _listEq(other.numbers, numbers) &&
          _listEq(other.order, order) &&
          other.sortStrategy == sortStrategy &&
          _groupEq(other.groupAssignment, groupAssignment);

  @override
  int get hashCode => Object.hash(
        mode,
        rangeFrom,
        rangeTo,
        Object.hashAll(numbers),
        Object.hashAll(order),
        sortStrategy,
        Object.hashAll(
          groupAssignment.entries
              .map((e) => Object.hash(e.key, Object.hashAll(e.value))),
        ),
      );
}

// ---- Mighty-Finisher qualification ------------------------------------

/// Shootout used as a QUALIFICATION stage between the group phase and the
/// KO (Wasserschloss model). Distinct from the KO tiebreak method.
@immutable
final class MightyFinisherQuali {
  const MightyFinisherQuali({
    this.enabled = false,
    this.slots = 0,
    this.source = 'group_runner_ups',
  });

  factory MightyFinisherQuali.fromJson(Map<String, Object?> json) =>
      MightyFinisherQuali(
        enabled: json['enabled'] as bool? ?? false,
        slots: (json['slots'] as num?)?.toInt() ?? 0,
        source: json['source'] as String? ?? 'group_runner_ups',
      );

  final bool enabled;

  /// Number of remaining KO slots the shootout fills.
  final int slots;

  /// Where the shootout participants come from.
  final String source;

  List<String> issues() {
    final out = <String>[];
    if (enabled && slots < 1) {
      out.add('Mighty-Finisher-Quali braucht mindestens einen Platz.');
    }
    return out;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'slots': slots,
        'source': source,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MightyFinisherQuali &&
          other.enabled == enabled &&
          other.slots == slots &&
          other.source == source;

  @override
  int get hashCode => Object.hash(enabled, slots, source);
}

// ---- Consolation bracket ----------------------------------------------

/// A second KO bracket for players knocked out early (Bâton Rouille /
/// "Best of the Rest").
@immutable
final class ConsolationConfig {
  const ConsolationConfig({
    this.enabled = false,
    this.sourceRounds = const <int>[],
    this.matchFormat,
  });

  factory ConsolationConfig.fromJson(Map<String, Object?> json) {
    final rawRounds = (json['source_rounds'] as List?) ?? const <Object?>[];
    final rawFormat = json['match_format'];
    return ConsolationConfig(
      enabled: json['enabled'] as bool? ?? false,
      sourceRounds: rawRounds.map((e) => (e! as num).toInt()).toList(),
      matchFormat: rawFormat == null
          ? null
          : MatchFormatSpec.fromJson((rawFormat as Map).cast<String, Object?>()),
    );
  }

  final bool enabled;

  /// KO rounds whose losers drop into the consolation bracket
  /// (e.g. `[1, 2]` = round of 128 + round of 64).
  final List<int> sourceRounds;

  /// Own match rules for the consolation bracket. Null => reuse the KO
  /// match format.
  final MatchFormatSpec? matchFormat;

  List<String> issues() {
    final out = <String>[];
    if (enabled && sourceRounds.isEmpty) {
      out.add('Trostturnier braucht mindestens eine Quell-Runde.');
    }
    final fmt = matchFormat;
    if (fmt != null) out.addAll(fmt.issues());
    return out;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'source_rounds': sourceRounds,
        'match_format': matchFormat?.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConsolationConfig &&
          other.enabled == enabled &&
          _listEq(other.sourceRounds, sourceRounds) &&
          other.matchFormat == matchFormat;

  @override
  int get hashCode =>
      Object.hash(enabled, Object.hashAll(sourceRounds), matchFormat);
}

// ---- small helpers ----------------------------------------------------

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _groupEq(Map<String, List<int>> a, Map<String, List<int>> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !_listEq(entry.value, other)) return false;
  }
  return true;
}
