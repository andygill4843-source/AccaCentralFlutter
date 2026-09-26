import 'api_football_service.dart';
import 'match_data.dart';
import 'api_football_mapper.dart';

/// Builds a MatchPredictionInput for MatchPredictionEngine from live
/// API-Football data. This is the one place that knows how to translate
/// this app's API-Football integration into the prediction engine's
/// backend-agnostic input shape — the engine itself has no knowledge of
/// API-Football at all, by design (see the package's own README).
///
/// NOT wired in here, left as a future enhancement:
///   - xG per team — not reliably available across every league/plan,
///     left null; the engine falls back to goals-only signals.
///   - League-specific baseline goals/game — uses the engine's generic
///     default rather than a computed per-league figure from /standings.
///
/// Injuries/suspensions ARE now wired in (via fetchInjuries), but every
/// absence is given the SAME flat importance/attacking/defensive impact
/// (0.5 each) — there's no data-driven way to tell how important a
/// specific missing player is without a further player-stats call
/// (appearances, goals) that isn't integrated here. A team missing its
/// top scorer and a team missing its third-choice goalkeeper are
/// currently weighted identically.
class MatchPredictionDataProvider {
  final ApiFootballService _api;
  final ApiFootballMapper _mapper;

  MatchPredictionDataProvider({
    ApiFootballService? api,
    ApiFootballMapper? mapper,
  })  : _api = api ?? ApiFootballService.instance,
        _mapper = mapper ?? const ApiFootballMapper();

  Future<MatchPredictionInput> build({
    required int fixtureId,
    required int leagueId,
    required int season,
    required int homeTeamId,
    required String homeTeamName,
    required int awayTeamId,
    required String awayTeamName,
    Map<String, dynamic>? predictionsRawOverride,
  }) async {
    final results = await Future.wait([
      _api.fetchLastFixtures(homeTeamId, last: 8),
      _api.fetchLastFixtures(awayTeamId, last: 8),
      _api.fetchTeamStatistics(teamId: homeTeamId, leagueId: leagueId, season: season),
      _api.fetchTeamStatistics(teamId: awayTeamId, leagueId: leagueId, season: season),
      _api.fetchHeadToHeadRaw(homeTeamId, awayTeamId, last: 5),
      predictionsRawOverride != null
          ? Future.value(predictionsRawOverride)
          : _api.fetchPredictionsRaw(fixtureId),
      _api.fetchInjuries(fixtureId),
    ]);

    final homeFixtures = results[0] as List<ApiFootballFixture>;
    final awayFixtures = results[1] as List<ApiFootballFixture>;
    final homeStats = results[2] as ApiFootballTeamStatistics?;
    final awayStats = results[3] as ApiFootballTeamStatistics?;
    final h2hRaw = results[4] as List<Map<String, dynamic>>;
    final predictionRaw = results[5] as Map<String, dynamic>;
    final injuries = results[6] as List<ApiFootballInjury>;

    final homeAbsences = injuries.where((i) => i.teamId == homeTeamId).map(_toPlayerAbsence).toList();
    final awayAbsences = injuries.where((i) => i.teamId == awayTeamId).map(_toPlayerAbsence).toList();

    final home = TeamInput(
      id: homeTeamId,
      name: homeTeamName,
      // fetchLastFixtures returns most-recent-first; FeatureBuilder
      // internally reverses whatever list it's given, expecting
      // OLDEST-first as input so its own reversal recovers "most
      // recent = highest weight". Reversing here is required.
      recentMatches: homeFixtures.reversed.map((f) => _toTeamMatch(f, homeTeamId)).toList(),
      homeRecord: (homeStats == null || homeStats.homePlayed == 0)
          ? null
          : VenueRecord(
              played: homeStats.homePlayed,
              wins: homeStats.homeWins,
              draws: homeStats.homeDraws,
              losses: homeStats.homeLosses,
              goalsForPerGame: homeStats.homeGoalsForAvg,
              goalsAgainstPerGame: homeStats.homeGoalsAgainstAvg,
            ),
      seasonGoalsForPerGame: homeStats?.seasonGoalsForAvg,
      seasonGoalsAgainstPerGame: homeStats?.seasonGoalsAgainstAvg,
      absences: homeAbsences,
    );

    final away = TeamInput(
      id: awayTeamId,
      name: awayTeamName,
      recentMatches: awayFixtures.reversed.map((f) => _toTeamMatch(f, awayTeamId)).toList(),
      awayRecord: (awayStats == null || awayStats.awayPlayed == 0)
          ? null
          : VenueRecord(
              played: awayStats.awayPlayed,
              wins: awayStats.awayWins,
              draws: awayStats.awayDraws,
              losses: awayStats.awayLosses,
              goalsForPerGame: awayStats.awayGoalsForAvg,
              goalsAgainstPerGame: awayStats.awayGoalsAgainstAvg,
            ),
      seasonGoalsForPerGame: awayStats?.seasonGoalsForAvg,
      seasonGoalsAgainstPerGame: awayStats?.seasonGoalsAgainstAvg,
      absences: awayAbsences,
    );

    final h2h = h2hRaw
        .map((json) => _mapper.h2hFromFixtureJson(json, homeTeamId, awayTeamId))
        .whereType<H2HMatch>()
        .toList();

    final apiPrediction = _mapper.predictionFromJson(predictionRaw);

    return MatchPredictionInput(
      fixtureId: fixtureId,
      leagueId: leagueId,
      season: season,
      home: home,
      away: away,
      h2h: h2h,
      apiPrediction: apiPrediction,
    );
  }

  TeamMatch _toTeamMatch(ApiFootballFixture fixture, int teamId) {
    final isHome = fixture.homeTeamId == teamId;
    final goalsFor = isHome ? (fixture.homeGoals ?? 0) : (fixture.awayGoals ?? 0);
    final goalsAgainst = isHome ? (fixture.awayGoals ?? 0) : (fixture.homeGoals ?? 0);
    return TeamMatch(isHome: isHome, goalsFor: goalsFor, goalsAgainst: goalsAgainst);
  }

  PlayerAbsence _toPlayerAbsence(ApiFootballInjury injury) {
    return PlayerAbsence(
      playerId: injury.playerId.toString(),
      playerName: injury.playerName,
      type: injury.type,
      reason: injury.reason,
      importance: 0.5,
      attackingImpact: 0.5,
      defensiveImpact: 0.5,
    );
  }
}