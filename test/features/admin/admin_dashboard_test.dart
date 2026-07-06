import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/admin/application/admin_providers.dart';
import 'package:kubb_app/features/admin/data/admin_models.dart';
import 'package:kubb_app/features/admin/data/admin_repository.dart';
import 'package:kubb_app/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:kubb_app/features/admin/presentation/admin_user_detail_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository(this.rows);
  final List<AdminUserRow> rows;
  final List<(String, String, bool)> capabilityCalls = [];

  @override
  Future<List<AdminUserRow>> listUsers(
      {String? query, int limit = 50, int offset = 0}) async {
    if (query == null || query.isEmpty) return rows;
    return rows
        .where((r) => r.nickname.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Future<void> setCapability(
      {required String userId,
      required String capability,
      required bool value}) async {
    capabilityCalls.add((userId, capability, value));
  }

  @override
  Future<void> setAccountStatus(
      {required String userId, required bool suspended}) async {}

  @override
  Future<void> deleteAccount({required String userId}) async {}

  @override
  Future<String> sendInbox(
          {required String userId,
          required String subject,
          required String body}) async =>
      'msg-id';
}

AdminUserRow _row(String id, String nick,
        {bool admin = false, bool founder = false, DateTime? suspended}) =>
    AdminUserRow(
      userId: id,
      nickname: nick,
      createdAt: DateTime.utc(2026),
      isAdmin: admin,
      canFoundClubs: founder,
      authKinds: const ['keypair'],
      suspendedAt: suspended,
    );

Widget _wrap(Widget home, _FakeAdminRepository repo) => ProviderScope(
      overrides: [adminRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: home,
      ),
    );

void main() {
  testWidgets('dashboard lists users with capability badges', (tester) async {
    final repo = _FakeAdminRepository([
      _row('a', 'Alice', admin: true),
      _row('b', 'Bob', founder: true, suspended: DateTime.utc(2026)),
    ]);
    await tester.pumpWidget(_wrap(const AdminDashboardScreen(), repo));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    // Bob's badges — unambiguous (the appbar title is 'Admin', so we assert
    // on the founder/suspended badges instead).
    expect(find.text('Veranstalter'), findsOneWidget);
    expect(find.text('Gesperrt'), findsOneWidget);
  });

  testWidgets('detail: toggling Veranstalter calls setCapability',
      (tester) async {
    final repo = _FakeAdminRepository([]);
    await tester.pumpWidget(
      _wrap(AdminUserDetailScreen(row: _row('b', 'Bob')), repo),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Veranstalter (kann Turniere & Vereine anlegen)'));
    await tester.pumpAndSettle();

    expect(repo.capabilityCalls, [('b', 'can_found_clubs', true)]);
  });
}
