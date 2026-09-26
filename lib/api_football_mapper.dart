import 'match_data.dart';

class ApiFootballMapper {
  const ApiFootballMapper();

  ApiPredictionInput? predictionFromJson(Map<String, dynamic> json) {
    final response = json['response'];
    if (response is! List || response.isEmpty) return null;

    final root = response.first;
    if (root is! Map) return null;

    final percent = root['percent'];
    if (percent is! Map) return null;

    final home = _percent(percent['home']);
    final draw = _percent(percent['draw']);
    final away = _percent(percent['away']);

    if (home == null || draw == null || away == null) return null;

    final goals = root['goals'];
    double? homeGoals;
    double? awayGoals;

    if (goals is Map) {
      homeGoals = _number(goals['home']);
      awayGoals = _number(goals['away']);
    }

    return ApiPredictionInput(
      home: home,
      draw: draw,
      away: away,
      predictedHomeGoals: homeGoals,
      predictedAwayGoals: awayGoals,
    );
  }

  H2HMatch? h2hFromFixtureJson(
    Map<String, dynamic> fixture,
    int homeTeamId,
    int awayTeamId,
  ) {
    final teams = fixture['teams'];
    final goals = fixture['goals'];
    if (teams is! Map || goals is! Map) return null;

    final home = teams['home'];
    final away = teams['away'];
    if (home is! Map || away is! Map) return null;

    final homeId = _int(home['id']);
    final awayId = _int(away['id']);
    final homeGoals = _int(goals['home']);
    final awayGoals = _int(goals['away']);

    if (homeId == null ||
        awayId == null ||
        homeGoals == null ||
        awayGoals == null) {
      return null;
    }

    return H2HMatch(
      homeTeamId: homeId,
      awayTeamId: awayId,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      date: DateTime.tryParse('${fixture['fixture']?['date'] ?? ''}'),
    );
  }

  double? _percent(dynamic value) {
    final n = _number(value);
    if (n == null) return null;
    // API-Football percentages are generally strings such as "55%".
    return (n > 1 ? n / 100.0 : n).clamp(0.0, 1.0).toDouble();
  }

  double? _number(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll('%', '').trim();
      return double.tryParse(cleaned);
    }
    return null;
  }

  int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}
