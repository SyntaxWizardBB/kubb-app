import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Result payload of [SaveTemplateDialog].
class SaveTemplateResult {
  const SaveTemplateResult({
    required this.name,
    required this.visibility,
  });

  final String name;
  final TemplateVisibility visibility;
}

/// Save-as-template dialog shared by the standalone stage-graph editor and the
/// tournament-setup wizard. Asks for a name and a visibility scope and pops a
/// [SaveTemplateResult]; the caller maps that onto `saveTemplate`.
///
/// The visibility labels spell the scopes out (private = "nur ich", club =
/// "Verein/Organisation") so the organizer-team scope is never mistaken for a
/// personal one. When [clubAvailable] is false the club option is disabled and
/// hint-labelled — a club-scoped template needs an organizing club on the
/// draft, and there is none.
class SaveTemplateDialog extends StatefulWidget {
  const SaveTemplateDialog({super.key, this.clubAvailable = true});

  /// Whether a `club`-scoped save is possible (the draft carries a club id).
  /// When false the club option is shown disabled with an explanatory hint.
  final bool clubAvailable;

  @override
  State<SaveTemplateDialog> createState() => _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends State<SaveTemplateDialog> {
  final _nameController = TextEditingController();
  late TemplateVisibility _visibility = TemplateVisibility.private;
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final l = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = l.stageGraphErrorNameEmpty);
      return;
    }
    Navigator.of(context).pop(
      SaveTemplateResult(name: name, visibility: _visibility),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.stageGraphTemplateSave),
      content: SizedBox(
        width: saveTemplateDialogWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('stageGraphTemplateNameField'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l.stageGraphSaveTemplateName,
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: KubbTokens.space3),
            DropdownButtonFormField<TemplateVisibility>(
              key: const Key('stageGraphTemplateVisibilityField'),
              initialValue: _visibility,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.stageGraphSaveTemplateVisibility,
                helperText: widget.clubAvailable
                    ? null
                    : l.stageGraphSaveTemplateClubUnavailable,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final v in TemplateVisibility.values)
                  DropdownMenuItem<TemplateVisibility>(
                    value: v,
                    enabled:
                        v != TemplateVisibility.club || widget.clubAvailable,
                    child: Text(templateVisibilityLabel(l, v)),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                if (v == TemplateVisibility.club && !widget.clubAvailable) {
                  return;
                }
                setState(() => _visibility = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.stageGraphCancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(l.stageGraphConfirm),
        ),
      ],
    );
  }
}

/// Localized, spelled-out label for a [TemplateVisibility]. Shared so the editor
/// and the wizard render the same wording.
String templateVisibilityLabel(AppLocalizations l, TemplateVisibility v) {
  switch (v) {
    case TemplateVisibility.private:
      return l.stageGraphVisibilityPrivate;
    case TemplateVisibility.club:
      return l.stageGraphVisibilityClub;
    case TemplateVisibility.public:
      return l.stageGraphVisibilityPublic;
  }
}

/// Responsive content width for the save dialog. Mirrors the node/edge dialog
/// sizing: caps at a roomy 360 but shrinks on a phone so the fixed-width content
/// never exceeds the AlertDialog's own insets.
double saveTemplateDialogWidth(BuildContext context) {
  final available = MediaQuery.sizeOf(context).width - 128;
  return available.clamp(220.0, 360.0);
}
