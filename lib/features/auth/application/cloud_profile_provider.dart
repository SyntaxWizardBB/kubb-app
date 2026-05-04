import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';
import 'package:kubb_app/features/auth/data/cloud_profile_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository over the `user_profiles` cloud table. Tests override
/// with the fake from `test/fixtures/auth/fake_cloud_profile_repository.dart`.
final cloudProfileRepositoryProvider = Provider<CloudProfileRepository>((ref) {
  return CloudProfileRepositoryImpl(Supabase.instance.client);
});
