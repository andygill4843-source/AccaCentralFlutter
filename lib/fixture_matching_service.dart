import 'sportmonks_service.dart';
import 'package:collection/collection.dart';

/// Bridges The Odds API's fixture (used when a member picks a leg) to its
/// Sportmonks equivalent (used for live scores). The two providers don't
/// share an ID scheme, so this does a best-effort match by kickoff date and
/// team name at the moment a leg is submitted.
class FixtureMatchingService {
  static Future<int?> resolveSportmonksFixtureId({
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoff,
  }) async {
    try {
      final fixtures = await SportmonksService.instance.fetchFixturesOnDate(kickoff);
      final match = fixtures.where((f) {
        final homeMatches = f.homeTeamName.toLowerCase().contains(homeTeam.toLowerCase()) ||
            homeTeam.toLowerCase().contains(f.homeTeamName.toLowerCase());
        final awayMatches = f.awayTeamName.toLowerCase().contains(awayTeam.toLowerCase()) ||
            awayTeam.toLowerCase().contains(f.awayTeamName.toLowerCase());
        return homeMatches && awayMatches;
      }).firstOrNull;
      return match?.id;
    } catch (_) {
      return null; // best-effort — a leg with no match just shows "—" on the live screen
    }
  }
}