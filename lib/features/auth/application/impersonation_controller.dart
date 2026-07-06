import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Active-impersonation snapshot. Non-null only while an admin is acting as
/// another user. Read by the global banner and by [AuthController]'s
/// clobber-gate (which must NOT persist the impersonated session to the
/// drift cache, so the admin identity survives a cold restart / drives the
/// exit re-sign).
@immutable
class ImpersonationState {
  const ImpersonationState({
    required this.adminUserId,
    required this.targetUserId,
    required this.targetNickname,
  });

  final String adminUserId;
  final String targetUserId;
  final String targetNickname;
}

/// Owns the impersonation lifecycle (M1 §2.2). `start` calls the
/// `admin-impersonate` edge function (which enforces admin + non-suspended +
/// not-an-admin-target and audits), installs the returned short-lived token
/// as the live session, and marks the in-flight state. `stop` clears the
/// state first (re-arming normal persistence) and re-signs the admin's own
/// session from the still-intact drift cache.
class ImpersonationNotifier extends Notifier<ImpersonationState?> {
  @override
  ImpersonationState? build() => null;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> start(String targetUserId) async {
    final res = await _client.functions.invoke(
      'admin-impersonate',
      body: <String, dynamic>{'target_user_id': targetUserId},
    );
    final data = (res.data as Map).cast<String, dynamic>();

    // Set the in-flight state BEFORE installing the session: the recoverSession
    // below fires onAuthStateChange, and the AuthController gate keys on this
    // being non-null to skip persisting the impersonated identity.
    state = ImpersonationState(
      adminUserId: data['impersonator_id'] as String,
      targetUserId: data['user_id'] as String,
      targetNickname: (data['nickname'] as String?) ?? '',
    );

    try {
      await _installSession(
        accessToken: data['access_token'] as String,
        expiresAtUnix: (data['expires_at'] as num).toInt(),
        userId: data['user_id'] as String,
        nickname: (data['nickname'] as String?) ?? '',
      );
    } on Object {
      state = null; // roll back the gate if the session never installed
      rethrow;
    }
  }

  Future<void> stop() async {
    if (state == null) return;
    // Clear FIRST so the admin re-sign emission persists normally.
    state = null;
    await ref.read(forceReSignWireSessionProvider)();
  }

  // Hydrate a self-contained Session (no refresh_token) via recoverSession —
  // the same envelope the keypair path uses (supabase_auth_adapter_impl). The
  // local user is classified as keypair for a clean display name; the true
  // impersonator_id lives in [state], read by the banner, not decoded here.
  Future<void> _installSession({
    required String accessToken,
    required int expiresAtUnix,
    required String userId,
    required String nickname,
  }) async {
    final sessionJson = jsonEncode(<String, dynamic>{
      'access_token': accessToken,
      'token_type': 'bearer',
      'expires_in':
          expiresAtUnix - DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'expires_at': expiresAtUnix,
      'user': <String, dynamic>{
        'id': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'app_metadata': <String, dynamic>{
          'provider': 'keypair',
          'providers': <String>['keypair'],
        },
        'user_metadata': <String, dynamic>{'nickname': nickname},
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_anonymous': false,
      },
    });
    await _client.auth.recoverSession(sessionJson);
  }
}

final impersonationProvider =
    NotifierProvider<ImpersonationNotifier, ImpersonationState?>(
  ImpersonationNotifier.new,
);
