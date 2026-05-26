/// League tiers a team can be enrolled in.
///
/// Per ADR-0018 the schema accepts only `A`, `B`, `C`. The DB
/// `teams.league_membership_check` rejects any other value; the wizard
/// presents these three options with B as the default.
enum LeagueMembership {
  a,
  b,
  c;

  /// Wire value used by the RPC contract (uppercase single letter).
  String get wire => switch (this) {
        LeagueMembership.a => 'A',
        LeagueMembership.b => 'B',
        LeagueMembership.c => 'C',
      };

  static LeagueMembership fromWire(String value) => switch (value) {
        'A' => LeagueMembership.a,
        'B' => LeagueMembership.b,
        'C' => LeagueMembership.c,
        _ => throw ArgumentError.value(
            value,
            'value',
            'Unknown league membership wire value',
          ),
      };
}
