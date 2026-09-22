import 'dart:math';

/// A weighted Poisson goal-prediction model. Blends each team's own
/// scoring rate with the opponent's conceding weakness to estimate each
/// side's expected goals (lambda), then uses the Poisson distribution
/// to derive win/draw/away, over/under, and BTTS probabilities.
///
/// This is a simplified team-vs-team model — it isn't normalised against
/// full league-wide scoring averages (which would need a separate call
/// per team in the league), so treat these as directional estimates
/// rather than a bookmaker-grade forecast. A small home-advantage
/// multiplier is applied to the home side's expected goals — a common,
/// well-established adjustment in Poisson football models.
class PoissonPrediction {
  final double homeWinPercent;
  final double drawPercent;
  final double awayWinPercent;
  final double over15Percent;
  final double over25Percent;
  final double bttsPercent;
  final double expectedHomeGoals;
  final double expectedAwayGoals;

  const PoissonPrediction({
    required this.homeWinPercent,
    required this.drawPercent,
    required this.awayWinPercent,
    required this.over15Percent,
    required this.over25Percent,
    required this.bttsPercent,
    required this.expectedHomeGoals,
    required this.expectedAwayGoals,
  });

  static const double _homeAdvantage = 1.10;
  static const int _maxGoalsConsidered = 8; // beyond this, probability is negligible

  static double _poissonPmf(int k, double lambda) {
    return exp(-lambda) * pow(lambda, k) / _factorial(k);
  }

  static double _factorial(int n) {
    double result = 1;
    for (var i = 2; i <= n; i++) {
      result *= i;
    }
    return result;
  }

  /// [homeAvgScored]/[homeAvgConceded] and [awayAvgScored]/[awayAvgConceded]
  /// are each team's average goals scored/conceded over their last 5
  /// matches. Expected goals for each side are the average of their own
  /// scoring rate and the opponent's conceding rate — a straightforward,
  /// standard weighting of attack vs. defence.
  factory PoissonPrediction.compute({
    required double homeAvgScored,
    required double homeAvgConceded,
    required double awayAvgScored,
    required double awayAvgConceded,
  }) {
    final lambdaHome = ((homeAvgScored + awayAvgConceded) / 2) * _homeAdvantage;
    final lambdaAway = (awayAvgScored + homeAvgConceded) / 2;

    double homeWin = 0, draw = 0, awayWin = 0;
    double over15 = 0, over25 = 0, btts = 0;

    for (var h = 0; h <= _maxGoalsConsidered; h++) {
      final pHome = _poissonPmf(h, lambdaHome);
      for (var a = 0; a <= _maxGoalsConsidered; a++) {
        final pAway = _poissonPmf(a, lambdaAway);
        final joint = pHome * pAway;

        if (h > a) {
          homeWin += joint;
        } else if (h == a) {
          draw += joint;
        } else {
          awayWin += joint;
        }

        if (h + a >= 2) over15 += joint;
        if (h + a >= 3) over25 += joint;
        if (h >= 1 && a >= 1) btts += joint;
      }
    }

    return PoissonPrediction(
      homeWinPercent: homeWin * 100,
      drawPercent: draw * 100,
      awayWinPercent: awayWin * 100,
      over15Percent: over15 * 100,
      over25Percent: over25 * 100,
      bttsPercent: btts * 100,
      expectedHomeGoals: lambdaHome,
      expectedAwayGoals: lambdaAway,
    );
  }
}