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
