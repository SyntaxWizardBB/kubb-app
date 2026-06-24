import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart'
    show stageTypeGraphConfigKey;
import 'package:kubb_app/features/tournament/presentation/stage_type_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Wizard host for the Ebene-2 stage-TYPE editor ("Stufen-Typ modellieren",
/// spec §3/§9.1). It mounts the shared [StageTypeGraphBuilderBody] (the same
/// editor the standalone screen renders, reading/mutating only
/// `stageTypeGraphBuilderProvider`) and turns its save into a `StageNode`
/// mutation: the builder's `toConfig()` carries one key
/// ([stageTypeGraphConfigKey]), which is merged into [stage]'s config so the
/// stage's existing keys survive. The updated node is handed back via [onSaved].
///
/// This is the write path the spec's parity check relies on: whichever editor
/// (form or canvas) made the edit, the persisted config round-trips through
/// `StageTypeGraph.toJson` / `fromJson` (ADR-0039 §6.5 / §9.5).
class StageTypeGraphWizardHost extends StatelessWidget {
  const StageTypeGraphWizardHost({
    required this.stage,
    required this.onSaved,
    super.key,
  });

  /// The stage node whose `config['type_graph']` is being authored.
  final StageNode stage;

  /// Called with the stage node carrying the freshly serialized type graph.
  final ValueChanged<StageNode> onSaved;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KubbTokens.space4,
            KubbTokens.space4,
            KubbTokens.space4,
            0,
          ),
          child: Text(
            l.stageTypeGraphTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: tokens.fg,
            ),
          ),
        ),
        Expanded(
          child: StageTypeGraphBuilderBody(
            onSave: (config) => onSaved(_merge(stage, config)),
          ),
        ),
      ],
    );
  }

  /// Merges the builder's serialized config (one key, [stageTypeGraphConfigKey])
  /// into [node]'s config, keeping every other key intact.
  static StageNode _merge(StageNode node, Map<String, Object?> config) {
    return StageNode(
      id: node.id,
      type: node.type,
      seeding: node.seeding,
      config: <String, Object?>{
        ...node.config,
        ...config,
      },
    );
  }
}
