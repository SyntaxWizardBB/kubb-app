import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

class KubbBottomSheet extends StatelessWidget {
  const KubbBottomSheet({
    required this.child,
    super.key,
    this.header,
  });

  final Widget? header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KubbTokens.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(18, 10, 18, 32 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: tokens.line,
                  borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
                ),
              ),
            ),
            ?header,
            child,
          ],
        ),
      ),
    );
  }
}

Future<T?> showKubbBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Widget? header,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => KubbBottomSheet(header: header, child: builder(ctx)),
  );
}
