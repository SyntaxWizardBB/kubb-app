import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/public_link_share_service.dart';

// P1: the per-match share link must point at the public route
// /public/match/<matchId>, sharing the same host as the public tournament
// link /public/tournament/<id>.
void main() {
  test('publicMatchLink ends with /public/match/<matchId>', () {
    final link = publicMatchLink('abc-123');
    expect(link, endsWith('/public/match/abc-123'));
    expect(link, startsWith(kubbPublicLinkBase));
  });

  test('publicTournamentLink ends with /public/tournament/<id>', () {
    final link = publicTournamentLink('t-7');
    expect(link, endsWith('/public/tournament/t-7'));
    expect(link, startsWith(kubbPublicLinkBase));
  });

  test('match and tournament links share the same host base', () {
    expect(
      publicMatchLink('m').replaceAll('/public/match/m', ''),
      publicTournamentLink('t').replaceAll('/public/tournament/t', ''),
    );
  });
}
