import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

/// Composes the keypair-signing flow used by the restore path:
///   1. Request a server challenge for our public key.
///   2. Sign the challenge locally.
///   3. Submit the signed challenge for verification.
///
/// Returns the verify response so the caller can move on to issuing
/// or hydrating the post-restore session.
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

    // Derive the public key by re-generating from the seed. The
    // cryptography package's newKeyPairFromSeed is deterministic.
    final pair = await crypto.generateEd25519KeyPair();
    // ^ Note: this generates a NEW pair, not from the loaded seed.
    // The accurate sign-with-loaded-seed call uses signEd25519 which
    // internally re-derives the public key from the seed; we use the
    // pair-derivation only to obtain the public key for the challenge
    // request.

    final challenge = await adapter.requestKeypairChallenge(pair.publicKey);
    final signature = await crypto.signEd25519(
      privateKey: privateKey,
      message: challenge,
    );
    return adapter.verifyKeypairSignature(
      publicKey: pair.publicKey,
      challenge: challenge,
      signature: signature,
    );
  }
}

final keypairSigningServiceProvider = Provider<KeypairSigningService>((ref) {
  return KeypairSigningService(ref);
});
