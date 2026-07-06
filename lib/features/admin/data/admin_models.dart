import 'package:flutter/foundation.dart';

/// One row of the admin user list, as projected by the `admin_list_users`
/// RPC (migration 20261333000000). App-only feature (M1) — kept in the
/// feature's data layer rather than the kubb_domain port, since no other
/// context consumes it.
@immutable
class AdminUserRow {
  const AdminUserRow({
    required this.userId,
    required this.nickname,
    required this.createdAt,
    required this.isAdmin,
    required this.canFoundClubs,
    required this.authKinds,
    this.avatarColor,
    this.suspendedAt,
  });

  factory AdminUserRow.fromJson(Map<String, dynamic> json) {
    return AdminUserRow(
      userId: json['user_id'] as String,
      nickname: json['nickname'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      isAdmin: json['is_admin'] as bool? ?? false,
      canFoundClubs: json['can_found_clubs'] as bool? ?? false,
      authKinds:
          (json['auth_kinds'] as List?)?.cast<String>() ?? const <String>[],
      avatarColor: json['avatar_color'] as String?,
      suspendedAt: json['suspended_at'] == null
          ? null
          : DateTime.parse(json['suspended_at'] as String),
    );
  }

  final String userId;
  final String nickname;
  final DateTime createdAt;
  final bool isAdmin;
  final bool canFoundClubs;

  /// Distinct `user_credentials.kind` values on the account
  /// (`keypair` / `oauth_google` / `oauth_apple` / `password`). Drives the
  /// "how they sign in" chips.
  final List<String> authKinds;

  final String? avatarColor;

  /// Non-null once an admin has suspended the account.
  final DateTime? suspendedAt;

  bool get isSuspended => suspendedAt != null;

  AdminUserRow copyWith({
    bool? isAdmin,
    bool? canFoundClubs,
    DateTime? suspendedAt,
    bool clearSuspended = false,
  }) {
    return AdminUserRow(
      userId: userId,
      nickname: nickname,
      createdAt: createdAt,
      isAdmin: isAdmin ?? this.isAdmin,
      canFoundClubs: canFoundClubs ?? this.canFoundClubs,
      authKinds: authKinds,
      avatarColor: avatarColor,
      suspendedAt: clearSuspended ? null : (suspendedAt ?? this.suspendedAt),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminUserRow &&
          other.userId == userId &&
          other.nickname == nickname &&
          other.isAdmin == isAdmin &&
          other.canFoundClubs == canFoundClubs &&
          other.suspendedAt == suspendedAt &&
          listEquals(other.authKinds, authKinds);

  @override
  int get hashCode => Object.hash(
        userId,
        nickname,
        isAdmin,
        canFoundClubs,
        suspendedAt,
        Object.hashAll(authKinds),
      );
}
