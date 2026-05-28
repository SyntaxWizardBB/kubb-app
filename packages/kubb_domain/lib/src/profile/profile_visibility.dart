/// User-facing visibility tier for a `user_profiles` row.
///
/// The server enforces the same set as a CHECK constraint and as RLS-
/// policy branches (see migration `20260601000020_profile_visibility`).
/// Refs:
///   - R20-F-02 (Profile-Visibility-Settings, FR-AUTH-5, DSGVO Art. 25
///     Privacy-by-Default)
///   - R20-F-10 (Friends-only-Privacy, FR-SOCIAL-4)
enum ProfileVisibility {
  /// Every authenticated user can read the profile row.
  public('public'),

  /// Owner plus accepted-friends can read the row. This is the
  /// Privacy-by-Default tier (DSGVO Art. 25) and the floor for new
  /// accounts.
  friendsOnly('friends_only'),

  /// Only the owner can read the row.
  private('private');

  const ProfileVisibility(this.wireValue);

  /// Stable wire / database identifier. Matches the CHECK constraint on
  /// `public.user_profiles.profile_visibility`.
  final String wireValue;

  /// Privacy-floor default per DSGVO Art. 25 — new accounts MUST start
  /// at the friends-only tier and only opt-in to a wider visibility.
  static const ProfileVisibility defaultTier = ProfileVisibility.friendsOnly;

  /// Parses a wire value. Unknown / null values fall back to
  /// [defaultTier] — this keeps the client robust against a server-side
  /// migration adding a new tier we do not understand yet.
  static ProfileVisibility fromWire(String? value) {
    for (final tier in ProfileVisibility.values) {
      if (tier.wireValue == value) return tier;
    }
    return defaultTier;
  }
}
