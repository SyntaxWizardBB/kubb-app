import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/admin/data/admin_models.dart';
import 'package:kubb_app/features/admin/data/admin_repository.dart';
import 'package:kubb_app/features/admin/data/admin_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository over the caller-gated `admin_*` RPCs. Tests override with a fake.
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepositoryImpl(Supabase.instance.client);
});

/// The admin user list for a given search query. `family` keyed on the
/// (already-debounced) query string; the dashboard invalidates it after a
/// mutation to refresh. autoDispose so it drops when the screen closes.
//
// ignore: specify_nonobvious_property_types
final adminUserListProvider =
    FutureProvider.autoDispose.family<List<AdminUserRow>, String>((ref, query) {
  return ref.watch(adminRepositoryProvider).listUsers(query: query);
});
