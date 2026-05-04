import 'package:logging/logging.dart';

/// Discrete auth events that the controller layer emits to the
/// telemetry sink. Keep this enum the single source of truth so
/// downstream filters (PII checks, metrics dashboards, log audits)
/// can be exhaustive.
enum AuthEvent {
  signinAttempt,
  signinSuccess,
  signinFailure,
  refreshSuccess,
  refreshFailure,
  logout,
  accountDelete,
  accountUpgrade,
  profileUpdate,
  restoreAttempted,
  passphraseChanged,
  keypairBackupCreated,
  keypairBackupRotated,
}

/// Routes auth-state transitions to `package:logging` with strict PII
/// scrubbing. Callers pass the user id raw; this class truncates to
/// the first eight characters before it ever lands in a log record.
///
/// Anything that could conceivably identify a real person — email,
/// OAuth subject, full nickname, token, signature, public key — is
/// either dropped at the API boundary or, where the value adds debug
/// signal (e.g. event kind), kept in a constrained shape.
class AuthTelemetry {
  AuthTelemetry({Logger? logger})
      : _logger = logger ?? Logger('auth');

  final Logger _logger;

  /// Maximum length of the user-id prefix that lands in log records.
  /// Eight characters is enough to disambiguate during a debugging
  /// session without leaking a usable identifier.
  static const int userIdPrefixLength = 8;

  void signinAttempt({required String kind}) {
    _emit(AuthEvent.signinAttempt, message: 'kind=$kind');
  }

  void signinSuccess({required String userId, required String kind}) {
    _emit(
      AuthEvent.signinSuccess,
      message: 'userId=${_prefix(userId)} kind=$kind',
    );
  }

  void signinFailure({required String kind, required String reasonCode}) {
    _emit(
      AuthEvent.signinFailure,
      message: 'kind=$kind reason=$reasonCode',
      level: Level.WARNING,
    );
  }

  void refreshSuccess({required String userId}) {
    _emit(
      AuthEvent.refreshSuccess,
      message: 'userId=${_prefix(userId)}',
    );
  }

  void refreshFailure({required String reasonCode}) {
    _emit(
      AuthEvent.refreshFailure,
      message: 'reason=$reasonCode',
      level: Level.WARNING,
    );
  }

  void logout({required String userId}) {
    _emit(
      AuthEvent.logout,
      message: 'userId=${_prefix(userId)}',
    );
  }

  void accountDelete({required String userId}) {
    _emit(
      AuthEvent.accountDelete,
      message: 'userId=${_prefix(userId)}',
    );
  }

  void accountUpgrade({required String userId, required String toKind}) {
    _emit(
      AuthEvent.accountUpgrade,
      message: 'userId=${_prefix(userId)} to=$toKind',
    );
  }

  /// Logged after a successful cloud-profile update. The actual
  /// nickname and avatar value never leave the client; we only record
  /// which fields the user touched so a regression in the edit flow
  /// can be diagnosed without trawling the database.
  void profileUpdate({
    required String userId,
    required bool didRenameNickname,
    required bool didChangeAvatar,
  }) {
    _emit(
      AuthEvent.profileUpdate,
      message: 'userId=${_prefix(userId)} '
          'rename=$didRenameNickname avatar=$didChangeAvatar',
    );
  }

  /// Logged on every restore attempt — both the success path and the
  /// per-attempt failures. The cooldown branch passes `success: false`
  /// with `reason: cooldown_triggered` so the rate-limit can be
  /// audited from the log alone.
  ///
  /// No userId is recorded: at the point this event fires the actual
  /// account id is not yet known (the sign-in challenge runs after the
  /// private key has been put on the device). Trying to log a userId
  /// here would either be a placeholder or leak the nickname.
  void restoreAttempted({
    required bool success,
    String? reasonCode,
  }) {
    final parts = <String>[
      'success=$success',
      if (reasonCode != null) 'reason=$reasonCode',
    ];
    _emit(
      AuthEvent.restoreAttempted,
      message: parts.join(' '),
      level: success ? Level.INFO : Level.WARNING,
    );
  }

  /// Logged after the encrypted backup row was re-encrypted with a
  /// new passphrase. Neither the old nor the new passphrase appears
  /// in the log — only the user-id prefix.
  void passphraseChanged({required String userId}) {
    _emit(
      AuthEvent.passphraseChanged,
      message: 'userId=${_prefix(userId)}',
    );
  }

  /// Logged after the initial encrypted-keypair upload during anonymous
  /// signup. Distinct from `passphraseChanged` so a backup that exists
  /// only because of a rotation can be distinguished from a brand-new
  /// account.
  void keypairBackupCreated({required String userId}) {
    _emit(
      AuthEvent.keypairBackupCreated,
      message: 'userId=${_prefix(userId)}',
    );
  }

  /// Logged after a backup row was rotated as part of a recovery
  /// flow (e.g. account-link re-encrypts under a new passphrase).
  void keypairBackupRotated({required String userId}) {
    _emit(
      AuthEvent.keypairBackupRotated,
      message: 'userId=${_prefix(userId)}',
    );
  }

  void _emit(
    AuthEvent event, {
    required String message,
    Level level = Level.INFO,
  }) {
    _logger.log(level, '${event.name} $message');
  }

  String _prefix(String userId) {
    if (userId.length <= userIdPrefixLength) return userId;
    return userId.substring(0, userIdPrefixLength);
  }
}
