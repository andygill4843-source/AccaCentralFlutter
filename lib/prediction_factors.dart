import 'prediction_weights.dart';

class PredictionFactors {
  /// Every factor is a home-side strength score.
  /// 0.50 = neutral, >0.50 favours home, <0.50 favours away.
  final double recentForm;
  final double homeAway;
  final double goalsXg;
  final double h2h;
  final double injuries;
  final double apiPrediction;

  const PredictionFactors({
    required this.recentForm,
    required this.homeAway,
    required this.goalsXg,
    required this.h2h,
    required this.injuries,
    required this.apiPrediction,
  });

  double get weightedHomeStrength =>
      recentForm * PredictionWeights.recentForm +
      homeAway * PredictionWeights.homeAway +
      goalsXg * PredictionWeights.goalsXg +
      h2h * PredictionWeights.h2h +
      injuries * PredictionWeights.injuries +
      apiPrediction * PredictionWeights.apiPrediction;

  double get weightedAwayStrength => 1.0 - weightedHomeStrength;

  Map<String, double> toMap() => {
        'recentForm': recentForm,
        'homeAway': homeAway,
        'goalsXg': goalsXg,
        'h2h': h2h,
        'injuries': injuries,
        'apiPrediction': apiPrediction,
        'weightedHomeStrength': weightedHomeStrength,
        'weightedAwayStrength': weightedAwayStrength,
      };
}
