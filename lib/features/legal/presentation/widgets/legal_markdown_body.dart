import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Minimaler Markdown-Renderer fuer die statischen Rechtstexte
/// (Privacy, Impressum).
///
/// Bewusste Stack-Entscheidung im Sprint-C-Briefing: kein
/// `flutter_markdown`. Absatz-Grenze ist die Leerzeile (`\n\n`).
/// Jeder Block beginnt mit `# ` oder `## ` (Heading 1/2), `> ` (Owner-
/// Eskalation-Quote) oder ist Fliesstext. Listen/Tabellen werden bewusst
/// nicht unterstuetzt — die Asset-Skelette nutzen sie nicht.
class LegalMarkdownBody extends StatelessWidget {
  const LegalMarkdownBody({required this.source, super.key});

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
