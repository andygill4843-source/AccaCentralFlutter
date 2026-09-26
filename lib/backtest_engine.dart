import 'match_data.dart';
import 'match_prediction_engine.dart';

class BacktestObservation {
  final MatchPredictionInput input;
  final int actualHomeGoals;
  final int actualAwayGoals;

  const BacktestObservation({
    required this.input,
    required this.actualHomeGoals,
    required this.actualAwayGoals,
  });
}

class BacktestSummary {
  final int matches;
  final double homeWinAccuracy;
  final double drawAccuracy;
  final double awayWinAccuracy;
  final double over25Accuracy;
  final double bttsAccuracy;
  final double averageHomeProbability;
  final double averageAwayProbability;
  final double averageAbsolute1x2Error;

  const BacktestSummary({
    required this.matches,
    required this.homeWinAccuracy,
    required this.drawAccuracy,
    required this.awayWinAccuracy,
    required this.over25Accuracy,
    required this.bttsAccuracy,
    required this.averageHomeProbability,
    required this.averageAwayProbability,
    required this.averageAbsolute1x2Error,
  });
}

class BacktestEngine {
  final MatchPredictionEngine engine;

  BacktestEngine({MatchPredictionEngine? engine})
      : engine = engine ?? MatchPredictionEngine();

  BacktestSummary run(List<BacktestObservation> observations) {
    if (observations.isEmpty) {
      return const BacktestSummary(
        matches: 0,
        homeWinAccuracy: 0,
        drawAccuracy: 0,
        awayWinAccuracy: 0,
        over25Accuracy: 0,
        bttsAccuracy: 0,
        averageHomeProbability: 0,
        averageAwayProbability: 0,
        averageAbsolute1x2Error: 0,
      );
    }

    var homeCorrect = 0;
    var drawCorrect = 0;
    var awayCorrect = 0;
    var over25Correct = 0;
    var bttsCorrect = 0;
    var homeProbSum = 0.0;
    var awayProbSum = 0.0;
    var errorSum = 0.0;

    for (final o in observations) {
      final r = engine.predict(o.input);
      final actualHome = o.actualHomeGoals > o.actualAwayGoals;
      final actualDraw = o.actualHomeGoals == o.actualAwayGoals;
      final actualAway = o.actualHomeGoals < o.actualAwayGoals;
      final actualOver25 = o.actualHomeGoals + o.actualAwayGoals >= 3;
      final actualBtts = o.actualHomeGoals >= 1 && o.actualAwayGoals >= 1;

      if ((r.probabilities.homeWin >= r.probabilities.draw &&
              r.probabilities.homeWin >= r.probabilities.awayWin) ==
          actualHome) {
        homeCorrect++;
      }
      if ((r.probabilities.draw >= r.probabilities.homeWin &&
              r.probabilities.draw >= r.probabilities.awayWin) ==
          actualDraw) {
        drawCorrect++;
      }
      if ((r.probabilities.awayWin >= r.probabilities.homeWin &&
              r.probabilities.awayWin >= r.probabilities.draw) ==
          actualAway) {
        awayCorrect++;
      }

      final predictedOver = r.probabilities.over25 >= 0.5;
      if (predictedOver == actualOver25) over25Correct++;

      final predictedBtts = r.probabilities.bttsYes >= 0.5;
      if (predictedBtts == actualBtts) bttsCorrect++;

      homeProbSum += r.probabilities.homeWin;
      awayProbSum += r.probabilities.awayWin;

      final actualVector = [
        actualHome ? 1.0 : 0.0,
        actualDraw ? 1.0 : 0.0,
        actualAway ? 1.0 : 0.0,
      ];
      final predictedVector = [
        r.probabilities.homeWin,
        r.probabilities.draw,
        r.probabilities.awayWin,
      ];

      for (var i = 0; i < 3; i++) {
        errorSum += (actualVector[i] - predictedVector[i]).abs();
      }
    }

    final n = observations.length.toDouble();

    return BacktestSummary(
      matches: observations.length,
      homeWinAccuracy: homeCorrect / n,
      drawAccuracy: drawCorrect / n,
      awayWinAccuracy: awayCorrect / n,
      over25Accuracy: over25Correct / n,
      bttsAccuracy: bttsCorrect / n,
      averageHomeProbability: homeProbSum / n,
      averageAwayProbability: awayProbSum / n,
      averageAbsolute1x2Error: errorSum / (n * 3.0),
    );
  }
}
