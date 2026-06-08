import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Base for the app's public, anon-spectator deep links. ONE constant so
/// the public tournament link (`/public/tournament/:id`) and the public
/// match link (`/public/match/:matchId`) share the exact same host /
/// scheme convention — see the GoRouter routes in `lib/app/router.dart`.
///
/// No app-link host is configured yet (no `android:scheme` / universal
/// link), so we emit a stable, fully-qualified URL that mirrors the
/// in-app route path. When a real deep-link host is registered this is
/// the single place to change.
const String kubbPublicLinkBase = 'https://kubbclub.app';

/// Builds the shareable public link for a single tournament match. The
/// suffix matches the GoRoute `/public/match/:matchId`.
String publicMatchLink(String matchId) =>
    '$kubbPublicLinkBase/public/match/$matchId';

/// Builds the shareable public link for a tournament. The suffix matches
/// the GoRoute `/public/tournament/:id`.
String publicTournamentLink(String tournamentId) =>
    '$kubbPublicLinkBase/public/tournament/$tournamentId';

/// How the link was delivered to the user.
enum LinkShareKind { shared, copiedToClipboard }

/// Result of a [PublicLinkShareService.shareLink] call.
@immutable
class LinkShareResult {
  const LinkShareResult({required this.kind, required this.link});
  final LinkShareKind kind;
  final String link;
}

/// Thin adapter around `share_plus` for sharing a public link, with a
/// clipboard fallback on platforms without a system share sheet (desktop
/// / web). Kept as an injectable seam so widgets can be tested without
/// the `SharePlus` channel — mirrors `CsvShareService`.
class PublicLinkShareService {
  /// Shares [link] via the system share sheet on mobile; copies it to the
  /// clipboard otherwise (or when [SharePlus] is unavailable). [subject]
  /// is the optional share-sheet title.
  Future<LinkShareResult> shareLink(
    String link, {
    String? subject,
  }) async {
    if (_useSystemShare) {
      await SharePlus.instance.share(
        ShareParams(text: link, subject: subject),
      );
      return LinkShareResult(kind: LinkShareKind.shared, link: link);
    }
    await Clipboard.setData(ClipboardData(text: link));
    return LinkShareResult(
        kind: LinkShareKind.copiedToClipboard, link: link);
  }

  bool get _useSystemShare {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}

final publicLinkShareServiceProvider = Provider<PublicLinkShareService>((ref) {
  return PublicLinkShareService();
});
