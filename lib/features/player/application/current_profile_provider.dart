import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/player/data/player_repository.dart';

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PlayerRepository(db.playerDao);
});

final currentProfileProvider = StreamProvider<Player?>((ref) {
  final repo = ref.watch(playerRepositoryProvider);
  return repo.watchCurrent();
});
