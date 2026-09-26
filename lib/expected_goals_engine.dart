import 'match_data.dart';
import 'prediction_factors.dart';

class ExpectedGoals {
  final double home;
  final double away;

  const ExpectedGoals({
    required this.home,
    required this.away,
  });

  Map<String, double> toMap() => {
        'home': home,
        'away': away,
      };
}

class ExpectedGoalsEngine {
  ExpectedGoals calculate(
    MatchPredictionInput input,
    PredictionFactors factors,
  ) {
    final baselineHome = input.leagueBaseline.homeGoalsPerGame;
    final baselineAway = input.leagueBaseline.awayGoalsPerGame;

    final homeAttack = _attackMultiplier(
      input.home.seasonGoalsForPerGame,
      input.home.seasonXgForPerGame,
      baselineHome,
      input.leagueBaseline.homeXgPerGame,
    );

    final awayAttack = _attackMultiplier(
      input.away.seasonGoalsForPerGame,
      input.away.seasonXgForPerGame,
      baselineAway,
      input.leagueBaseline.awayXgPerGame,
    );

    final homeDef = _defenceMultiplier(
      input.home.seasonGoalsAgainstPerGame,
      input.home.seasonXgAgainstPerGame,
      baselineAway,
      input.leagueBaseline.awayXgPerGame,
    );

    final awayDef = _defenceMultiplier(
      input.away.seasonGoalsAgainstPerGame,
      input.away.seasonXgAgainstPerGame,
      baselineHome,
      input.leagueBaseline.homeXgPerGame,
    );

    var homeLambda = baselineHome * homeAttack * awayDef;
    var awayLambda = baselineAway * awayAttack * homeDef;

    // The weighted factor score is used as a modest adjustment rather than
    // being treated as a literal win probability.
    final homeStrength = factors.weightedHomeStrength;
    final homeAdjustment = 1.0 + ((homeStrength - 0.5) * 0.55);
    final awayAdjustment = 1.0 - ((homeStrength - 0.5) * 0.45);

    homeLambda *= homeAdjustment;
    awayLambda *= awayAdjustment;

    // If API-Football supplies predicted goals, blend them lightly.
    final api = input.apiPrediction;
    if (api?.predictedHomeGoals != null) {
      homeLambda = 0.90 * homeLambda + 0.10 * api!.predictedHomeGoals!;
    }
    if (api?.predictedAwayGoals != null) {
      awayLambda = 0.90 * awayLambda + 0.10 * api!.predictedAwayGoals!;
    }

    return ExpectedGoals(
      home: homeLambda.clamp(0.05, 5.0).toDouble(),
      away: awayLambda.clamp(0.05, 5.0).toDouble(),
    );
  }

  double _attackMultiplier(
    double? goals,
    double? xg,
    double baselineGoals,
    double? baselineXg,
  ) {
    final signals = <double>[];

    if (goals != null && baselineGoals > 0) {
      signals.add((goals / baselineGoals).clamp(0.50, 1.80).toDouble());
    }

    if (xg != null && baselineXg != null && baselineXg > 0) {
      signals.add((xg / baselineXg).clamp(0.50, 1.80).toDouble());
    }

    if (signals.isEmpty) return 1.0;
    return signals.reduce((a, b) => a + b) / signals.length;
  }

  double _defenceMultiplier(
    double? goalsAgainst,
    double? xga,
    double opponentBaselineGoals,
    double? opponentBaselineXg,
  ) {
    final signals = <double>[];

    if (goalsAgainst != null && opponentBaselineGoals > 0) {
      signals.add(
        (goalsAgainst / opponentBaselineGoals)
            .clamp(0.55, 1.75)
            .toDouble(),
      );
    }

    if (xga != null && opponentBaselineXg != null && opponentBaselineXg > 0) {
      signals.add(
        (xga / opponentBaselineXg).clamp(0.55, 1.75).toDouble(),
      );
    }

    if (signals.isEmpty) return 1.0;
    return signals.reduce((a, b) => a + b) / signals.length;
  }
}
