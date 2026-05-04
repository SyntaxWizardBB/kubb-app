import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

/// Composes the keypair-signing flow used by the restore path:
///   1. Re-derive the public key from the seed in secure storage.
///   2. Request a server challenge for that public key.
///   3. Sign the challenge locally.
///   4. Submit the signed challenge for verification — the adapter
///      hydrates the resulting Supabase session in the same call.
class KeypairSigningService {
  KeypairSigningService(this._ref);

  final Ref _ref;

  Future<AuthVerifyResult> signInWithChallenge() async {
    final adapter = _ref.read(supabaseAuthAdapterProvider);
    final keypairStorage = _ref.read(keypairStorageProvider);
    final crypto = _ref.read(cryptoServiceProvider);

    final privateKey = await keypairStorage.load();
    if (privateKey == null) {
      throw StateError(
        'signInWithChallenge requires a private key in secure storage',
      );
    }

    final publicKey = await crypto.publicKeyFromSeed(privateKey);
    final challenge = await adapter.requestKeypairChallenge(publicKey);
    final signature = await crypto.signEd25519(
      privateKey: privateKey,
      message: challenge,
    );
    return adapter.verifyKeypairSignature(
      publicKey: publicKey,
      challenge: challenge,
      signature: signature,
    );
  }
}

final keypairSigningServiceProvider = Provider<KeypairSigningService>((ref) {
  return KeypairSigningService(ref);
});
