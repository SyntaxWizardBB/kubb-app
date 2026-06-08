import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// M1: single source of truth for turning a tournament participant into a
/// human-readable display name across ALL match-display surfaces (list /
/// card, set input, match detail, public screens).
///
/// The server projects the participant's display name
/// (`participant_{a,b}_display_name`: single -> player nickname, team ->
/// team name; for a singles tournament the player name IS the team name,
/// already resolved server-side). This helper only decides the fallback:
///
///   * a present, non-empty trimmed `displayName` is used verbatim;
///   * otherwise the localized `tournamentParticipantUnknown`
///     ("Unbekannt") is returned — NEVER 'A'/'B' and NEVER a raw UUID.
///
/// Centralizing the fallback keeps every surface consistent and removes the
/// previously duplicated `_resolveLabel` / `_participantLabel` / `_name` /
/// `label()` copies (each of which had its own A/B- or UUID-substring
/// fallback).
///
/// The resolution is driven purely by the server-projected `displayName`;
/// callers that want the BYE/Freilos label must handle `participantB == null`
/// themselves before calling this (this helper only guards the unknown-name
/// fallback, never leaking a raw placeholder).
abstract final class ParticipantName {
  /// Resolves the display name for a participant slot.
  ///
  /// A present, non-empty trimmed [displayName] is used verbatim; otherwise
  /// the localized `tournamentParticipantUnknown` ("Unbekannt") is returned —
  /// NEVER 'A'/'B' and NEVER a raw UUID.
  static String resolve(
    AppLocalizations l, {
    required String? displayName,
  }) {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return l.tournamentParticipantUnknown;
  }
}
