import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Document kind stored in the `tournament-pdfs` bucket. Maps to the path
/// prefix the object is uploaded under.
enum TournamentPdfKind {
  rules('rules'),
  siteMap('maps');

  const TournamentPdfKind(this.pathPrefix);

  final String pathPrefix;
}

/// Uploads tournament PDFs (rules / site map) and returns their public URL.
/// Abstract so widget tests can inject a fake without touching Storage.
// ignore: one_member_abstracts
abstract interface class TournamentPdfUploader {
  /// Uploads [bytes] as a PDF of [kind] and returns the public URL of the
  /// stored object. Throws on failure so the caller can surface an error.
  Future<String> uploadPdf({
    required TournamentPdfKind kind,
    required Uint8List bytes,
  });
}

/// Supabase Storage-backed implementation. Objects land in the
/// `tournament-pdfs` bucket under `<prefix>/<uuid>.pdf`; the bucket is
/// public-read (see migration `20261001000003_tournament_storage`).
class SupabaseTournamentPdfUploader implements TournamentPdfUploader {
  SupabaseTournamentPdfUploader(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  static const String bucket = 'tournament-pdfs';

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<String> uploadPdf({
    required TournamentPdfKind kind,
    required Uint8List bytes,
  }) async {
    final path = '${kind.pathPrefix}/${_uuid.v4()}.pdf';
    final storage = _client.storage.from(bucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'application/pdf',
        upsert: true,
      ),
    );
    return storage.getPublicUrl(path);
  }
}

/// Injectable uploader. Overridden in tests with a fake so the wizard's
/// PDF field never reaches Storage during widget tests.
final tournamentPdfUploaderProvider = Provider<TournamentPdfUploader>((ref) {
  return SupabaseTournamentPdfUploader(Supabase.instance.client);
});
