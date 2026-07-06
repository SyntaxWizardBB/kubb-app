import 'package:kubb_app/features/admin/data/admin_models.dart';

/// Caller-gated admin operations (M1). Every method maps to an `admin_*`
/// RPC that re-checks `caller_is_admin()` server-side (migration
/// 20261333000000), so this layer carries no authority of its own.
/// Impersonation is deliberately NOT here — it is a session concern owned by
/// `impersonationProvider` in the auth feature.
abstract class AdminRepository {
  /// Lists user profiles, newest first; `query` filters on nickname
  /// (case-insensitive substring). Empty/blank query returns all.
  Future<List<AdminUserRow>> listUsers({
    String? query,
    int limit,
    int offset,
  });

  /// Grants/revokes a capability. [capability] is `can_found_clubs` or
  /// `is_admin`. Idempotent server-side.
  Future<void> setCapability({
    required String userId,
    required String capability,
    required bool value,
  });

  /// Suspends (blocks all logins) or reactivates an account.
  Future<void> setAccountStatus({
    required String userId,
    required bool suspended,
  });

  /// Hard-deletes an account and all cascade-linked rows. Irreversible.
  Future<void> deleteAccount({required String userId});

  /// Sends an in-app inbox message (rides the CDC + push spine). Returns the
  /// created message id.
  Future<String> sendInbox({
    required String userId,
    required String subject,
    required String body,
  });
}
