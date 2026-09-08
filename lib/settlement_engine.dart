import 'models.dart';
import 'api_football_service.dart';

/// Determines whether a leg is currently winning based on live fixture data.
/// Uses the same logic as settleLegs.js — keep both in sync when adding
/// new bet types.
class SettlementEngine {
  static bool isCurrentlyWinning({
    required AccumulatorLeg leg,
    required ApiFootballFixture fixture,
  }) {
    final homeGoals = fixture.homeGoals ?? 0;
    final awayGoals = fixture.awayGoals ?? 0;
    final totalGoals = homeGoals + awayGoals;
    final desc = leg.selectionDescription.toLowerCase().trim();

    switch (leg.betType) {
      case BetType.matchWinner:
        if (desc.contains(fixture.homeTeam.toLowerCase()) ||
            desc == 'home' || desc.contains('home win')) {
          return homeGoals > awayGoals;
        }
        if (desc.contains(fixture.awayTeam.toLowerCase()) ||
            desc == 'away' || desc.contains('away win')) {
          return awayGoals > homeGoals;
        }
        if (desc == 'draw' || desc.contains('x')) {
          return homeGoals == awayGoals;
        }
        return false;

      case BetType.bothTeamsToScore:
        final isYes = desc.contains('yes') || desc == 'btts - yes';
        if (isYes) return homeGoals > 0 && awayGoals > 0;
        return !(homeGoals > 0 && awayGoals > 0);

      case BetType.overUnderGoals:
        final line = _extractLine(desc);
        if (line == null) return false;
        if (desc.contains('over') || desc.contains('>')) {
          return totalGoals > line;
        }
        if (desc.contains('under') || desc.contains('<')) {
          return totalGoals < line;
        }
        return false;

      case BetType.teamTotals:
        final line = _extractLine(desc);
        if (line == null) return false;
        final isHome = desc.contains('home') ||
            desc.contains(fixture.homeTeam.toLowerCase());
        final teamGoals = isHome ? homeGoals : awayGoals;
        if (desc.contains('over')) return teamGoals > line;
        if (desc.contains('under')) return teamGoals < line;
        return false;

      case BetType.correctScore:
        // e.g. "2 - 1" or "2-1"
        final scoreMatch = RegExp(r'(\d+)\s*[-–]\s*(\d+)').firstMatch(desc);
        if (scoreMatch == null) return false;
        final predHome = int.tryParse(scoreMatch.group(1) ?? '') ?? -1;
        final predAway = int.tryParse(scoreMatch.group(2) ?? '') ?? -1;
        return homeGoals == predHome && awayGoals == predAway;

      case BetType.doubleChance:
        if (desc.contains('1x') || desc.contains('home or draw')) {
          return homeGoals >= awayGoals;
        }
        if (desc.contains('x2') || desc.contains('draw or away')) {
          return awayGoals >= homeGoals;
        }
        if (desc.contains('12') || desc.contains('home or away')) {
          return homeGoals != awayGoals;
        }
        return false;

      case BetType.drawNoBet:
        if (desc.contains(fixture.homeTeam.toLowerCase()) || desc.contains('home')) {
          return homeGoals > awayGoals;
        }
        if (desc.contains(fixture.awayTeam.toLowerCase()) || desc.contains('away')) {
          return awayGoals > homeGoals;
        }
        return false;

      case BetType.halfTimeFullTime:
      case BetType.anytimeScorer:
      case BetType.handicap:
      case BetType.bttsYesOverCombo:
      case BetType.bttsYesUnderCombo:
      case BetType.bttsNoOverCombo:
      case BetType.bttsNoUnderCombo:
      case BetType.other:
        // Cannot determine in-play result from score alone.
        return false;
    }
  }

  static double? _extractLine(String desc) {
    final match = RegExp(r'(\d+\.?\d*)').firstMatch(desc);
    if (match == null) return null;
    return double.tryParse(match.group(1) ?? '');
  }
}