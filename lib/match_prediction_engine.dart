import 'feature_builder.dart';
import 'expected_goals_engine.dart';
import 'match_data.dart';
import 'match_probabilities.dart';
import 'poisson_engine.dart';
import 'prediction_factors.dart';

class MatchPredictionResult {
  final int fixtureId;
  final int leagueId;
  final int season;
  final String homeTeam;
  final String awayTeam;
  final PredictionFactors factors;
  final ExpectedGoals expectedGoals;
  final MatchProbabilities probabilities;

  const MatchPredictionResult({
    required this.fixtureId,
    required this.leagueId,
    required this.season,
    required this.homeTeam,
    required this.awayTeam,
    required this.factors,
    required this.expectedGoals,
    required this.probabilities,
  });

  Map<String, dynamic> toJson() => {
        'fixtureId': fixtureId,
        'leagueId': leagueId,
        'season': season,
        'homeTeam': homeTeam,
        'awayTeam': awayTeam,
        'factors': factors.toMap(),
        'expectedGoals': expectedGoals.toMap(),
        'probabilities': probabilities.toProbabilities(),
        'percentages': probabilities.toPercentages(),
      };
}

class MatchPredictionEngine {
  final FeatureBuilder featureBuilder;
  final ExpectedGoalsEngine expectedGoalsEngine;
  final PoissonEngine poissonEngine;

  MatchPredictionEngine({
    FeatureBuilder? featureBuilder,
    ExpectedGoalsEngine? expectedGoalsEngine,
    PoissonEngine? poissonEngine,
  })  : featureBuilder = featureBuilder ?? FeatureBuilder(),
        expectedGoalsEngine =
            expectedGoalsEngine ?? ExpectedGoalsEngine(),
        poissonEngine = poissonEngine ?? const PoissonEngine();

  MatchPredictionResult predict(MatchPredictionInput input) {
    final factors = featureBuilder.build(input);
    final xg = expectedGoalsEngine.calculate(input, factors);
    final probabilities = poissonEngine.calculate(xg);

    return MatchPredictionResult(
      fixtureId: input.fixtureId,
      leagueId: input.leagueId,
      season: input.season,
      homeTeam: input.home.name,
      awayTeam: input.away.name,
      factors: factors,
      expectedGoals: xg,
      probabilities: probabilities,
    );
  }
}
