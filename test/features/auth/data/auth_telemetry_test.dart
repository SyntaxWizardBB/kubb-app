import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:logging/logging.dart';

/// PII-leak detector. Any new event handler that touches a sensitive
/// field must run its inputs through here before sign-off.
final _piiSubstrings = <String>[
  '@',                           // email-like
  'google-12345',                // oauth subject sample
  'apple-67890',                 // oauth subject sample
  'eyJ',                         // base64-encoded JWT prefix
  'Bearer ',                     // header form
  'fullnickname',                // full nickname sample
];

void main() {
  late AuthTelemetry telemetry;
  late Logger logger;
  late List<LogRecord> records;
  late void Function(LogRecord) sink;

  setUp(() {
    records = <LogRecord>[];
    logger = Logger.detached('auth-test')..level = Level.ALL;
    sink = records.add;
    logger.onRecord.listen(sink);
    telemetry = AuthTelemetry(logger: logger);
  });

  void expectNoPii(String haystack) {
    for (final needle in _piiSubstrings) {
      expect(
        haystack.contains(needle),
        isFalse,
        reason: 'log record contains PII substring "$needle": $haystack',
      );
    }
  }

  test('signinSuccess truncates userId to 8 chars and drops the full one',
      () {
    telemetry.signinSuccess(
      userId: 'abc12345-6789-aaaa-bbbb-fullnickname-suffix',
      kind: 'oauth_google',
    );

    expect(records.length, 1);
    expect(records.first.level, Level.INFO);
    expect(records.first.message, contains('signinSuccess'));
    expect(records.first.message, contains('userId=abc12345'));
    expect(records.first.message, contains('kind=oauth_google'));
    expect(records.first.message, isNot(contains('fullnickname-suffix')));
    expectNoPii(records.first.message);
  });

  test('signinFailure logs at WARNING and keeps reason code, not message',
      () {
    telemetry.signinFailure(
      kind: 'keypair',
      reasonCode: 'passphrase_mismatch',
    );

    expect(records.first.level, Level.WARNING);
    expect(records.first.message, contains('signinFailure'));
    expect(records.first.message, contains('reason=passphrase_mismatch'));
    expectNoPii(records.first.message);
  });

  test('logout records userId prefix only', () {
    telemetry
      ..logout(userId: 'short')
      ..logout(userId: 'long-user-id-that-keeps-going-and-going');

    expect(records.length, 2);
    expect(records[0].message, contains('userId=short'));
    expect(records[1].message, contains('userId=long-use'));
    expect(records[1].message, isNot(contains('keeps-going')));
  });

  test('refreshFailure does not include the refresh token in any form', () {
    telemetry.refreshFailure(reasonCode: 'token_expired');

    expect(records.first.level, Level.WARNING);
    expect(records.first.message, contains('refreshFailure'));
    expect(records.first.message, contains('reason=token_expired'));
    expectNoPii(records.first.message);
  });

  test('accountUpgrade records the target kind without provider id', () {
    telemetry.accountUpgrade(
      userId: 'abc12345-extra',
      toKind: 'oauth_apple',
    );

    expect(records.first.message, contains('accountUpgrade'));
    expect(records.first.message, contains('userId=abc12345'));
    expect(records.first.message, contains('to=oauth_apple'));
    // The provider id ("apple-67890" sample) is not passed in.
    expectNoPii(records.first.message);
  });

  test('signinAttempt does not log a userId at all', () {
    telemetry.signinAttempt(kind: 'oauth_google');

    expect(records.first.message, contains('signinAttempt'));
    expect(records.first.message, contains('kind=oauth_google'));
    expect(records.first.message, isNot(contains('userId')));
  });

  test('every AuthEvent is exercised by the API surface', () {
    // Documents the API completeness — if a new event is added to the
    // enum, this test forces the maintainer to add a corresponding
    // method (and unit test) before commit.
    final exercisable = {
      AuthEvent.signinAttempt: () =>
          telemetry.signinAttempt(kind: 'k'),
      AuthEvent.signinSuccess: () =>
          telemetry.signinSuccess(userId: 'u', kind: 'k'),
      AuthEvent.signinFailure: () =>
          telemetry.signinFailure(kind: 'k', reasonCode: 'r'),
      AuthEvent.refreshSuccess: () =>
          telemetry.refreshSuccess(userId: 'u'),
      AuthEvent.refreshFailure: () =>
          telemetry.refreshFailure(reasonCode: 'r'),
      AuthEvent.logout: () => telemetry.logout(userId: 'u'),
      AuthEvent.accountDelete: () =>
          telemetry.accountDelete(userId: 'u'),
      AuthEvent.accountUpgrade: () =>
          telemetry.accountUpgrade(userId: 'u', toKind: 'k'),
    };

    expect(exercisable.keys.toSet(), AuthEvent.values.toSet());

    for (final action in exercisable.values) {
      action();
    }
    expect(records.length, AuthEvent.values.length);
  });
}
