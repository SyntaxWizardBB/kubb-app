import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Visual preview of the kubb arrangement for the finisseur config screen:
/// a row of small field-kubbs above a row of larger base-kubbs separated by
/// a thin pitch line. Pure presentation — no logic.
class KubbStackPreview extends StatelessWidget {
  const KubbStackPreview({
    required this.field,
    required this.base,
    required this.subtitle,
    super.key,
  });

  final int field;
  final int base;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space4,
        vertical: KubbTokens.space4,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(
        children: [
          _Row(count: field, big: false),
          const SizedBox(height: KubbTokens.space2),
          Container(
            height: 2,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: KubbTokens.space6),
            color: tokens.lineStrong,
          ),
          const SizedBox(height: KubbTokens.space2),
          _Row(count: base, big: true),
          const SizedBox(height: KubbTokens.space2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.36,
              color: tokens.fgMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.count, required this.big});

  final int count;
  final bool big;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox(height: 32);
    final w = big ? 18.0 : 14.0;
    final h = big ? 32.0 : 24.0;
    final fill = big ? KubbTokens.wood300 : KubbTokens.wood400;
    final top = big ? KubbTokens.wood500 : KubbTokens.wood600;
    return Wrap(
      spacing: 5,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: List<Widget>.generate(
        count,
        (_) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: fill,
            border: Border(top: BorderSide(color: top, width: 2)),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
