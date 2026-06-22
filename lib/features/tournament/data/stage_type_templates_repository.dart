import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart'
    show TemplateVisibility;
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A reusable stage-TYPE template (Ebene 2, spec §6/§9.6, ADR-0037/ADR-0039).
///
/// Wraps the pure-domain [StageTypeGraph] (one stage modelled as rounds /
/// fields / field-edges) with persistence metadata. System presets (shipped,
/// ownerless) sort first in the picker; user/club templates carry an owner.
/// [isSystem] is derived in [stageTypeTemplateFromRow] from a `null`
/// `owner_user_id` and is not persisted as its own column. Reuses
/// [TemplateVisibility] (the Ebene-1 visibility enum) — the 'club' wire value
/// maps to the owning Veranstalterteam.
@immutable
class StageTypeTemplate {
  /// Creates a stage-type template.
  const StageTypeTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.visibility,
    required this.category,
    required this.typeGraph,
    required this.isSystem,
  });

  /// Stable template id (uuid).
  final String id;

  /// Display name.
  final String name;

  /// Optional human description.
  final String? description;

  /// Visibility scope (private / club / public).
  final TemplateVisibility visibility;

  /// KO or Vorrunde — the type graph's category, mirrored as a column so a
  /// picker can group/badge without parsing the graph.
  final TypeStageCategory category;

  /// The reusable Ebene-2 type graph (reused `kubb_domain` model).
  final StageTypeGraph typeGraph;

  /// Whether this is an ownerless system preset (`owner_user_id == null`).
  final bool isSystem;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageTypeTemplate &&
          other.id == id &&
          other.name == name &&
          other.description == description &&
          other.visibility == visibility &&
          other.category == category &&
          other.typeGraph == typeGraph &&
          other.isSystem == isSystem;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        description,
        visibility,
        category,
        typeGraph,
        isSystem,
      );

  @override
  String toString() =>
      'StageTypeTemplate(id: $id, name: $name, visibility: ${visibility.wire}, '
      'category: ${category.wire}, isSystem: $isSystem)';
}

/// Maps one raw `tournament_stage_type_templates` row onto a
/// [StageTypeTemplate]. Null-/type-robust, modelled on `templateFromRow`:
///
///  * `id`/`name` fall back to `''` when absent.
///  * `description` is genuinely nullable.
///  * `visibility` is parsed via [TemplateVisibility.fromWire] (defaults to
///    `private` on an unknown value).
///  * `category` is read from the column when present, else recovered from the
///    `type_graph` body, and ultimately defaults to KO.
///  * `type_graph` is parsed from the `jsonb` column via
///    [StageTypeGraph.fromJson] (reusing the domain deserializer). The
///    PostgREST driver hands back an already-decoded `Map`.
///  * `isSystem` is derived from `owner_user_id == null`.
StageTypeTemplate stageTypeTemplateFromRow(Map<String, dynamic> row) {
  final rawGraph = row['type_graph'];
  final graphMap = (rawGraph as Map).map(
    (key, value) => MapEntry(key as String, value as Object?),
  );
  final categoryWire =
      row['category'] as String? ?? graphMap['category'] as String?;
  return StageTypeTemplate(
    id: row['id'] as String? ?? '',
    name: row['name'] as String? ?? '',
    description: row['description'] as String?,
    visibility: TemplateVisibility.fromWire(row['visibility'] as String?),
    category: _categoryFromWire(categoryWire),
    typeGraph: StageTypeGraph.fromJson(graphMap),
    isSystem: row['owner_user_id'] == null,
  );
}

TypeStageCategory _categoryFromWire(String? wire) {
  if (wire == null) return TypeStageCategory.ko;
  for (final c in TypeStageCategory.values) {
    if (c.wire == wire) return c;
  }
  return TypeStageCategory.ko;
}

/// Low-level RPC seam (mirrors the Ebene-1 template repo's RPC caller).
typedef StageTypeTemplateRpcCaller = Future<Object?> Function(
  String fn,
  Map<String, dynamic> params,
);

/// Low-level select seam (mirrors the Ebene-1 template repo's select caller).
typedef StageTypeTemplateSelectCaller = Future<List<dynamic>> Function(
  String table,
);

/// Repository for stage-TYPE templates (spec §6/§9.6) backed by the T11 server
/// objects: table `tournament_stage_type_templates` and the RPCs
/// `save_stage_type_template` / `apply_stage_type_template`.
///
/// Persistence (save/apply) goes exclusively through the two RPCs. [applyTemplate]
/// returns the stored [StageTypeGraph] (the apply RPC returns the raw
/// type_graph jsonb), which the setup UI loads into the
/// `stageTypeGraphBuilderProvider` via `loadFromGraph`.
class StageTypeTemplatesRepository {
  /// Production constructor: wires the select + RPC seams to a live client.
  StageTypeTemplatesRepository({required SupabaseClient client})
      : _select = ((table) => client.from(table).select()),
        _rpc = ((fn, params) => client.rpc<Object?>(fn, params: params));

  /// Test seam: build the repository around captured select + RPC callers.
  StageTypeTemplatesRepository.withSeams({
    required StageTypeTemplateSelectCaller select,
    required StageTypeTemplateRpcCaller rpc,
  })  : _select = select,
        _rpc = rpc;

  final StageTypeTemplateSelectCaller _select;
  final StageTypeTemplateRpcCaller _rpc;

  /// Exact table name (T11).
  static const String tableName = 'tournament_stage_type_templates';

  /// Exact RPC name for saving a type template (T11 `save_stage_type_template`).
  static const String saveRpcName = 'save_stage_type_template';

  /// Exact RPC name for applying a type template
  /// (T11 `apply_stage_type_template`).
  static const String applyRpcName = 'apply_stage_type_template';

  /// Param keys of `save_stage_type_template(name, description, visibility,
  /// type_graph, organizer_team_id, template_id)`.
  static const String saveNameParam = 'name';
  static const String saveDescriptionParam = 'description';
  static const String saveVisibilityParam = 'visibility';
  static const String saveTypeGraphParam = 'type_graph';
  static const String saveOrganizerTeamIdParam = 'organizer_team_id';
  static const String saveTemplateIdParam = 'template_id';

  /// Param key of `apply_stage_type_template(template_id)`.
  static const String applyTemplateIdParam = 'template_id';

  /// Lists the type templates visible to the caller (spec §9.6).
  ///
  /// Issues a plain `select()`; visibility is NOT filtered client-side — RLS
  /// decides which rows the caller may see. Sorted deterministically: system
  /// presets first, then by `name` ascending, tie-broken by `id`.
  Future<List<StageTypeTemplate>> listTemplates() async {
    final rows = await _select(tableName);
    final templates = rows
        .cast<Map<String, dynamic>>()
        .map(stageTypeTemplateFromRow)
        .toList(growable: false);
    final sorted = List<StageTypeTemplate>.of(templates)
      ..sort((a, b) {
        if (a.isSystem != b.isSystem) {
          return a.isSystem ? -1 : 1;
        }
        final byName = a.name.compareTo(b.name);
        if (byName != 0) return byName;
        return a.id.compareTo(b.id);
      });
    return List<StageTypeTemplate>.unmodifiable(sorted);
  }

  /// Saves a stage-type template via the T11 RPC `save_stage_type_template`
  /// and returns the template id (uuid). Passing [templateId] overwrites an
  /// existing template the caller owns; null inserts a fresh row.
  ///
  /// [typeGraph] is serialized via `typeGraph.toJson()`; [visibility] is passed
  /// as its wire string. [organizerTeamId] is required for `club` visibility.
  Future<String> saveTemplate({
    required String name,
    required TemplateVisibility visibility,
    required StageTypeGraph typeGraph,
    String? description,
    String? organizerTeamId,
    String? templateId,
  }) async {
    final result = await _rpc(saveRpcName, <String, dynamic>{
      saveNameParam: name,
      saveDescriptionParam: description,
      saveVisibilityParam: visibility.toWire(),
      saveTypeGraphParam: typeGraph.toJson(),
      saveOrganizerTeamIdParam: organizerTeamId,
      saveTemplateIdParam: templateId,
    });
    return result! as String;
  }

  /// Applies a type template via the T11 RPC `apply_stage_type_template` and
  /// returns the stored [StageTypeGraph] (round-trips through
  /// `StageTypeGraph.fromJson`). The setup UI loads it into the
  /// `stageTypeGraphBuilderProvider` via `loadFromGraph`.
  Future<StageTypeGraph> applyTemplate({required String templateId}) async {
    final result = await _rpc(applyRpcName, <String, dynamic>{
      applyTemplateIdParam: templateId,
    });
    final graphMap = (result! as Map).map(
      (key, value) => MapEntry(key as String, value as Object?),
    );
    return StageTypeGraph.fromJson(graphMap);
  }
}

/// Repository provider (mirrors `stageGraphTemplatesRepositoryProvider`).
final stageTypeTemplatesRepositoryProvider =
    Provider<StageTypeTemplatesRepository>(
  (ref) => StageTypeTemplatesRepository(client: Supabase.instance.client),
);

/// The list of stage-type templates visible to the caller as an [AsyncValue]
/// (mirrors `stageGraphTemplatesProvider`). Invalidate to refresh after a save.
final stageTypeTemplatesProvider = FutureProvider<List<StageTypeTemplate>>(
  (ref) async =>
      ref.read(stageTypeTemplatesRepositoryProvider).listTemplates(),
);
