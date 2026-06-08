import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Contract tests for the stage-graph templates repository (ADR-0030
/// §Templates; L3a table `tournament_stage_graph_templates`, RPCs
/// `save_stage_graph_template` / `apply_stage_graph_template`).
///
/// All calls go through the [StageGraphTemplatesRepository.withSeams] test seam
/// (capturing select + RPC), so no live Supabase backend is needed.
void main() {
  // A small valid 2-stage graph (pool -> single_elim) used across tests.
  Map<String, Object?> graphJson() => <String, Object?>{
        'nodes': <Object?>[
          <String, Object?>{
            'id': 'pool',
            'type': 'pool',
            'seeding': 'from_elo',
            'config': <String, Object?>{'groupCount': 1},
          },
          <String, Object?>{
            'id': 'ko',
            'type': 'single_elim',
            'seeding': 'as_routed',
            'config': <String, Object?>{},
          },
        ],
        'edges': <Object?>[
          <String, Object?>{
            'from_node_id': 'pool',
            'to_node_id': 'ko',
            'selector': <String, Object?>{'kind': 'top_k', 'k': 4},
            'seeding_in': 'order_preserving',
          },
        ],
      };

  group('templateFromRow', () {
    test('parses a full jsonb row into a StageGraphTemplate (graph round-trips)',
        () {
      final template = templateFromRow(<String, dynamic>{
        'id': 't-1',
        'name': 'Pool then KO',
        'description': 'A pool feeding a single-elim bracket',
        'visibility': 'public',
        'owner_user_id': 'u-1',
        'graph': graphJson(),
      });

      expect(template.id, 't-1');
      expect(template.name, 'Pool then KO');
      expect(template.description, 'A pool feeding a single-elim bracket');
      expect(template.visibility, TemplateVisibility.public);
      expect(template.isSystem, isFalse);

      // Graph parsed via StageGraph.fromJson: nodes, edges + selector kind.
      expect(template.graph.nodes, hasLength(2));
      expect(template.graph.nodes.first.id, 'pool');
      expect(template.graph.nodes.first.type, StageNodeType.pool);
      expect(template.graph.nodes[1].type, StageNodeType.singleElim);
      expect(template.graph.edges, hasLength(1));
      final selector = template.graph.edges.single.selector;
      expect(selector, isA<TopK>());
      expect((selector as TopK).k, 4);
    });

    test('owner_user_id == null => isSystem true; set owner => false', () {
      final system = templateFromRow(<String, dynamic>{
        'id': 's-1',
        'name': 'Preset',
        'visibility': 'public',
        'owner_user_id': null,
        'graph': graphJson(),
      });
      expect(system.isSystem, isTrue);

      final owned = templateFromRow(<String, dynamic>{
        'id': 'o-1',
        'name': 'Mine',
        'visibility': 'private',
        'owner_user_id': 'u-9',
        'graph': graphJson(),
      });
      expect(owned.isSystem, isFalse);
    });

    test('is null-/type-robust: missing description -> null, unknown visibility '
        '-> private default, no throw', () {
      final template = templateFromRow(<String, dynamic>{
        'id': 't-2',
        'name': 'Sparse',
        // description omitted entirely
        'visibility': 'galaxy', // unknown wire value
        'owner_user_id': null,
        'graph': graphJson(),
      });

      expect(template.description, isNull);
      expect(template.visibility, TemplateVisibility.private);
      expect(template.isSystem, isTrue);
    });
  });

  group('listTemplates', () {
    test('selects from the templates table, maps + sorts deterministically',
        () async {
      String? capturedTable;
      final repo = StageGraphTemplatesRepository.withSeams(
        select: (table) async {
          capturedTable = table;
          // Intentionally unsorted mixed input: non-system "Alpha" before a
          // system "Zeta", plus two systems out of name order.
          return <dynamic>[
            <String, dynamic>{
              'id': 'u-alpha',
              'name': 'Alpha',
              'visibility': 'private',
              'owner_user_id': 'u-1',
              'graph': graphJson(),
            },
            <String, dynamic>{
              'id': 's-zeta',
              'name': 'Zeta',
              'visibility': 'public',
              'owner_user_id': null,
              'graph': graphJson(),
            },
            <String, dynamic>{
              'id': 's-beta',
              'name': 'Beta',
              'visibility': 'public',
              'owner_user_id': null,
              'graph': graphJson(),
            },
          ];
        },
        rpc: (fn, params) async => null,
      );

      final templates = await repo.listTemplates();

      expect(capturedTable, StageGraphTemplatesRepository.tableName);
      // System presets first (Beta, Zeta — name-ordered), then the user one.
      expect(
        templates.map((t) => t.id).toList(),
        <String>['s-beta', 's-zeta', 'u-alpha'],
      );
      expect(templates[0].isSystem, isTrue);
      expect(templates[1].isSystem, isTrue);
      expect(templates[2].isSystem, isFalse);
    });
  });

  group('saveTemplate', () {
    test('calls save_stage_graph_template with the exact params; graph arrives '
        'as toJson(); returns the uuid', () async {
      String? capturedFn;
      Map<String, dynamic>? capturedParams;
      final repo = StageGraphTemplatesRepository.withSeams(
        select: (table) async => const <dynamic>[],
        rpc: (fn, params) async {
          capturedFn = fn;
          capturedParams = params;
          return 'new-id';
        },
      );

      final graph = StageGraph.fromJson(graphJson());
      final id = await repo.saveTemplate(
        name: 'My template',
        description: 'desc',
        visibility: TemplateVisibility.club,
        graph: graph,
        clubId: 'club-1',
      );

      expect(id, 'new-id');
      expect(capturedFn, StageGraphTemplatesRepository.saveRpcName);
      expect(capturedParams, isNotNull);
      expect(
        capturedParams![StageGraphTemplatesRepository.saveNameParam],
        'My template',
      );
      expect(
        capturedParams![StageGraphTemplatesRepository.saveDescriptionParam],
        'desc',
      );
      expect(
        capturedParams![StageGraphTemplatesRepository.saveVisibilityParam],
        'club',
      );
      expect(
        capturedParams![StageGraphTemplatesRepository.saveClubIdParam],
        'club-1',
      );
      // graph is the serialized map, not the Dart object.
      final graphParam =
          capturedParams![StageGraphTemplatesRepository.saveGraphParam];
      expect(graphParam, isA<Map<String, Object?>>());
      expect(graphParam, graph.toJson());
    });
  });

  group('applyTemplate', () {
    test('calls apply_stage_graph_template with tournament_id/template_id; '
        'returns the int count (num-robust)', () async {
      String? capturedFn;
      Map<String, dynamic>? capturedParams;
      final repo = StageGraphTemplatesRepository.withSeams(
        select: (table) async => const <dynamic>[],
        rpc: (fn, params) async {
          capturedFn = fn;
          capturedParams = params;
          // PostgREST scalar can arrive as a plain num.
          return 7;
        },
      );

      final count = await repo.applyTemplate(
        tournamentId: 'trn-1',
        templateId: 'tpl-1',
      );

      expect(count, 7);
      expect(capturedFn, StageGraphTemplatesRepository.applyRpcName);
      expect(
        capturedParams![StageGraphTemplatesRepository.applyTournamentIdParam],
        'trn-1',
      );
      expect(
        capturedParams![StageGraphTemplatesRepository.applyTemplateIdParam],
        'tpl-1',
      );
    });
  });

  group('constants', () {
    test('table / RPC names + param keys match the L3a contract', () {
      expect(
        StageGraphTemplatesRepository.tableName,
        'tournament_stage_graph_templates',
      );
      expect(
        StageGraphTemplatesRepository.saveRpcName,
        'save_stage_graph_template',
      );
      expect(
        StageGraphTemplatesRepository.applyRpcName,
        'apply_stage_graph_template',
      );
      expect(StageGraphTemplatesRepository.saveNameParam, 'name');
      expect(StageGraphTemplatesRepository.saveDescriptionParam, 'description');
      expect(StageGraphTemplatesRepository.saveVisibilityParam, 'visibility');
      expect(StageGraphTemplatesRepository.saveGraphParam, 'graph');
      expect(StageGraphTemplatesRepository.saveClubIdParam, 'club_id');
      expect(
        StageGraphTemplatesRepository.applyTournamentIdParam,
        'tournament_id',
      );
      expect(StageGraphTemplatesRepository.applyTemplateIdParam, 'template_id');
    });
  });
}
