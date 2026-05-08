import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/data/match_config_draft.dart';
import 'package:kubb_app/features/social/application/social_providers.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Bottom-sheet picker used by the match config wizard to add a
/// participant slot to one of the teams.
///
/// Pulls from `acceptedFriendsProvider` so only real friends can be
/// picked. Each row resolves to a [FriendSlot].
///
/// Returns the selected [FriendSlot] via Navigator.pop or `null` when
/// the user dismisses the sheet without choosing anything.
class ParticipantPickerSheet extends ConsumerStatefulWidget {
  const ParticipantPickerSheet({super.key});

  static Future<FriendSlot?> show(BuildContext context) {
    return showModalBottomSheet<FriendSlot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ParticipantPickerSheet(),
    );
  }

  @override
  ConsumerState<ParticipantPickerSheet> createState() =>
      _ParticipantPickerSheetState();
}

class _ParticipantPickerSheetState
    extends ConsumerState<ParticipantPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final friends = ref.watch(acceptedFriendsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KubbTokens.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(0, 10, 0, bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KubbTokens.space4,
                vertical: KubbTokens.space2,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Freunde',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 360,
              child: friends.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(KubbTokens.space5),
                        child: Text(
                          'Du hast noch keine Freunde.\n'
                          'Füge zuerst welche hinzu, um sie zu einem Match einzuladen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.fgMuted,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(KubbTokens.space3),
                      itemCount: friends.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: KubbTokens.space2),
                      itemBuilder: (context, i) {
                        final f = friends[i];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(KubbTokens.radiusMd),
                            side: BorderSide(color: tokens.line),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: KubbTokens.meadow600,
                            child: Text(
                              f.nickname.isEmpty
                                  ? '?'
                                  : f.nickname.characters.first.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            f.nickname,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          trailing: const Icon(LucideIcons.plus, size: 18),
                          onTap: () => Navigator.of(context).pop<FriendSlot>(
                            FriendSlot(
                              userId: f.userId,
                              nickname: f.nickname,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
