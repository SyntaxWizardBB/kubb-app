import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/inbox/application/inbox_controller.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// AppBar-Trailing-Action: Bell-Icon + Unread-Badge fuer die Inbox.
///
/// Wiederverwendbar: kann sowohl in `KubbAppBar` (single `actions`-Slot)
/// als auch in Material `AppBar` (`actions: [...]`) eingehaengt werden.
///
/// Watched [inboxUnreadCountProvider] und blendet rechts oben einen
/// kleinen roten Badge ein, solange unread > 0. Bei unread > 9 wird
/// "9+" angezeigt. Tap navigiert auf [AuthRoutes.inbox].
///
/// Schliesst R20-F-14 / R20-A-05 (Toter-Brief-Pattern fuer
/// `inboxUnreadCountProvider`).
class InboxBellAction extends ConsumerWidget {
  const InboxBellAction({super.key, this.tooltip});

  /// Optionales Tooltip-Override. Default ist 'Postfach'.
  final String? tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final unread = ref.watch(inboxUnreadCountProvider);

    return SizedBox(
      width: KubbTokens.touchMin,
      height: KubbTokens.touchMin,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip ?? 'Postfach',
            icon: const KubbIcon(LucideIcons.bell),
            iconSize: 24,
            splashRadius: 24,
            constraints: const BoxConstraints.tightFor(
              width: KubbTokens.touchMin,
              height: KubbTokens.touchMin,
            ),
            onPressed: () => context.push(AuthRoutes.inbox),
          ),
          if (unread > 0)
            Positioned(
              top: 6,
              right: 4,
              child: IgnorePointer(
                child: _UnreadBadge(
                  count: unread,
                  borderColor: tokens.bg,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, required this.borderColor});

  final int count;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: KubbTokens.miss,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.1,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
