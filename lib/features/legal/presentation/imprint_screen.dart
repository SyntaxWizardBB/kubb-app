import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/legal/data/legal_text_loader.dart';
import 'package:kubb_app/features/legal/presentation/widgets/legal_markdown_body.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Statischer Reader fuer `docs/legal/imprint-de.md`.
///
/// Spiegelbild des Privacy-Policy-Screens: gleicher Loader-Override-Hook,
/// gleicher Fallback bei Asset-Fehlern, gleicher Markdown-Renderer
/// ([LegalMarkdownBody]).
class ImprintScreen extends StatelessWidget {
  const ImprintScreen({super.key});

  /// Loader-Indirektion fuer Tests (Fake-Asset).
  static Future<String> Function() loaderOverride = loadImprintDe;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.legalEyebrow,
        title: l.legalImprintTitle,
      ),
      body: FutureBuilder<String>(
        future: loaderOverride(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _StatusText(text: l.legalImprintLoading);
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _StatusText(text: l.legalImprintUnavailable);
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space8,
            ),
            child: LegalMarkdownBody(source: snapshot.data!),
          );
        },
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.all(KubbTokens.space5),
      child: Text(text, style: TextStyle(color: tokens.fgMuted)),
    );
  }
}
