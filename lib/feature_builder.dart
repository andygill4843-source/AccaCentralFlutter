import 'dart:math' as math;
import 'match_data.dart';
import 'prediction_factors.dart';

class FeatureBuilder {
  PredictionFactors build(MatchPredictionInput input) {
    return PredictionFactors(
      recentForm: _recentForm(input.home, input.away),
      homeAway: _homeAway(input.home, input.away),
      goalsXg: _goalsXg(input),
      h2h: _h2h(input),
      injuries: _injuries(input.home, input.away),
      apiPrediction: _apiPrediction(input.apiPrediction),
    );
  }

  double _recentForm(TeamInput home, TeamInput away) {
    final homeScore = _teamFormScore(home.recentMatches);
    final awayScore = _teamFormScore(away.recentMatches);
    return _share(homeScore, awayScore);
  }

  double _teamFormScore(List<TeamMatch> matches) {
    if (matches.isEmpty) return 1.0;

    final ordered = matches.reversed.take(8).toList();
    var weighted = 0.0;
    var weights = 0.0;

    for (var i = 0; i < ordered.length; i++) {
      final m = ordered[i];
      final weight = math.pow(0.85, i).toDouble();
      final result = m.goalsFor > m.goalsAgainst
          ? 1.0
          : m.goalsFor == m.goalsAgainst
              ? 0.5
              : 0.0;

      final gd = (m.goalsFor - m.goalsAgainst).clamp(-3, 3) / 6.0 + 0.5;

      final xgSignal = (m.xgFor != null && m.xgAgainst != null)
          ? _clamp01(
              0.5 + ((m.xgFor! - m.xgAgainst!) / 3.0),
            )
          : 0.5;

      final score = 0.55 * result + 0.25 * gd + 0.20 * xgSignal;
      weighted += score * weight;
      weights += weight;
    }

    return weights == 0 ? 1.0 : weighted / weights;
  }

  double _homeAway(TeamInput home, TeamInput away) {
    final h = home.homeRecord;
    final a = away.awayRecord;

    if (h == null && a == null) return 0.5;

    final hScore = h == null
        ? 0.5
        : 0.55 * h.winRate +
            0.20 * h.drawRate +
            0.25 * _goalDifferenceSignal(
              h.goalsForPerGame,
              h.goalsAgainstPerGame,
            );

    final aScore = a == null
        ? 0.5
        : 0.55 * a.winRate +
            0.20 * a.drawRate +
            0.25 * _goalDifferenceSignal(
              a.goalsForPerGame,
              a.goalsAgainstPerGame,
            );

    return _share(hScore, aScore);
  }

  double _goalsXg(MatchPredictionInput input) {
    final h = input.home;
    final a = input.away;

    final hAttack = _attackScore(
      h.seasonGoalsForPerGame,
      h.seasonXgForPerGame,
      input.leagueBaseline.homeGoalsPerGame,
      input.leagueBaseline.homeXgPerGame,
    );

    final aAttack = _attackScore(
      a.seasonGoalsForPerGame,
      a.seasonXgForPerGame,
      input.leagueBaseline.awayGoalsPerGame,
      input.leagueBaseline.awayXgPerGame,
    );

    final hDefWeakness = _defensiveWeakness(
      h.seasonGoalsAgainstPerGame,
      h.seasonXgAgainstPerGame,
      input.leagueBaseline.awayGoalsPerGame,
      input.leagueBaseline.awayXgPerGame,
    );

    final aDefWeakness = _defensiveWeakness(
      a.seasonGoalsAgainstPerGame,
      a.seasonXgAgainstPerGame,
      input.leagueBaseline.homeGoalsPerGame,
      input.leagueBaseline.homeXgPerGame,
    );

    final homeScore = 0.65 * hAttack + 0.35 * aDefWeakness;
    final awayScore = 0.65 * aAttack + 0.35 * hDefWeakness;

    return _share(homeScore, awayScore);
  }

  double _attackScore(
    double? goals,
    double? xg,
    double leagueGoals,
    double? leagueXg,
  ) {
    final values = <double>[];

    if (goals != null && leagueGoals > 0) {
      values.add(_clamp01(0.5 + ((goals / leagueGoals) - 1.0) * 0.35));
    }

    if (xg != null && leagueXg != null && leagueXg > 0) {
      values.add(_clamp01(0.5 + ((xg / leagueXg) - 1.0) * 0.35));
    }

    if (values.isEmpty) return 0.5;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _defensiveWeakness(
    double? goalsAgainst,
    double? xga,
    double leagueGoals,
    double? leagueXga,
  ) {
    final values = <double>[];

    if (goalsAgainst != null && leagueGoals > 0) {
      values.add(_clamp01(0.5 + (1.0 - goalsAgainst / leagueGoals) * 0.35));
    }

    if (xga != null && leagueXga != null && leagueXga > 0) {
      values.add(_clamp01(0.5 + (1.0 - xga / leagueXga) * 0.35));
    }

    if (values.isEmpty) return 0.5;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _h2h(MatchPredictionInput input) {
    if (input.h2h.isEmpty) return 0.5;

    final matches = input.h2h.reversed.take(5).toList();
    var homeScore = 0.0;
    var weightTotal = 0.0;

    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final weight = math.pow(0.8, i).toDouble();
      final homeWasH2HHome = m.homeTeamId == input.home.id;

      final homeGoals = homeWasH2HHome ? m.homeGoals : m.awayGoals;
      final awayGoals = homeWasH2HHome ? m.awayGoals : m.homeGoals;

      final result = homeGoals > awayGoals
          ? 1.0
          : homeGoals == awayGoals
              ? 0.5
              : 0.0;

      final goalSignal =
          _clamp01(0.5 + ((homeGoals - awayGoals) / 5.0));

      homeScore += (0.7 * result + 0.3 * goalSignal) * weight;
      weightTotal += weight;
    }

    return weightTotal == 0 ? 0.5 : homeScore / weightTotal;
  }

  double _injuries(TeamInput home, TeamInput away) {
    double impact(List<PlayerAbsence> absences) {
      if (absences.isEmpty) return 0.0;
      return absences.fold<double>(
        0.0,
        (sum, p) =>
            sum +
            p.importance *
                (0.55 * p.attackingImpact + 0.45 * p.defensiveImpact),
      );
    }

    final h = impact(home.absences);
    final a = impact(away.absences);

    // Convert absence impact into a bounded relative signal.
    return _share(1.0 / (1.0 + h), 1.0 / (1.0 + a));
  }

  double _apiPrediction(ApiPredictionInput? prediction) {
    if (prediction == null) return 0.5;
    final h = _clamp01(prediction.home);
    final a = _clamp01(prediction.away);
    return _share(h, a);
  }

  double _goalDifferenceSignal(double gf, double ga) {
    return _clamp01(0.5 + ((gf - ga) / 4.0));
  }

  double _share(double home, double away) {
    final total = home + away;
    if (total <= 0) return 0.5;
    return _clamp01(home / total);
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();
}
