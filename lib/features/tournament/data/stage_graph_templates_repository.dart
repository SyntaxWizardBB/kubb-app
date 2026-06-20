import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Visibility scope of a stage-graph template (ADR-0030 §Templates).
///
/// Stable lowercase wire strings are part of the persistence contract and are
/// NOT derived from the enum name, mirroring the `kubb_domain` enum convention
/// (`StageNodeType.fromWire`/`toWire`). Unlike the domain enums, [fromWire]
/// degrades gracefully to [private] for an unknown value so a future
/// server-side visibility never crashes the client mapper.
enum TemplateVisibility {
  /// Visible only to the owner.
  private('private'),

  /// Visible to members of the owning club.
  club('club'),

  /// Visible to everyone.
  public('public');

  const TemplateVisibility(this.wire);

  /// Stable lowercase wire string (persistence contract).
  final String wire;

  /// Serializes this value to its stable wire string.
  String toWire() => wire;

  /// Parses [wire] back to a [TemplateVisibility]. Robust by design: an
  /// unknown/empty value falls back to [private] (the most restrictive scope)
  /// instead of throwing, so a row that carries a future visibility value can
  /// still be mapped.
  static TemplateVisibility fromWire(String? wire) {
    for (final v in TemplateVisibility.values) {
      if (v.wire == wire) return v;
    }
    return TemplateVisibility.private;
  }
}

/// A reusable stage-graph template (ADR-0030 §Templates).
///
/// Wraps the pure-domain [StageGraph] with persistence metadata. System presets
/// (shipped, ownerless) sort first in the picker; user/club templates carry an
/// owner. [isSystem] is derived in [templateFromRow] from a `null`
/// `owner_user_id` and is not persisted as its own column.
@immutable
class StageGraphTemplate {
  /// Creates a stage-graph template.
  const StageGraphTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.visibility,
    required this.graph,
    required this.isSystem,
    this.pitchPlan,
  });

  /// Stable template id (uuid).
  final String id;

  /// Display name.
  final String name;

  /// Optional human description.
  final String? description;

  /// Visibility scope.
  final TemplateVisibility visibility;

  /// The reusable stage graph (reused `kubb_domain` model).
  final StageGraph graph;

  /// Whether this is an ownerless system preset (`owner_user_id == null`).
  final bool isSystem;

  /// Optional pitch plan saved alongside the graph (#11). Null for templates
  /// stored before the pitch-plan column existed, or for a standalone save
  /// outside the wizard (no draft/pitch context). When present, the wizard
  /// restores it into the config draft on apply.
  final PitchPlan? pitchPlan;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageGraphTemplate &&
          other.id == id &&
          other.name == name &&
          other.description == description &&
          other.visibility == visibility &&
          other.graph == graph &&
          other.isSystem == isSystem &&
          other.pitchPlan == pitchPlan;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        description,
        visibility,
        graph,
        isSystem,
        pitchPlan,
      );

  @override
  String toString() =>
      'StageGraphTemplate(id: $id, name: $name, visibility: ${visibility.wire}, '
      'isSystem: $isSystem)';
}

/// Maps one raw `tournament_stage_graph_templates` row onto a
/// [StageGraphTemplate]. Null-/type-robust analog to `eloLeaderboardRowFromRow`:
///
///  * `id`/`name` fall back to `''` when absent (PostgREST never omits them in
///    practice; the fallback only guards a degenerate row).
///  * `description` is genuinely nullable.
///  * `visibility` is parsed via [TemplateVisibility.fromWire] (defaults to
///    `private` on an unknown value).
///  * `graph` is parsed from the `jsonb` column via [StageGraph.fromJson]
///    (reusing the domain deserializer). The PostgREST driver normally hands
///    back an already-decoded `Map`, so we cast robustly to
///    `Map<String, Object?>`.
///  * `isSystem` is derived from `owner_user_id == null`.
StageGraphTemplate templateFromRow(Map<String, dynamic> row) {
  final rawGraph = row['graph'];
  // The driver hands back an already-decoded map for a jsonb column. Cast key
  // and value types robustly so StageGraph.fromJson sees `Map<String, Object?>`.
  final graphMap = (rawGraph as Map).map(
    (key, value) => MapEntry(key as String, value as Object?),
  );
  // pitch_plan is nullable (older rows / pitch-less saves). Parse it the same
  // way as graph when present; a null column stays a null PitchPlan.
  final rawPitchPlan = row['pitch_plan'];
  final pitchPlan = rawPitchPlan is Map
      ? PitchPlan.fromJson(
          rawPitchPlan.map(
            (key, value) => MapEntry(key as String, value as Object?),
          ),
        )
      : null;
  return StageGraphTemplate(
    id: row['id'] as String? ?? '',
    name: row['name'] as String? ?? '',
    description: row['description'] as String?,
    visibility: TemplateVisibility.fromWire(row['visibility'] as String?),
    graph: StageGraph.fromJson(graphMap),
    isSystem: row['owner_user_id'] == null,
    pitchPlan: pitchPlan,
  );
}

/// Signature of the low-level RPC call the repository delegates to for the
/// `save_*`/`apply_*` template RPCs. Production wiring forwards to
/// `SupabaseClient.rpc`; tests inject a capturing fake to assert the exact RPC
/// name + params without a live Supabase backend (analog to the ELO repo's
/// `EloLeaderboardRpcCaller`).
typedef StageGraphTemplateRpcCaller = Future<Object?> Function(
  String fn,
  Map<String, dynamic> params,
);

/// Signature of the low-level select call the repository delegates to for
/// [StageGraphTemplatesRepository.listTemplates]. Production wiring forwards to
/// `SupabaseClient.from(table).select()`; tests inject a capturing fake that
/// returns canned rows so the select + mapping + sort can be exercised without
/// a live backend.
typedef StageGraphTemplateSelectCaller = Future<List<dynamic>> Function(
  String table,
);

/// Repository for stage-graph templates (ADR-0030 §Templates) backed by the
/// L3a server objects: table `tournament_stage_graph_templates` and the RPCs
/// `save_stage_graph_template` / `apply_stage_graph_template`.
///
/// Persistence (save/apply) goes exclusively through the two RPCs; no write
/// logic is duplicated here or in the builder controller.
class StageGraphTemplatesRepository {
  /// Production constructor: wires the select + RPC seams to a live client.
  StageGraphTemplatesRepository({required SupabaseClient client})
      : _select = ((table) => client.from(table).select()),
        _rpc = ((fn, params) => client.rpc<Object?>(fn, params: params));

  /// Test seam: build the repository around captured select + RPC callers
  /// instead of a live client (analog to `EloLeaderboardRepository.withRpc`).
  StageGraphTemplatesRepository.withSeams({
    required StageGraphTemplateSelectCaller select,
    required StageGraphTemplateRpcCaller rpc,
  })  : _select = select,
        _rpc = rpc;

  final StageGraphTemplateSelectCaller _select;
  final StageGraphTemplateRpcCaller _rpc;

  /// Exact table name (L3a). Exposed as a constant so the contract test can
  /// assert it without re-typing the literal.
  static const String tableName = 'tournament_stage_graph_templates';

  /// Exact RPC name for saving a template (L3a `save_stage_graph_template`).
  static const String saveRpcName = 'save_stage_graph_template';

  /// Exact RPC name for applying a template (L3a `apply_stage_graph_template`).
  static const String applyRpcName = 'apply_stage_graph_template';

  /// Param keys of `save_stage_graph_template(name, description, visibility,
  /// graph, club_id)`.
  static const String saveNameParam = 'name';
  static const String saveDescriptionParam = 'description';
  static const String saveVisibilityParam = 'visibility';
  static const String saveGraphParam = 'graph';
  static const String saveClubIdParam = 'club_id';
  static const String savePitchPlanParam = 'pitch_plan';

  /// Param keys of `apply_stage_graph_template(tournament_id, template_id)`.
  static const String applyTournamentIdParam = 'tournament_id';
  static const String applyTemplateIdParam = 'template_id';

  /// Lists the templates visible to the caller (ADR-0030 §Templates).
  ///
  /// Issues a plain `select()` on [tableName]; visibility is NOT filtered
  /// client-side — Row-Level Security filters server-side which rows the caller
  /// may see. The result is sorted deterministically client-side (not relying
  /// on a server `.order()`): system presets first (`isSystem == true` before
  /// `false`), then by `name` ascending (case-sensitive `String.compareTo`),
  /// tie-broken by `id` so the order is total and stable.
  Future<List<StageGraphTemplate>> listTemplates() async {
    final rows = await _select(tableName);
    final templates = rows
        .cast<Map<String, dynamic>>()
        .map(templateFromRow)
        .toList(growable: false);
    final sorted = List<StageGraphTemplate>.of(templates)
      ..sort((a, b) {
        if (a.isSystem != b.isSystem) {
          // System presets first.
          return a.isSystem ? -1 : 1;
        }
        final byName = a.name.compareTo(b.name);
        if (byName != 0) return byName;
        return a.id.compareTo(b.id);
      });
    return List<StageGraphTemplate>.unmodifiable(sorted);
  }

  /// Saves a new stage-graph template via the L3a RPC
  /// `save_stage_graph_template(name, description, visibility, graph, club_id)`
  /// and returns the new template id (uuid).
  ///
  /// [graph] is serialized via `graph.toJson()` (reusing the domain
  /// serializer); [visibility] is passed as its wire string. The optional
  /// [pitchPlan] (#11) is serialized via its own `toJson()` and rides the
  /// `p_pitch_plan` RPC param; null when the caller has no pitch context
  /// (older templates / the standalone editor), keeping the wire backward
  /// compatible.
  Future<String> saveTemplate({
    required String name,
    required TemplateVisibility visibility,
    required StageGraph graph,
    String? description,
    String? clubId,
    PitchPlan? pitchPlan,
  }) async {
    final result = await _rpc(saveRpcName, <String, dynamic>{
      saveNameParam: name,
      saveDescriptionParam: description,
      saveVisibilityParam: visibility.toWire(),
      saveGraphParam: graph.toJson(),
      saveClubIdParam: clubId,
      savePitchPlanParam: pitchPlan?.toJson(),
    });
    return result! as String;
  }

  /// Applies a template onto a tournament via the L3a RPC
  /// `apply_stage_graph_template(tournament_id, template_id)` and returns the
  /// `RETURNS int` count (num-robust decode).
  Future<int> applyTemplate({
    required String tournamentId,
    required String templateId,
  }) async {
    final result = await _rpc(applyRpcName, <String, dynamic>{
      applyTournamentIdParam: tournamentId,
      applyTemplateIdParam: templateId,
    });
    return (result as num?)?.toInt() ?? 0;
  }
}

/// Repository provider (mirrors `seasonRepositoryProvider` /
/// `eloLeaderboardRepositoryProvider`).
final stageGraphTemplatesRepositoryProvider =
    Provider<StageGraphTemplatesRepository>(
  (ref) => StageGraphTemplatesRepository(client: Supabase.instance.client),
);

/// The list of stage-graph templates visible to the caller as an [AsyncValue]
/// (mirrors `eloLeaderboardProvider`). Invalidate to refresh after a save.
final stageGraphTemplatesProvider =
    FutureProvider<List<StageGraphTemplate>>(
  (ref) async =>
      ref.read(stageGraphTemplatesRepositoryProvider).listTemplates(),
);
