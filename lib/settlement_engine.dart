import 'models.dart';
import 'api_football_service.dart';

/// Determines whether a leg is currently winning based on live fixture data.
/// Uses the same logic as livePoller.js — keep both in sync when adding
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
    final pick = leg.pickValue?.toLowerCase().trim();
    final market = leg.marketName?.toLowerCase() ?? '';

    switch (leg.betType) {
      case BetType.matchWinner:
        if (pick != null) {
          if (pick == 'home') return homeGoals > awayGoals;
          if (pick == 'away') return awayGoals > homeGoals;
          if (pick == 'draw') return homeGoals == awayGoals;
          return false;
        }
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
        final valueStr = pick ?? desc;
        final isYes = valueStr.contains('yes') || valueStr == 'btts - yes';
        if (isYes) return homeGoals > 0 && awayGoals > 0;
        return !(homeGoals > 0 && awayGoals > 0);

      case BetType.overUnderGoals:
        final valueStr = pick ?? desc;
        final line = _extractLine(valueStr);
        if (line == null) return false;
        if (valueStr.contains('over') || valueStr.contains('>')) {
          return totalGoals > line;
        }
        if (valueStr.contains('under') || valueStr.contains('<')) {
          return totalGoals < line;
        }
        return false;

      case BetType.teamTotals:
        final valueStr = pick ?? desc;
        final line = _extractLine(valueStr);
        if (line == null) return false;
        final bool isHome;
        if (leg.marketName != null) {
          isHome = market.contains('home');
        } else {
          isHome = desc.contains('home') ||
              desc.contains(fixture.homeTeam.toLowerCase());
        }
        final teamGoals = isHome ? homeGoals : awayGoals;
        if (valueStr.contains('over')) return teamGoals > line;
        if (valueStr.contains('under')) return teamGoals < line;
        return false;

      case BetType.correctScore:
        final valueStr = pick ?? desc;
        final scoreMatch = RegExp(r'(\d+)\s*[-–]\s*(\d+)').firstMatch(valueStr);
        if (scoreMatch == null) return false;
        final predHome = int.tryParse(scoreMatch.group(1) ?? '') ?? -1;
        final predAway = int.tryParse(scoreMatch.group(2) ?? '') ?? -1;
        return homeGoals == predHome && awayGoals == predAway;

      case BetType.doubleChance:
        final valueStr = pick ?? desc;
        if (valueStr.contains('1x') || valueStr.contains('home or draw')) {
          return homeGoals >= awayGoals;
        }
        if (valueStr.contains('x2') || valueStr.contains('draw or away')) {
          return awayGoals >= homeGoals;
        }
        if (valueStr.contains('12') || valueStr.contains('home or away')) {
          return homeGoals != awayGoals;
        }
        return false;

      case BetType.drawNoBet:
        if (pick != null) {
          if (pick == 'home') return homeGoals > awayGoals;
          if (pick == 'away') return awayGoals > homeGoals;
          return false;
        }
        if (desc.contains(fixture.homeTeam.toLowerCase()) || desc.contains('home')) {
          return homeGoals > awayGoals;
        }
        if (desc.contains(fixture.awayTeam.toLowerCase()) || desc.contains('away')) {
          return awayGoals > homeGoals;
        }
        return false;

      // BTTS & Goals combo bets — BOTH halves must be true for a win.
      // The combo market is always fixed at the 2.5 line (see the
      // alternate_totals extraction in odds_orchestrator.dart, which
      // only ever pulls the 2.5 line for these), so no line-parsing is
      // needed here, unlike overUnderGoals/teamTotals above.
      case BetType.bttsYesOverCombo:
        return (homeGoals > 0 && awayGoals > 0) && (totalGoals > 2.5);
      case BetType.bttsYesUnderCombo:
        return (homeGoals > 0 && awayGoals > 0) && (totalGoals < 2.5);
      case BetType.bttsNoOverCombo:
        return !(homeGoals > 0 && awayGoals > 0) && (totalGoals > 2.5);
      case BetType.bttsNoUnderCombo:
        return !(homeGoals > 0 && awayGoals > 0) && (totalGoals < 2.5);

      case BetType.halfTimeFullTime:
      case BetType.anytimeScorer:
      case BetType.handicap:
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