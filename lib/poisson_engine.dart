import 'dart:math' as math;
import 'expected_goals_engine.dart';
import 'match_probabilities.dart';

class PoissonEngine {
  final int maxGoals;

  const PoissonEngine({this.maxGoals = 10});

  MatchProbabilities calculate(ExpectedGoals xg) {
    final home = _distribution(xg.home);
    final away = _distribution(xg.away);

    var homeWin = 0.0;
    var draw = 0.0;
    var awayWin = 0.0;

    var over15 = 0.0;
    var over25 = 0.0;
    var over35 = 0.0;
    var under25 = 0.0;

    var bttsYes = 0.0;
    var homeOver05 = 0.0;
    var homeOver15 = 0.0;
    var awayOver05 = 0.0;
    var awayOver15 = 0.0;

    for (var h = 0; h <= maxGoals; h++) {
      for (var a = 0; a <= maxGoals; a++) {
        final p = home[h] * away[a];
        final total = h + a;

        if (h > a) {
          homeWin += p;
        } else if (h == a) {
          draw += p;
        } else {
          awayWin += p;
        }

        if (total >= 2) over15 += p;
        if (total >= 3) over25 += p;
        if (total >= 4) over35 += p;
        if (total <= 2) under25 += p;

        if (h >= 1 && a >= 1) bttsYes += p;
        if (h >= 1) homeOver05 += p;
        if (h >= 2) homeOver15 += p;
        if (a >= 1) awayOver05 += p;
        if (a >= 2) awayOver15 += p;
      }
    }

    // The grid truncation above can leave a tiny probability mass above
    // maxGoals. Renormalise all scoreline-derived probabilities.
    final mass = _gridMass(home, away);

    return MatchProbabilities(
      homeWin: homeWin / mass,
      draw: draw / mass,
      awayWin: awayWin / mass,
      over15: over15 / mass,
      over25: over25 / mass,
      over35: over35 / mass,
      under25: under25 / mass,
      bttsYes: bttsYes / mass,
      bttsNo: 1.0 - (bttsYes / mass),
      homeOver05: homeOver05 / mass,
      homeOver15: homeOver15 / mass,
      awayOver05: awayOver05 / mass,
      awayOver15: awayOver15 / mass,
    );
  }

  List<double> _distribution(double lambda) {
    final probabilities = List<double>.filled(maxGoals + 1, 0.0);
    probabilities[0] = math.exp(-lambda);

    for (var k = 1; k <= maxGoals; k++) {
      probabilities[k] = probabilities[k - 1] * lambda / k;
    }

    return probabilities;
  }

  double _gridMass(List<double> home, List<double> away) {
    var total = 0.0;
    for (final h in home) {
      for (final a in away) {
        total += h * a;
      }
    }
    return total == 0 ? 1.0 : total;
  }
}
