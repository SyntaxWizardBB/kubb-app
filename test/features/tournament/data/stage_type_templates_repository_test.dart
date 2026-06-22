import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart'
    show TemplateVisibility;
import 'package:kubb_app/features/tournament/data/stage_type_templates_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Contract tests for the stage-TYPE templates repository (spec §6/§9.6; T11
/// table `tournament_stage_type_templates`, RPCs `save_stage_type_template` /
/// `apply_stage_type_template`).
///
/// All calls go through the [StageTypeTemplatesRepository.withSeams] test seam
/// (capturing select + RPC), so no live Supabase backend is needed.
void main() {
  // A small valid KO type graph (1 round, 1 field, no edges).
  Map<String, Object?> graphJson(String category) => <String, Object?>{
        'category': category,
        'rounds': <Object?>[
          <String, Object?>{
            'round_number': 1,
            'fields': <Object?>[
              <String, Object?>{
                'id': 'R1F1',
                'round_number': 1,
                'slot': 1,
              },
            ],
            'match_format': <String, Object?>{
              'sets_to_win': 2,
              'max_sets': 3,
              'time_limit_seconds': 1800,
              'tiebreak_enabled': false,
            },
          },
        ],
        'edges': <Object?>[],
      };

  group('stageTypeTemplateFromRow', () {
    test('parses a full jsonb row (type_graph round-trips, category column)',
        () {
      final template = stageTypeTemplateFromRow(<String, dynamic>{
        'id': 't-1',
        'name': 'My KO',
        'description': 'eight-player KO',
        'visibility': 'public',
        'category': 'ko',
        'owner_user_id': 'u-1',
        'type_graph': graphJson('ko'),
      });

      expect(template.id, 't-1');
      expect(template.name, 'My KO');
      expect(template.description, 'eight-player KO');
      expect(template.visibility, TemplateVisibility.public);
      expect(template.category, TypeStageCategory.ko);
      expect(template.isSystem, isFalse);
      expect(template.typeGraph.category, TypeStageCategory.ko);
      expect(template.typeGraph.rounds, hasLength(1));
      expect(template.typeGraph.rounds.single.fields.single.id, 'R1F1');
    });

    test('recovers category from the type_graph body when the column is absent',
        () {
      final template = stageTypeTemplateFromRow(<String, dynamic>{
        'id': 't-2',
        'name': 'Vorrunde',
        'visibility': 'private',
        // category column omitted; recovered from the body
        'owner_user_id': 'u-1',
        'type_graph': graphJson('vorrunde'),
      });
      expect(template.category, TypeStageCategory.vorrunde);
    });

    test('owner_user_id == null => isSystem true; unknown visibility -> private',
        () {
      final system = stageTypeTemplateFromRow(<String, dynamic>{
        'id': 's-1',
        'name': 'Preset',
        'visibility': 'galaxy',
        'owner_user_id': null,
        'type_graph': graphJson('ko'),
      });
      expect(system.isSystem, isTrue);
      expect(system.visibility, TemplateVisibility.private);
    });
  });

  group('listTemplates', () {
    test('selects from the table, maps + sorts (system first, then by name)',
        () async {
      String? capturedTable;
      final repo = StageTypeTemplatesRepository.withSeams(
        select: (table) async {
          capturedTable = table;
          return <dynamic>[
            <String, dynamic>{
              'id': 'u-alpha',
              'name': 'Alpha',
              'visibility': 'private',
              'owner_user_id': 'u-1',
              'type_graph': graphJson('ko'),
            },
            <String, dynamic>{
              'id': 's-zeta',
              'name': 'Zeta',
              'visibility': 'public',
              'owner_user_id': null,
              'type_graph': graphJson('ko'),
            },
            <String, dynamic>{
              'id': 's-beta',
              'name': 'Beta',
              'visibility': 'public',
              'owner_user_id': null,
              'type_graph': graphJson('ko'),
            },
          ];
        },
        rpc: (fn, params) async => null,
      );

      final templates = await repo.listTemplates();

      expect(capturedTable, StageTypeTemplatesRepository.tableName);
      expect(
        templates.map((t) => t.id).toList(),
        <String>['s-beta', 's-zeta', 'u-alpha'],
      );
      expect(templates[0].isSystem, isTrue);
      expect(templates[2].isSystem, isFalse);
    });
  });

  group('saveTemplate', () {
    test('calls save_stage_type_template with the exact params; type_graph '
        'arrives as toJson(); returns the uuid', () async {
      String? capturedFn;
      Map<String, dynamic>? capturedParams;
      final repo = StageTypeTemplatesRepository.withSeams(
        select: (table) async => const <dynamic>[],
        rpc: (fn, params) async {
          capturedFn = fn;
          capturedParams = params;
          return 'new-id';
        },
      );

      final graph = StageTypeGraph.fromJson(graphJson('ko'));
      final id = await repo.saveTemplate(
        name: 'My template',
        description: 'desc',
        visibility: TemplateVisibility.club,
        typeGraph: graph,
        organizerTeamId: 'team-1',
      );

      expect(id, 'new-id');
      expect(capturedFn, StageTypeTemplatesRepository.saveRpcName);
      expect(
        capturedParams![StageTypeTemplatesRepository.saveNameParam],
        'My template',
      );
      expect(
        capturedParams![StageTypeTemplatesRepository.saveVisibilityParam],
        'club',
      );
      expect(
        capturedParams![StageTypeTemplatesRepository.saveOrganizerTeamIdParam],
        'team-1',
      );
      // template_id defaults to null on a fresh save.
      expect(
        capturedParams![StageTypeTemplatesRepository.saveTemplateIdParam],
        isNull,
      );
      final graphParam =
          capturedParams![StageTypeTemplatesRepository.saveTypeGraphParam];
      expect(graphParam, isA<Map<String, Object?>>());
      expect(graphParam, graph.toJson());
    });

    test('forwards a template_id for the overwrite path', () async {
      Map<String, dynamic>? capturedParams;
      final repo = StageTypeTemplatesRepository.withSeams(
        select: (table) async => const <dynamic>[],
        rpc: (fn, params) async {
          capturedParams = params;
          return 'same-id';
        },
      );

      await repo.saveTemplate(
        name: 'Overwrite',
        visibility: TemplateVisibility.private,
        typeGraph: StageTypeGraph.fromJson(graphJson('ko')),
        templateId: 'same-id',
      );

      expect(
        capturedParams![StageTypeTemplatesRepository.saveTemplateIdParam],
        'same-id',
      );
    });
  });

  group('applyTemplate', () {
    test('calls apply_stage_type_template; decodes the returned type_graph '
        'jsonb back into a StageTypeGraph (round-trip)', () async {
      String? capturedFn;
      Map<String, dynamic>? capturedParams;
      final repo = StageTypeTemplatesRepository.withSeams(
        select: (table) async => const <dynamic>[],
        rpc: (fn, params) async {
          capturedFn = fn;
          capturedParams = params;
          // The apply RPC returns the raw type_graph jsonb (already-decoded map).
          return graphJson('vorrunde');
        },
      );

      final graph = await repo.applyTemplate(templateId: 'tpl-1');

      expect(capturedFn, StageTypeTemplatesRepository.applyRpcName);
      expect(
        capturedParams![StageTypeTemplatesRepository.applyTemplateIdParam],
        'tpl-1',
      );
      expect(graph.category, TypeStageCategory.vorrunde);
      expect(graph.rounds, hasLength(1));
      // Full round-trip: re-serializing equals the wire form returned.
      expect(graph.toJson(), StageTypeGraph.fromJson(graphJson('vorrunde')).toJson());
    });
  });

  group('constants', () {
    test('table / RPC names + param keys match the T11 contract', () {
      expect(
        StageTypeTemplatesRepository.tableName,
        'tournament_stage_type_templates',
      );
      expect(
        StageTypeTemplatesRepository.saveRpcName,
        'save_stage_type_template',
      );
      expect(
        StageTypeTemplatesRepository.applyRpcName,
        'apply_stage_type_template',
      );
      expect(StageTypeTemplatesRepository.saveNameParam, 'name');
      expect(StageTypeTemplatesRepository.saveDescriptionParam, 'description');
      expect(StageTypeTemplatesRepository.saveVisibilityParam, 'visibility');
      expect(StageTypeTemplatesRepository.saveTypeGraphParam, 'type_graph');
      expect(
        StageTypeTemplatesRepository.saveOrganizerTeamIdParam,
        'organizer_team_id',
      );
      expect(StageTypeTemplatesRepository.saveTemplateIdParam, 'template_id');
      expect(StageTypeTemplatesRepository.applyTemplateIdParam, 'template_id');
    });
  });
}
