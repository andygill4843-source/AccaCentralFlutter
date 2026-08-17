import 'dart:math';

/// Estimates fair odds for the four BTTS x Over/Under 2.5 combinations,
/// calibrated against the fixture's own real BTTS and Over/Under 2.5
/// market odds. These are genuine statistical estimates, NOT real
/// bookmaker prices — see the class-level notes on estimateAllCombos.
class ComboEstimate {
  final double bttsYesOver25;
  final double bttsYesUnder25;
  final double bttsNoOver25;
  final double bttsNoUnder25;

  ComboEstimate({
    required this.bttsYesOver25,
    required this.bttsYesUnder25,
    required this.bttsNoOver25,
    required this.bttsNoUnder25,
  });
}

class PoissonComboService {
  static const _maxGoals = 8;

  /// Returns fair (no-margin) estimated decimal odds for all four
  /// BTTS/Over-Under combinations, or null if the required market odds
  /// weren't available. Calibrated against the fixture's own real BTTS
  /// and Over/Under 2.5 prices — this correctly captures the correlation
  /// between the two outcomes (unlike naively multiplying two markets'
  /// odds together), because both are derived from one shared goal
  /// distribution fitted to match the real market.
  static ComboEstimate? estimateAllCombos({
    required double over25Odds,
    required double under25Odds,
    required double bttsYesOdds,
    required double bttsNoOdds,
  }) {
    final rawOverProb = 1 / over25Odds;
    final rawUnderProb = 1 / under25Odds;
    final totalsOverround = rawOverProb + rawUnderProb;
    final trueOverProb = rawOverProb / totalsOverround;

    final rawYesProb = 1 / bttsYesOdds;
    final rawNoProb = 1 / bttsNoOdds;
    final bttsOverround = rawYesProb + rawNoProb;
    final trueBttsProb = rawYesProb / bttsOverround;

    double lowT = 0.1, highT = 8.0;
    for (var i = 0; i < 40; i++) {
      final mid = (lowT + highT) / 2;
      if (_poissonOverProbability(mid, 2.5) < trueOverProb) {
        lowT = mid;
      } else {
        highT = mid;
      }
    }
    final lambdaTotal = (lowT + highT) / 2;

    double bttsAt(double f) {
      final lh = f * lambdaTotal;
      final la = (1 - f) * lambdaTotal;
      return 1 - exp(-lh) - exp(-la) + exp(-lambdaTotal);
    }

    final maxAchievableBtts = bttsAt(0.5);
    final targetBtts = trueBttsProb > maxAchievableBtts ? maxAchievableBtts : trueBttsProb;

    double lowF = 0.001, highF = 0.5;
    for (var i = 0; i < 40; i++) {
      final mid = (lowF + highF) / 2;
      if (bttsAt(mid) < targetBtts) {
        lowF = mid;
      } else {
        highF = mid;
      }
    }
    final f = (lowF + highF) / 2;

    final lambdaA = f * lambdaTotal;
    final lambdaB = (1 - f) * lambdaTotal;
    if (lambdaA <= 0 || lambdaB <= 0) return null;

    double bttsYesOverProb = 0, bttsYesUnderProb = 0, bttsNoOverProb = 0, bttsNoUnderProb = 0;
    for (var h = 0; h <= _maxGoals; h++) {
      for (var a = 0; a <= _maxGoals; a++) {
        final p = _poissonPmf(lambdaA, h) * _poissonPmf(lambdaB, a);
        final bothScored = h >= 1 && a >= 1;
        final isOver = (h + a) >= 3;
        if (bothScored && isOver) bttsYesOverProb += p;
        if (bothScored && !isOver) bttsYesUnderProb += p;
        if (!bothScored && isOver) bttsNoOverProb += p;
        if (!bothScored && !isOver) bttsNoUnderProb += p;
      }
    }

    if (bttsYesOverProb <= 0 || bttsYesUnderProb <= 0 || bttsNoOverProb <= 0 || bttsNoUnderProb <= 0) return null;

    return ComboEstimate(
      bttsYesOver25: 1 / bttsYesOverProb,
      bttsYesUnder25: 1 / bttsYesUnderProb,
      bttsNoOver25: 1 / bttsNoOverProb,
      bttsNoUnder25: 1 / bttsNoUnderProb,
    );
  }

  static double _poissonPmf(double lambda, int k) {
    return exp(-lambda) * pow(lambda, k) / _factorial(k);
  }

  static double _factorial(int n) {
    double result = 1;
    for (var i = 2; i <= n; i++) {
      result *= i;
    }
    return result;
  }

  static double _poissonOverProbability(double lambda, double threshold) {
    double cumulative = 0;
    final maxK = threshold.floor();
    for (var k = 0; k <= maxK; k++) {
      cumulative += _poissonPmf(lambda, k);
    }
    return 1 - cumulative;
  }
}