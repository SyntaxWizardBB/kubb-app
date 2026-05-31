import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';
import 'package:kubb_app/features/auth/data/cloud_profile_repository_impl.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository over the `user_profiles` cloud table. Tests override
/// with the fake from `test/fixtures/auth/fake_cloud_profile_repository.dart`.
final cloudProfileRepositoryProvider = Provider<CloudProfileRepository>((ref) {
  return CloudProfileRepositoryImpl(Supabase.instance.client);
});

/// Async snapshot of the current user's `user_profiles` row. Surfaces
/// that need fields beyond the cached auth session (notably the
/// visibility tier driving the Settings picker) watch this provider
/// and react to invalidations after a save.
final cloudProfileProvider = FutureProvider<CloudProfile?>((ref) async {
  final display = ref.watch(displayProfileProvider);
  if (display == null) return null;
  final repo = ref.watch(cloudProfileRepositoryProvider);
  return repo.getProfile(userId: display.userId);
});

/// Whether the current user may create/publish tournaments (coarse
/// organizer role, P1 Tournament-Hub). Derived from the cloud profile's
/// `is_organizer` flag; resolves to `false` while the profile is loading
/// or absent so the "create tournament" tile only appears once the role is
/// confirmed. The server-side default is `true`, so in practice every
/// signed-in user with a profile resolves to `true` today.
final isOrganizerProvider = Provider<bool>((ref) {
  return ref.watch(cloudProfileProvider).maybeWhen(
        data: (profile) => profile?.isOrganizer ?? false,
        orElse: () => false,
      );
});
