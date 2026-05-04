import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_app_bar.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_primary_button.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Profile edit screen per design brief #12 (M5-T15, template
/// `EditProfileScreen.jsx`). Replaces the F2 inline edit-mode in
/// profile_screen as part of the auth-flow refactor.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

const List<Color> _avatarPalette = [
  Color(0xFF3A7C2E),
  Color(0xFFC08A33),
  Color(0xFF8A1F3D),
  Color(0xFF234E1C),
  Color(0xFF1C4F7A),
  Color(0xFF5B3A7C),
  Color(0xFF7A3A3A),
  Color(0xFF0C0B07),
];

String _toHex(Color c) =>
    '#${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final String _initialNick;
  late final String _initialColor;
  late final TextEditingController _nickController;
  late String _color;

  bool _saving = false;
  bool _hasError = false;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(displayProfileProvider);
    _initialNick = profile?.displayName ?? '';
    _initialColor = profile?.avatarColor ?? _toHex(_avatarPalette.first);
    _color = _initialColor;
    _nickController = TextEditingController(text: _initialNick)
      ..addListener(_onNickChanged);
  }

  @override
  void dispose() {
    _nickController
      ..removeListener(_onNickChanged)
      ..dispose();
    super.dispose();
  }

  void _onNickChanged() {
    // Re-render so save-button enabled-state and avatar initial track
    // the live text. The controller is the source of truth — we just
    // need to invalidate the frame.
    setState(() {});
  }

  String get _nick => _nickController.text;

  void _back() {
    GoRouter.of(context).pop();
  }

  bool get _validNickname =>
      _nick.length >= 3 &&
      _nick.length <= 30 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(_nick);

  bool get _dirty => _nick != _initialNick || _color != _initialColor;
  bool get _canSave => _dirty && _validNickname && !_saving;

  Future<void> _save() async {
    final profile = ref.read(displayProfileProvider);
    if (profile == null) return;
    setState(() {
      _saving = true;
      _hasError = false;
      _success = false;
    });
    final session = ref.read(authControllerProvider).maybeWhen(
          data: (s) => s,
          orElse: () => const AuthSession.signedOut(),
        );
    if (!session.isAuthenticated) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _hasError = true;
      });
      return;
    }
    try {
      await ref.read(cloudProfileRepositoryProvider).updateProfile(
            userId: profile.userId,
            nickname: _nick,
            avatarColor: _color,
          );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _success = true;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final initialChar = _nick.isEmpty ? 'A' : _nick[0].toUpperCase();
    final hexToColor = int.parse(_color.replaceFirst('#', 'ff'), radix: 16);
    final avatarColor = Color(hexToColor);

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space6),
          child: Column(
            children: [
              AuthAppBar(
                eyebrow: l10n.authEditProfileEyebrow,
                title: l10n.authEditProfileTitle,
                onBack: _back,
              ),
              const SizedBox(height: KubbTokens.space5),
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: avatarColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initialChar,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: KubbTokens.space3),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final c in _avatarPalette)
                    _ColorDot(
                      color: c,
                      selected: _color == _toHex(c),
                      onTap: () => setState(() => _color = _toHex(c)),
                    ),
                ],
              ),
              const SizedBox(height: KubbTokens.space4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.authEditProfileNicknameLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.fgMuted,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nickController,
                maxLength: 30,
                decoration: InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(KubbTokens.radiusMd),
                    borderSide:
                        BorderSide(color: tokens.lineStrong, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(KubbTokens.radiusMd),
                    borderSide:
                        BorderSide(color: tokens.lineStrong, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.authEditProfileNicknameHelper,
                  style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                ),
              ),
              if (_hasError) ...[
                const SizedBox(height: KubbTokens.space3),
                _Banner(
                  tone: _BannerTone.error,
                  message: l10n.authEditProfileError,
                ),
              ],
              if (_success) ...[
                const SizedBox(height: KubbTokens.space3),
                _Banner(
                  tone: _BannerTone.info,
                  message: l10n.authEditProfileSuccess,
                ),
              ],
              const Spacer(),
              AuthPrimaryButton(
                label: _saving
                    ? l10n.authEditProfileSubmitting
                    : l10n.authEditProfileSubmit,
                onPressed: _canSave ? _save : null,
                loading: _saving,
              ),
              const SizedBox(height: KubbTokens.space5),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: KubbTokens.stone900, width: 3)
                : null,
          ),
        ),
      ),
    );
  }
}

enum _BannerTone { info, error }

class _Banner extends StatelessWidget {
  const _Banner({required this.tone, required this.message});

  final _BannerTone tone;
  final String message;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, icon) = switch (tone) {
      _BannerTone.error => (
          const Color(0xFFFBE4E0),
          KubbTokens.miss,
          KubbTokens.miss,
          Icons.error_outline,
        ),
      _BannerTone.info => (
          KubbTokens.meadow100,
          KubbTokens.meadow600,
          KubbTokens.meadow800,
          Icons.check_circle_outline,
        ),
    };
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 1.5),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
