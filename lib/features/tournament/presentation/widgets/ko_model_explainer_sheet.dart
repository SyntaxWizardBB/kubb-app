import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_sheet.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// In-app explainer modal for the three KO models (Single-Out /
/// Double-Elimination / Trostturnier). The copy is the verbatim template from
/// `docs/P6_KO_MODELS.md` (section "Modal-Text"), surfaced via l10n keys.
///
/// Re-uses the shared [KubbBottomSheet] / [showKubbBottomSheet] app pattern so
/// the dismiss handle, padding and raised background match every other sheet.
class KoModelExplainerSheet extends StatelessWidget {
  const KoModelExplainerSheet({super.key});

  /// Opens the explainer using the shared bottom-sheet builder.
  static Future<void> show(BuildContext context) => showKubbBottomSheet<void>(
        context,
        builder: (_) => const KoModelExplainerSheet(),
        header: const _Header(),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Keep the (potentially long) body scrollable on small screens.
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: KubbTokens.space2),
            _Model(
              heading: l10n.tournamentKoModelExplainerSingleOutHeading,
              body: l10n.tournamentKoModelExplainerSingleOutBody,
            ),
            const SizedBox(height: KubbTokens.space5),
            _Model(
              heading: l10n.tournamentKoModelExplainerDoubleElimHeading,
              body: l10n.tournamentKoModelExplainerDoubleElimBody,
            ),
            const SizedBox(height: KubbTokens.space5),
            _Model(
              heading: l10n.tournamentKoModelExplainerTrostturnierHeading,
              body: l10n.tournamentKoModelExplainerTrostturnierBody,
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal header (eyebrow-less title) following the [KubbBottomSheet] header
/// slot convention used by the other app sheets.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space1),
      child: Text(
        l10n.tournamentKoModelExplainerTitle,
        style: t.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.44,
          color: tokens.fg,
        ),
      ),
    );
  }
}

/// One KO-model block: bold heading + explanation paragraph.
class _Model extends StatelessWidget {
  const _Model({required this.heading, required this.body});

  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: t.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: tokens.fg,
          ),
        ),
        const SizedBox(height: KubbTokens.space1),
        Text(
          body,
          style: t.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.45,
            color: tokens.fgMuted,
          ),
        ),
      ],
    );
  }
}
