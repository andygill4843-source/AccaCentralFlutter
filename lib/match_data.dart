class TeamMatch {
  final bool isHome;
  final int goalsFor;
  final int goalsAgainst;
  final double? xgFor;
  final double? xgAgainst;

  const TeamMatch({
    required this.isHome,
    required this.goalsFor,
    required this.goalsAgainst,
    this.xgFor,
    this.xgAgainst,
  });
}

class VenueRecord {
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final double goalsForPerGame;
  final double goalsAgainstPerGame;
  final double? xgForPerGame;
  final double? xgAgainstPerGame;

  const VenueRecord({
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsForPerGame,
    required this.goalsAgainstPerGame,
    this.xgForPerGame,
    this.xgAgainstPerGame,
  });

  double get winRate => played == 0 ? 0.5 : wins / played;
  double get drawRate => played == 0 ? 1 / 3 : draws / played;
}

class PlayerAbsence {
  final String playerId;
  final String playerName;
  final String type;
  final String? reason;

  /// 0-1. Optional manually/API-derived importance of the player.
  /// 1.0 = very important starter; 0.1 = fringe player.
  final double importance;

  /// Optional positional impact. 1.0 means the absence mainly affects
  /// the team's ability to score/concede in the modelled way.
  final double attackingImpact;
  final double defensiveImpact;

  const PlayerAbsence({
    required this.playerId,
    required this.playerName,
    required this.type,
    this.reason,
    this.importance = 0.5,
    this.attackingImpact = 0.5,
    this.defensiveImpact = 0.5,
  });
}

class TeamInput {
  final int id;
  final String name;
  final List<TeamMatch> recentMatches;

  final VenueRecord? homeRecord;
  final VenueRecord? awayRecord;

  final double? seasonGoalsForPerGame;
  final double? seasonGoalsAgainstPerGame;
  final double? seasonXgForPerGame;
  final double? seasonXgAgainstPerGame;

  final List<PlayerAbsence> absences;

  const TeamInput({
    required this.id,
    required this.name,
    this.recentMatches = const [],
    this.homeRecord,
    this.awayRecord,
    this.seasonGoalsForPerGame,
    this.seasonGoalsAgainstPerGame,
    this.seasonXgForPerGame,
    this.seasonXgAgainstPerGame,
    this.absences = const [],
  });
}

class H2HMatch {
  final int homeTeamId;
  final int awayTeamId;
  final int homeGoals;
  final int awayGoals;
  final DateTime? date;

  const H2HMatch({
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeGoals,
    required this.awayGoals,
    this.date,
  });
}

class ApiPredictionInput {
  final double home;
  final double draw;
  final double away;
  final double? predictedHomeGoals;
  final double? predictedAwayGoals;

  const ApiPredictionInput({
    required this.home,
    required this.draw,
    required this.away,
    this.predictedHomeGoals,
    this.predictedAwayGoals,
  });
}

class LeagueBaseline {
  final double homeGoalsPerGame;
  final double awayGoalsPerGame;
  final double? homeXgPerGame;
  final double? awayXgPerGame;

  const LeagueBaseline({
    this.homeGoalsPerGame = 1.50,
    this.awayGoalsPerGame = 1.20,
    this.homeXgPerGame,
    this.awayXgPerGame,
  });
}

class MatchPredictionInput {
  final int fixtureId;
  final int leagueId;
  final int season;
  final TeamInput home;
  final TeamInput away;
  final List<H2HMatch> h2h;
  final ApiPredictionInput? apiPrediction;
  final LeagueBaseline leagueBaseline;

  const MatchPredictionInput({
    required this.fixtureId,
    required this.leagueId,
    required this.season,
    required this.home,
    required this.away,
    this.h2h = const [],
    this.apiPrediction,
    this.leagueBaseline = const LeagueBaseline(),
  });
}
