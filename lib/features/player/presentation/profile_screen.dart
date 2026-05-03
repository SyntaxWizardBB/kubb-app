import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/avatar_circle.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/player/presentation/avatar_color.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:logging/logging.dart';

final _log = Logger('ProfileScreen');

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  Color? _pickedColor;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _enterEdit(Player player) {
    setState(() {
      _editing = true;
      _nameController.text = player.name;
      _pickedColor = AvatarColorHelper.resolve(
        player.avatarColor,
        seed: player.id,
      );
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _saving = false;
      _nameController.clear();
      _pickedColor = null;
    });
  }

  Future<void> _save(Player player) async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(playerRepositoryProvider).update(
            id: player.id,
            name: name,
            avatarColor: _pickedColor == null
                ? null
                : AvatarColorHelper.encode(_pickedColor!),
          );
      if (!mounted) return;
      _cancelEdit();
    } on Object catch (e, st) {
      _log.warning('failed to update profile', e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.profileUpdateError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        foregroundColor: tokens.fg,
        elevation: 0,
        title: Text(l.profileTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: SafeArea(
        child: profile.when(
          data: (player) => player == null
              ? const Center(child: Text('Kein Profil'))
              : _body(context, player, tokens, l),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(e.toString())),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    Player player,
    KubbTokens tokens,
    AppLocalizations l,
  ) {
    final color = _editing
        ? (_pickedColor ?? AvatarColorHelper.defaultColorFor(player.id))
        : AvatarColorHelper.resolve(player.avatarColor, seed: player.id);
    final initials = AvatarColorHelper.initialsFor(
      _editing ? _nameController.text : player.name,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space6,
        vertical: KubbTokens.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AvatarCircle(initials: initials, color: color)),
          const SizedBox(height: KubbTokens.space6),
          if (_editing)
            _editForm(player, tokens, l)
          else
            _readView(player, tokens, l),
        ],
      ),
    );
  }

  Widget _readView(Player player, KubbTokens tokens, AppLocalizations l) {
    final textTheme = Theme.of(context).textTheme;
    final since = DateFormat.yMMMMd('de').format(player.createdAt.toLocal());
    final labelStyle = textTheme.labelSmall?.copyWith(color: tokens.fgMuted);
    final valueStyle = textTheme.bodyLarge?.copyWith(color: tokens.fg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(player.name,
            style: textTheme.displaySmall?.copyWith(color: tokens.fg)),
        const SizedBox(height: KubbTokens.space6),
        Text(l.profileSinceLabel, style: labelStyle),
        const SizedBox(height: KubbTokens.space1),
        Text(since, style: valueStyle),
        const SizedBox(height: KubbTokens.space4),
        Text(l.profileDeviceLabel, style: labelStyle),
        const SizedBox(height: KubbTokens.space1),
        Text(
          player.deviceId,
          style: GoogleFonts.jetBrainsMono(fontSize: 12, color: tokens.fgMuted),
        ),
        const SizedBox(height: KubbTokens.space8),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: OutlinedButton(
            onPressed: () => _enterEdit(player),
            child: Text(l.profileEditButton),
          ),
        ),
      ],
    );
  }

  Widget _editForm(Player player, KubbTokens tokens, AppLocalizations l) {
    final canSave = _nameController.text.trim().isNotEmpty && !_saving;
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall?.copyWith(color: tokens.fgMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.profileNameLabel, style: labelStyle),
        const SizedBox(height: KubbTokens.space2),
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: KubbTokens.space4),
        Text(l.profileColorLabel, style: labelStyle),
        const SizedBox(height: KubbTokens.space2),
        Wrap(
          spacing: KubbTokens.space3,
          runSpacing: KubbTokens.space3,
          children: AvatarColorHelper.palette
              .map((c) => _ColorChip(
                    color: c,
                    selected: _pickedColor == c,
                    onTap: () => setState(() => _pickedColor = c),
                  ))
              .toList(),
        ),
        const SizedBox(height: KubbTokens.space8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: KubbTokens.touchComfortable,
                child: OutlinedButton(
                  onPressed: _saving ? null : _cancelEdit,
                  child: Text(l.profileCancelButton),
                ),
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: SizedBox(
                height: KubbTokens.touchComfortable,
                child: FilledButton(
                  onPressed: canSave ? () => _save(player) : null,
                  child: Text(l.profileSaveButton),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: KubbTokens.touchMin,
        height: KubbTokens.touchMin,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? tokens.lineStrong : tokens.line,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
