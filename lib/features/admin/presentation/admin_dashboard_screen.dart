import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/admin/application/admin_providers.dart';
import 'package:kubb_app/features/admin/data/admin_models.dart';

/// Admin dashboard (M1): searchable user list. Tapping a row opens the
/// per-user actions. Visibility is gated by the drawer (isAdminProvider);
/// every action re-checks caller_is_admin() server-side.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final usersAsync = ref.watch(adminUserListProvider(_query));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(eyebrow: 'Verwaltung', title: 'Admin'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Nach Name suchen …',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: tokens.bgRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(KubbTokens.space5),
                  child: Text('Fehler: $e',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: KubbTokens.miss)),
                ),
              ),
              data: (users) {
                if (users.isEmpty) {
                  return Center(
                    child: Text('Keine Nutzer gefunden.',
                        style: TextStyle(color: tokens.fgMuted)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(KubbTokens.space4, 0,
                      KubbTokens.space4, KubbTokens.space12),
                  itemCount: users.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: KubbTokens.space2),
                  itemBuilder: (_, i) => _UserRow(
                    row: users[i],
                    onTap: () => context.push(
                      '/admin/user/${users[i].userId}',
                      extra: users[i],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.row, required this.onTap});

  final AdminUserRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space3),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.nickname.isEmpty ? '(kein Name)' : row.nickname,
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: tokens.fg),
                    ),
                    const SizedBox(height: KubbTokens.space1),
                    Wrap(
                      spacing: KubbTokens.space1,
                      runSpacing: KubbTokens.space1,
                      children: [
                        if (row.isAdmin)
                          const _Badge('Admin', KubbTokens.miss),
                        if (row.canFoundClubs)
                          const _Badge('Veranstalter', KubbTokens.hit),
                        if (row.isSuspended)
                          const _Badge('Gesperrt', KubbTokens.miss),
                        for (final k in row.authKinds)
                          _Badge(_authLabel(k), tokens.fgMuted),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: tokens.fgMuted),
            ],
          ),
        ),
      ),
    );
  }
}

String _authLabel(String kind) {
  switch (kind) {
    case 'keypair':
      return 'Passphrase';
    case 'oauth_google':
      return 'Google';
    case 'oauth_apple':
      return 'Apple';
    case 'password':
      return 'Passwort';
    default:
      return kind;
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space2, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
