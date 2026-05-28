import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/legal/data/legal_text_loader.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Statischer Reader fuer `docs/legal/privacy-policy-de.md`.
///
/// Eigener Mini-Renderer statt `flutter_markdown` (bewusste Stack-
/// Entscheidung im Sprint-C-Briefing): Absatz-Split auf Leerzeile,
/// Heading-Detection ueber `# ` / `## `-Prefix, alles andere als
/// Fliesstext. Liste/Tabellen werden hier nicht gebraucht — das Skelett
/// hat nur Headings + Absaetze + zwei Blockquote-Eskalationen.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  /// Loader-Indirektion fuer Tests (Fake-Asset).
  static Future<String> Function() loaderOverride = loadPrivacyPolicyDe;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.legalEyebrow,
        title: l.legalPrivacyPolicyTitle,
      ),
      body: FutureBuilder<String>(
        future: loaderOverride(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _StatusText(text: l.legalPrivacyPolicyLoading);
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _StatusText(text: l.legalPrivacyPolicyUnavailable);
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space8,
            ),
            child: _MarkdownBody(source: snapshot.data!),
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

/// Minimaler Markdown-Renderer (Headings + Absaetze + Quote-Block).
///
/// Absatz-Grenze ist die Leerzeile (`\n\n`). Jeder Block beginnt mit `# `
/// oder `## ` (Heading 1/2), `> ` (Owner-Eskalation-Quote) oder ist
/// Fliesstext.
class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final theme = Theme.of(context).textTheme;
    final blocks = source.split(RegExp(r'\n\s*\n'));
    final children = <Widget>[];
    for (final raw in blocks) {
      final block = raw.trim();
      if (block.isEmpty) continue;
      if (block.startsWith('# ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: KubbTokens.space3),
          child: Text(block.substring(2),
              style: theme.titleLarge?.copyWith(color: tokens.fg)),
        ));
      } else if (block.startsWith('## ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(
              top: KubbTokens.space4, bottom: KubbTokens.space2),
          child: Text(block.substring(3),
              style: theme.titleMedium?.copyWith(color: tokens.fg)),
        ));
      } else if (block.startsWith('> ')) {
        children.add(_QuoteBlock(
            text: block
                .split('\n')
                .map((l) => l.startsWith('> ') ? l.substring(2) : l)
                .join(' ')));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: KubbTokens.space2),
          child: Text(block.replaceAll('\n', ' '),
              style: theme.bodyMedium?.copyWith(color: tokens.fg)),
        ));
      }
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      margin: const EdgeInsets.only(bottom: KubbTokens.space3),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border(left: BorderSide(color: tokens.accent, width: 3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: tokens.fgMuted, fontStyle: FontStyle.italic),
      ),
    );
  }
}
