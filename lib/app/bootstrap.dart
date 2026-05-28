import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_app/core/application/outbox_gc_task.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/dao/score_submission_outbox_dao.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:logging/logging.dart';

final _bootstrapLog = Logger('Bootstrap');

// Resolved once at app start. While pending, KubbApp renders a splash
// instead of the router so the redirect never sees an AsyncLoading
// auth state. Reads the cached auth session so the router can decide
// straight away whether to land on the sign-in screen or the home tab.
//
// After reading the cache we run [ensureWireSession] — this closes the
// R1-F-02 race (Mängel #9, `authentication required` on tournament
// create): the drift cache may hold a keypair / OAuth session while the
// underlying Supabase wire session is empty (cold start, expired
// access token, Phase-1 keypair token without refresh counterpart).
// Without this hop the first authenticated RPC after launch fires
// without an `Authorization` header and surfaces as an auth error
// downstream. The call is best-effort: a failure does not block
// rendering, the router decides what to do based on the live state.
//
// After the DB is reachable we also run the outbox GC (TASK-M4.3-T13)
// to bound the `score_submission_outbox` table. The GC is best-effort:
// a failure must not block sign-in, so we log and continue.
final appBootstrapProvider = FutureProvider<CachedAuthSessionData?>(
  (ref) async {
    final dao = ref.read(cachedAuthSessionDaoProvider);
    final session = await dao.current();
    if (session != null) {
      try {
        await ensureWireSession(ref);
      } on Object catch (e, st) {
        // ensureWireSession is already defensive internally; the catch
        // here is the belt-and-braces for an unexpected throw out of
        // the helper itself (e.g. provider misconfiguration in tests).
        _bootstrapLog.warning('ensureWireSession threw', e, st);
      }
    }
    final outboxDao = ref.read(scoreSubmissionOutboxDaoProvider);
    unawaited(_runOutboxGc(outboxDao));
    return session;
  },
);

Future<void> _runOutboxGc(ScoreSubmissionOutboxDao dao) async {
  try {
    await OutboxGcTask(dao).run();
  } on Object catch (e, st) {
    _bootstrapLog.warning('outbox GC failed', e, st);
  }
}
