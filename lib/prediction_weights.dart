class PredictionWeights {
  static const double recentForm = 0.25;
  static const double homeAway = 0.25;
  static const double goalsXg = 0.20;
  static const double h2h = 0.10;
  static const double injuries = 0.10;
  static const double apiPrediction = 0.10;

  static const double total =
      recentForm + homeAway + goalsXg + h2h + injuries + apiPrediction;

  static void validate() {
    if ((total - 1.0).abs() > 0.000001) {
      throw StateError('Prediction weights must total 1.0. Total: $total');
    }
  }
}
