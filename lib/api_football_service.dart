import 'dart:convert';
import 'package:http/http.dart' as http;

/// Handles all API Football (v3.football.api-sports.io) calls:
///   - Fixture list fetching (used by gameweek setup)
///   - Bet365 odds for all markets (used by odds caching layer)
///   - Live scores and match events (used by live screen + cloud function)
///   - Team form/H2H/injuries (used by the prediction engine's Cloud
///     Function — most of these Dart methods are no longer called
///     directly from the Flutter client since the Scout tab moved to
///     server-side computation, but are left here as they're harmless
///     and may still be useful for local testing/reference)
///   - Lineups (used by the Line-up tab, both official + as the data
///     source for PredictedLineupService's historical analysis)
class ApiFootballService {
  static final ApiFootballService instance = ApiFootballService._();
  ApiFootballService._();

  static const String _apiKey = String.fromEnvironment('API_FOOTBALL_KEY');
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const int _currentSeason = 2026;
  static const int _bet365Id = 8;

  static const List<int> _betTypeIds = [1, 8, 5, 10, 16, 17, 12];

  static const Map<String, int> leagueIds = {
    'soccer_epl':               39,
    'soccer_efl_champ':         40,
    'soccer_england_league1':   41,
    'soccer_england_league2':   42,
    'apifootball_only_national_league': 135,
    'soccer_italy_serie_a':     135,
    'soccer_spain_la_liga':     140,
    'soccer_france_ligue_one':  61,
    'soccer_germany_bundesliga': 78,
    'soccer_netherlands_eredivisie': 88,
  };

  Map<String, String> get _headers => {'x-apisports-key': _apiKey};

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('API Football $path → HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FIXTURES
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns all fixtures in the given league within the date window.
  Future<List<ApiFootballFixture>> fetchFixtures({
    required int leagueId,
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await _get(
      '/fixtures'
      '?league=$leagueId'
      '&season=$_currentSeason'
      '&from=${_dateStr(from)}'
      '&to=${_dateStr(to)}',
    );
    return (data['response'] as List<dynamic>)
        .map((j) => ApiFootballFixture.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Fetches a single fixture by its API Football ID.
  Future<ApiFootballFixture?> fetchFixture(int fixtureId) async {
    final data = await _get('/fixtures?id=$fixtureId');
    final response = data['response'] as List<dynamic>;
    if (response.isEmpty) return null;
    return ApiFootballFixture.fromJson(response[0] as Map<String, dynamic>);
  }

  /// A team's most recent completed fixtures, newest first.
  Future<List<ApiFootballFixture>> fetchLastFixtures(int teamId, {int last = 5}) async {
    final data = await _get('/fixtures?team=$teamId&last=$last');
    final fixtures = (data['response'] as List<dynamic>)
        .map((j) => ApiFootballFixture.fromJson(j as Map<String, dynamic>))
        .toList();
    fixtures.sort((a, b) => b.kickoff.compareTo(a.kickoff));
    return fixtures;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ODDS — BET365
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetches Bet365 odds for a fixture across all target bet types.
  /// Returns marketName → list of {value, odd} per outcome.
  /// Each bet type is a separate API call — batched sequentially here since
  /// the API doesn't support multiple bet IDs in one request.
  Future<Map<String, List<ApiFootballOddsValue>>> fetchBet365Odds(
    int fixtureId,
  ) async {
    final result = <String, List<ApiFootballOddsValue>>{};
    for (final betId in _betTypeIds) {
      try {
        final data = await _get(
          '/odds?fixture=$fixtureId&bookmaker=$_bet365Id&bet=$betId',
        );
        final response = data['response'] as List<dynamic>;
        if (response.isEmpty) continue;
        final bookmakers = response[0]['bookmakers'] as List<dynamic>;
        if (bookmakers.isEmpty) continue;
        final bets = bookmakers[0]['bets'] as List<dynamic>;
        if (bets.isEmpty) continue;
        final bet = bets[0];
        final betName = bet['name'] as String;
        result[betName] = (bet['values'] as List<dynamic>)
            .map((v) => ApiFootballOddsValue(
                  value: v['value'] as String,
                  odd: double.tryParse(v['odd'] as String) ?? 0.0,
                ))
            .toList();
      } catch (_) {
        // best-effort — skip this market if the call fails
      }
    }
    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LIVE SCORES
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns all live fixtures across the specified league IDs.
  /// Pass only the leagues that have pending legs — one call, minimal cost.
  Future<List<ApiFootballFixture>> fetchLiveFixtures(
    List<int> apiLeagueIds,
  ) async {
    if (apiLeagueIds.isEmpty) return [];
    final leagueStr = apiLeagueIds.join('-');
    final data = await _get('/fixtures?live=$leagueStr');
    return (data['response'] as List<dynamic>)
        .map((j) => ApiFootballFixture.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EVENTS
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns all match events (goals, cards, subs) for a fixture.
  Future<List<ApiFootballEvent>> fetchEvents(int fixtureId) async {
    final data = await _get('/fixtures/events?fixture=$fixtureId');
    return (data['response'] as List<dynamic>)
        .map((j) => ApiFootballEvent.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PREDICTIONS / FORM / H2H / TEAM STATS / INJURIES
  // (originally used by the client-side Scout tab; now primarily
  // superseded by the Cloud Function's own JS port of this same data
  // fetching — kept here as they're harmless and may still be useful)
  // ══════════════════════════════════════════════════════════════════════════

  /// Team form + head-to-head data. The raw win/draw/away percentages
  /// and other pre-computed fields in this response are deliberately
  /// NOT used for displayed predictions — those are computed
  /// independently via the weighted-Poisson engine.
  Future<ApiFootballPredictionData?> fetchPredictions(int fixtureId) async {
    final data = await _get('/predictions?fixture=$fixtureId');
    final response = data['response'] as List<dynamic>;
    if (response.isEmpty) return null;
    return ApiFootballPredictionData.fromJson(response[0] as Map<String, dynamic>);
  }

  /// Raw /predictions response — used by ApiFootballMapper.predictionFromJson,
  /// which expects the full response envelope.
  Future<Map<String, dynamic>> fetchPredictionsRaw(int fixtureId) async {
    return _get('/predictions?fixture=$fixtureId');
  }

  /// Season + home/away split statistics for a team — feeds VenueRecord
  /// and season goals-per-game figures for the prediction engine.
  Future<ApiFootballTeamStatistics?> fetchTeamStatistics({
    required int teamId,
    required int leagueId,
    int? season,
  }) async {
    final data = await _get('/teams/statistics?league=$leagueId&season=${season ?? _currentSeason}&team=$teamId');
    final response = data['response'];
    if (response is! Map || response.isEmpty) return null;
    return ApiFootballTeamStatistics.fromJson(response as Map<String, dynamic>);
  }

  /// Raw head-to-head fixture list between two teams — kept as raw JSON
  /// so each entry can be fed directly into
  /// ApiFootballMapper.h2hFromFixtureJson, which expects the API's own
  /// fixture shape.
  Future<List<Map<String, dynamic>>> fetchHeadToHeadRaw(
    int homeTeamId,
    int awayTeamId, {
    int last = 5,
  }) async {
    final data = await _get('/fixtures/headtohead?h2h=$homeTeamId-$awayTeamId&last=$last');
    return (data['response'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  /// Injuries and suspensions for a fixture. NOT every league has
  /// coverage for this — check the coverage.injuries flag in
  /// /leagues if this comes back unexpectedly empty for a league you'd
  /// expect data for.
  Future<List<ApiFootballInjury>> fetchInjuries(int fixtureId) async {
    final data = await _get('/injuries?fixture=$fixtureId');
    final response = data['response'] as List<dynamic>? ?? [];
    return response
        .map((e) => ApiFootballInjury.fromJson(e as Map<String, dynamic>))
        .where((i) => i.playerId != 0)
        .toList();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LINEUPS
  // ══════════════════════════════════════════════════════════════════════════

  /// Lineups for a fixture — usually not published by leagues until
  /// close to kickoff. An empty result here is normal for a fixture
  /// that's still some way off, not necessarily an error.
  Future<ApiFootballLineups> fetchLineups(int fixtureId) async {
    final data = await _get('/fixtures/lineups?fixture=$fixtureId');
    final response = (data['response'] as List<dynamic>?) ?? [];
    ApiFootballTeamLineup? home;
    ApiFootballTeamLineup? away;
    for (final entry in response) {
      final lineup = ApiFootballTeamLineup.fromJson(entry as Map<String, dynamic>);
      // First entry in API-Football's response is conventionally the
      // home team, second the away team — assigned positionally rather
      // than by matching team ID, since we don't always have the
      // fixture's home/away IDs handy at the call site.
      if (home == null) {
        home = lineup;
      } else {
        away = lineup;
      }
    }
    return ApiFootballLineups(home: home, away: away);
  }

  String _dateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

class ApiFootballFixture {
  final int id;
  final String homeTeam;
  final String awayTeam;
  final int homeTeamId;
  final int awayTeamId;
  final String homeLogo;
  final String awayLogo;
  final DateTime kickoff;
  final String statusShort;
  final String statusLong;
  final int? elapsed;
  final int? homeGoals;
  final int? awayGoals;
  final int leagueId;
  final String leagueName;
  final String? venue;
  final int season;

  static const List<String> _monthAbbrev = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  const ApiFootballFixture({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamId,
    required this.awayTeamId,
    this.homeLogo = '',
    this.awayLogo = '',
    required this.kickoff,
    required this.statusShort,
    required this.statusLong,
    this.elapsed,
    this.homeGoals,
    this.awayGoals,
    required this.leagueId,
    required this.leagueName,
    this.venue,
    required this.season,
  });

  bool get isLive => const {'1H', 'HT', '2H', 'ET', 'BT', 'P'}.contains(statusShort);
  bool get isFinished => const {'FT', 'AET', 'PEN', 'AWD', 'WO'}.contains(statusShort);
  bool get isNotStarted => statusShort == 'NS';

  /// Statuses meaning the fixture won't go ahead on its scheduled
  /// kickoff as planned — no reliable odds or predictions data exists
  /// for these. Excluded from the pick-selection fixture list entirely
  /// rather than shown with a broken/empty screen behind them.
  bool get isUnavailableForSelection =>
      const {'PST', 'CANC', 'ABD', 'SUSP', 'INT', 'TBD'}.contains(statusShort);

  String get statusLabel {
    if (statusShort == 'HT') return 'Half time';
    if (isLive && elapsed != null) return "$elapsed'";
    if (isFinished) return 'Full time';
    // Not started yet — show the date and time, e.g. "20 Sep 26 20:00",
    // rather than just the time alone, since kickoff could be days away.
    final local = kickoff.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = _monthAbbrev[local.month - 1];
    final year = (local.year % 100).toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day $month $year $hour:$minute';
  }

  /// Short label for the top line of a live status chip — "1ST", "2ND",
  /// "HT", "ET", "PEN", or "FT".
  String get halfLabel {
    switch (statusShort) {
      case '1H': return '1ST';
      case '2H': return '2ND';
      case 'HT': return 'HT';
      case 'ET': return 'ET';
      case 'BT': return 'BREAK';
      case 'P': return 'PENS';
      default: return isFinished ? 'FT' : '';
    }
  }

  String get scoreDisplay =>
      homeGoals != null && awayGoals != null ? '$homeGoals : $awayGoals' : 'vs';

  factory ApiFootballFixture.fromJson(Map<String, dynamic> json) {
    return ApiFootballFixture(
      id: json['fixture']['id'] as int,
      homeTeam: json['teams']['home']['name'] as String,
      awayTeam: json['teams']['away']['name'] as String,
      homeTeamId: json['teams']['home']['id'] as int,
      awayTeamId: json['teams']['away']['id'] as int,
      homeLogo: json['teams']['home']['logo'] as String? ?? '',
      awayLogo: json['teams']['away']['logo'] as String? ?? '',
      kickoff: DateTime.parse(json['fixture']['date'] as String),
      statusShort: json['fixture']['status']['short'] as String,
      statusLong: json['fixture']['status']['long'] as String,
      elapsed: json['fixture']['status']['elapsed'] as int?,
      homeGoals: json['goals']['home'] as int?,
      awayGoals: json['goals']['away'] as int?,
      leagueId: json['league']['id'] as int,
      leagueName: json['league']['name'] as String,
      venue: json['fixture']['venue']?['name'] as String?,
      season: json['league']['season'] as int? ?? DateTime.now().year,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'homeTeamId': homeTeamId,
    'awayTeamId': awayTeamId,
    'homeLogo': homeLogo,
    'awayLogo': awayLogo,
    'kickoff': kickoff.toIso8601String(),
    'statusShort': statusShort,
    'statusLong': statusLong,
    'elapsed': elapsed,
    'homeGoals': homeGoals,
    'awayGoals': awayGoals,
    'leagueId': leagueId,
    'leagueName': leagueName,
    'venue': venue,
    'season': season,
  };
}

class ApiFootballEvent {
  final int elapsed;
  final int? extraTime;
  final String teamName;
  final int teamId;
  final String? playerName;
  final String? assistName;
  final String type;
  final String detail;
  final String? comments;

  const ApiFootballEvent({
    required this.elapsed,
    this.extraTime,
    required this.teamName,
    required this.teamId,
    this.playerName,
    this.assistName,
    required this.type,
    required this.detail,
    this.comments,
  });

  bool get isGoal => type == 'Goal';
  bool get isCard => type == 'Card';
  bool get isSubstitution => type == 'subst';
  bool get isRelevantForNotification => isGoal || isCard;

  String get eventId =>
      '${elapsed}_${extraTime ?? 0}_${teamId}_${type}_${detail.replaceAll(' ', '_')}_${(playerName ?? '').replaceAll(' ', '_')}';

  String get emoji {
    if (isGoal) return '⚽';
    if (detail.contains('Yellow')) return '🟨';
    if (detail.contains('Red')) return '🟥';
    if (isSubstitution) return '🔄';
    return '📋';
  }

  String get timeLabel => extraTime != null ? "$elapsed'+$extraTime" : "$elapsed'";

  String get displayText {
    final player = playerName != null ? ' $playerName' : '';
    return '$timeLabel $emoji $teamName$player — $detail';
  }

  factory ApiFootballEvent.fromJson(Map<String, dynamic> json) {
    return ApiFootballEvent(
      elapsed: json['time']['elapsed'] as int,
      extraTime: json['time']['extra'] as int?,
      teamName: json['team']['name'] as String,
      teamId: json['team']['id'] as int,
      playerName: json['player']?['name'] as String?,
      assistName: json['assist']?['name'] as String?,
      type: json['type'] as String,
      detail: (json['detail'] as String) == 'Normal Goal' ? 'Goal' : json['detail'] as String,
      comments: json['comments'] as String?,
    );
  }
}

class ApiFootballOddsValue {
  final String value;
  final double odd;
  const ApiFootballOddsValue({required this.value, required this.odd});
}

/// One team's recent form, as returned under teams.home/away in the
/// /predictions response. goalsForAvg/goalsAgainstAvg feed the
/// prediction engine. The exact nested field path for these two numbers
/// is best-effort based on available documentation, not independently
/// verified against a live payload — double.tryParse is used
/// defensively throughout rather than assuming the path is exactly
/// right; a missing/renamed field falls back to 0.0 rather than
/// crashing.
class ApiFootballTeamForm {
  final int teamId;
  final String teamName;
  final String logo;
  final String formString;
  final double goalsForAvg;
  final double goalsAgainstAvg;

  const ApiFootballTeamForm({
    required this.teamId,
    required this.teamName,
    required this.logo,
    required this.formString,
    required this.goalsForAvg,
    required this.goalsAgainstAvg,
  });

  List<String> get lastResultsMostRecentFirst =>
      formString.split('').reversed.take(5).toList();

  int get winsInLast5 => lastResultsMostRecentFirst.where((r) => r == 'W').length;

  factory ApiFootballTeamForm.fromJson(Map<String, dynamic> json) {
    final last5 = json['last_5'] as Map<String, dynamic>?;
    double parseAvg(dynamic raw) {
      if (raw == null) return 0.0;
      return double.tryParse(raw.toString()) ?? 0.0;
    }
    return ApiFootballTeamForm(
      teamId: json['id'] as int? ?? 0,
      teamName: json['name'] as String? ?? '',
      logo: json['logo'] as String? ?? '',
      formString: last5?['form'] as String? ?? '',
      goalsForAvg: parseAvg(last5?['goals']?['for']?['average']),
      goalsAgainstAvg: parseAvg(last5?['goals']?['against']?['average']),
    );
  }
}

/// One past head-to-head fixture, from the /predictions response's h2h
/// array — same shape as the main /fixtures endpoint.
class ApiFootballH2HResult {
  final DateTime date;
  final String homeTeam;
  final String awayTeam;
  final int? homeGoals;
  final int? awayGoals;

  const ApiFootballH2HResult({
    required this.date,
    required this.homeTeam,
    required this.awayTeam,
    this.homeGoals,
    this.awayGoals,
  });

  String get scoreLabel =>
      homeGoals != null && awayGoals != null ? '$homeGoals-$awayGoals' : 'vs';

  factory ApiFootballH2HResult.fromJson(Map<String, dynamic> json) {
    return ApiFootballH2HResult(
      date: DateTime.tryParse(json['fixture']?['date'] as String? ?? '') ?? DateTime(2000),
      homeTeam: json['teams']?['home']?['name'] as String? ?? '',
      awayTeam: json['teams']?['away']?['name'] as String? ?? '',
      homeGoals: json['goals']?['home'] as int?,
      awayGoals: json['goals']?['away'] as int?,
    );
  }
}

class ApiFootballPredictionData {
  final ApiFootballTeamForm home;
  final ApiFootballTeamForm away;
  final List<ApiFootballH2HResult> h2h;

  const ApiFootballPredictionData({
    required this.home,
    required this.away,
    required this.h2h,
  });

  factory ApiFootballPredictionData.fromJson(Map<String, dynamic> json) {
    final teams = json['teams'] as Map<String, dynamic>? ?? {};
    final h2hList = (json['h2h'] as List<dynamic>? ?? [])
        .map((e) => ApiFootballH2HResult.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return ApiFootballPredictionData(
      home: ApiFootballTeamForm.fromJson(teams['home'] as Map<String, dynamic>? ?? {}),
      away: ApiFootballTeamForm.fromJson(teams['away'] as Map<String, dynamic>? ?? {}),
      h2h: h2hList.take(5).toList(),
    );
  }
}

/// Season + home/away split stats for a team, from /teams/statistics —
/// a standard, well-documented API-Football endpoint. Field paths below
/// follow its confirmed standard shape.
class ApiFootballTeamStatistics {
  final double seasonGoalsForAvg;
  final double seasonGoalsAgainstAvg;

  final int homePlayed;
  final int homeWins;
  final int homeDraws;
  final int homeLosses;
  final double homeGoalsForAvg;
  final double homeGoalsAgainstAvg;

  final int awayPlayed;
  final int awayWins;
  final int awayDraws;
  final int awayLosses;
  final double awayGoalsForAvg;
  final double awayGoalsAgainstAvg;

  const ApiFootballTeamStatistics({
    required this.seasonGoalsForAvg,
    required this.seasonGoalsAgainstAvg,
    required this.homePlayed,
    required this.homeWins,
    required this.homeDraws,
    required this.homeLosses,
    required this.homeGoalsForAvg,
    required this.homeGoalsAgainstAvg,
    required this.awayPlayed,
    required this.awayWins,
    required this.awayDraws,
    required this.awayLosses,
    required this.awayGoalsForAvg,
    required this.awayGoalsAgainstAvg,
  });

  static double _avg(dynamic raw) => double.tryParse(raw?.toString() ?? '') ?? 0.0;
  static int _asInt(dynamic raw) => raw is int ? raw : (int.tryParse(raw?.toString() ?? '') ?? 0);

  factory ApiFootballTeamStatistics.fromJson(Map<String, dynamic> json) {
    final fixtures = json['fixtures'] as Map<String, dynamic>? ?? {};
    final played = fixtures['played'] as Map<String, dynamic>? ?? {};
    final wins = fixtures['wins'] as Map<String, dynamic>? ?? {};
    final draws = fixtures['draws'] as Map<String, dynamic>? ?? {};
    final loses = fixtures['loses'] as Map<String, dynamic>? ?? {};

    final goals = json['goals'] as Map<String, dynamic>? ?? {};
    final goalsFor = goals['for'] as Map<String, dynamic>? ?? {};
    final goalsAgainst = goals['against'] as Map<String, dynamic>? ?? {};
    final goalsForAvg = goalsFor['average'] as Map<String, dynamic>? ?? {};
    final goalsAgainstAvg = goalsAgainst['average'] as Map<String, dynamic>? ?? {};

    return ApiFootballTeamStatistics(
      seasonGoalsForAvg: _avg(goalsForAvg['total']),
      seasonGoalsAgainstAvg: _avg(goalsAgainstAvg['total']),
      homePlayed: _asInt(played['home']),
      homeWins: _asInt(wins['home']),
      homeDraws: _asInt(draws['home']),
      homeLosses: _asInt(loses['home']),
      homeGoalsForAvg: _avg(goalsForAvg['home']),
      homeGoalsAgainstAvg: _avg(goalsAgainstAvg['home']),
      awayPlayed: _asInt(played['away']),
      awayWins: _asInt(wins['away']),
      awayDraws: _asInt(draws['away']),
      awayLosses: _asInt(loses['away']),
      awayGoalsForAvg: _avg(goalsForAvg['away']),
      awayGoalsAgainstAvg: _avg(goalsAgainstAvg['away']),
    );
  }
}

/// One injury/suspension entry from /injuries. Confirmed field-level
/// shape (type/reason as two distinct fields) per API-Football's own
/// documentation, but the EXACT nested JSON path for player/team wasn't
/// independently verified against a live payload — parsed defensively
/// (checks a nested 'player'/'team' object first, falls back to a flat
/// shape) so a shape mismatch returns fewer/no entries rather than
/// crashing.
class ApiFootballInjury {
  final int playerId;
  final String playerName;
  final String? playerPhoto;
  final int teamId;
  final String type; // "Injury" or "Suspension" per API-Football's docs
  final String? reason; // e.g. "Knee Injury", "Suspended 3 matches"

  const ApiFootballInjury({
    required this.playerId,
    required this.playerName,
    this.playerPhoto,
    required this.teamId,
    required this.type,
    this.reason,
  });

  factory ApiFootballInjury.fromJson(Map<String, dynamic> json) {
    final playerJson = (json['player'] as Map<String, dynamic>?) ?? json;
    final teamJson = (json['team'] as Map<String, dynamic>?) ?? {};
    return ApiFootballInjury(
      playerId: playerJson['id'] as int? ?? 0,
      playerName: playerJson['name'] as String? ?? 'Unknown',
      playerPhoto: playerJson['photo'] as String?,
      teamId: teamJson['id'] as int? ?? 0,
      type: json['type'] as String? ?? playerJson['type'] as String? ?? 'Unavailable',
      reason: json['reason'] as String? ?? playerJson['reason'] as String?,
    );
  }
}

/// A single player's lineup entry. gridRow/gridCol come from
/// API-Football's own "X:Y" grid field per player — row 1 is the
/// goalkeeper, increasing rows moving forward. Used directly to place
/// each player on the pitch diagram without hardcoding formation-shape
/// coordinates for every possible formation string. Also used to
/// represent a PREDICTED player (see PredictedLineupService), with
/// synthetic grid coordinates computed the same way.
class ApiFootballLineupPlayer {
  final int id;
  final String name;
  final String? number;
  final String? position;
  final int gridRow;
  final int gridCol;

  const ApiFootballLineupPlayer({
    required this.id,
    required this.name,
    this.number,
    this.position,
    required this.gridRow,
    required this.gridCol,
  });

  /// Constructed by convention (matching the confirmed team-logo CDN
  /// pattern) — not a field independently confirmed present in the
  /// lineups response itself. Falls back to a generic icon if the image
  /// fails to load, since not every player ID is guaranteed a photo.
  String get photoUrl => 'https://media.api-sports.io/football/players/$id.png';

  factory ApiFootballLineupPlayer.fromJson(Map<String, dynamic> json) {
    // Some API-Football response shapes nest the player object under a
    // 'player' key (e.g. {"player": {...}}), others return it flat —
    // handled defensively here rather than assuming one shape.
    final playerJson = (json['player'] as Map<String, dynamic>?) ?? json;
    final gridStr = playerJson['grid'] as String?;
    var row = 0;
    var col = 0;
    if (gridStr != null && gridStr.contains(':')) {
      final parts = gridStr.split(':');
      row = int.tryParse(parts[0]) ?? 0;
      col = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    }
    return ApiFootballLineupPlayer(
      id: playerJson['id'] as int? ?? 0,
      name: playerJson['name'] as String? ?? 'Unknown',
      number: playerJson['number']?.toString(),
      position: playerJson['pos'] as String?,
      gridRow: row,
      gridCol: col,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'number': number,
    'position': position,
    'gridRow': gridRow,
    'gridCol': gridCol,
  };

  factory ApiFootballLineupPlayer.fromMap(Map<String, dynamic> map) => ApiFootballLineupPlayer(
    id: map['id'] as int,
    name: map['name'] as String,
    number: map['number'] as String?,
    position: map['position'] as String?,
    gridRow: map['gridRow'] as int,
    gridCol: map['gridCol'] as int,
  );
}

class ApiFootballTeamLineup {
  final int teamId;
  final String teamName;
  final String formation;
  final List<ApiFootballLineupPlayer> startXI;
  final List<ApiFootballLineupPlayer> substitutes;
  final String? coachName;

  const ApiFootballTeamLineup({
    required this.teamId,
    required this.teamName,
    required this.formation,
    required this.startXI,
    required this.substitutes,
    this.coachName,
  });

  factory ApiFootballTeamLineup.fromJson(Map<String, dynamic> json) {
    final team = json['team'] as Map<String, dynamic>? ?? {};
    return ApiFootballTeamLineup(
      teamId: team['id'] as int? ?? 0,
      teamName: team['name'] as String? ?? '',
      formation: json['formation'] as String? ?? '',
      startXI: (json['startXI'] as List<dynamic>? ?? [])
          .map((e) => ApiFootballLineupPlayer.fromJson(e as Map<String, dynamic>))
          .where((p) => p.gridRow > 0) // drop any entry with no usable grid position
          .toList(),
      substitutes: (json['substitutes'] as List<dynamic>? ?? [])
          .map((e) => ApiFootballLineupPlayer.fromJson(e as Map<String, dynamic>))
          .toList(),
      coachName: json['coach']?['name'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'teamId': teamId,
    'teamName': teamName,
    'formation': formation,
    'startXI': startXI.map((p) => p.toMap()).toList(),
    'substitutes': substitutes.map((p) => p.toMap()).toList(),
    'coachName': coachName,
  };

  factory ApiFootballTeamLineup.fromMap(Map<String, dynamic> map) => ApiFootballTeamLineup(
    teamId: map['teamId'] as int,
    teamName: map['teamName'] as String,
    formation: map['formation'] as String,
    startXI: (map['startXI'] as List).map((p) => ApiFootballLineupPlayer.fromMap(Map<String, dynamic>.from(p))).toList(),
    substitutes: (map['substitutes'] as List).map((p) => ApiFootballLineupPlayer.fromMap(Map<String, dynamic>.from(p))).toList(),
    coachName: map['coachName'] as String?,
  );
}

class ApiFootballLineups {
  final ApiFootballTeamLineup? home;
  final ApiFootballTeamLineup? away;
  const ApiFootballLineups({this.home, this.away});
  bool get isAvailable => home != null && away != null;
}

class LineupCache {
  final int fixtureId;
  final bool isOfficial;
  final ApiFootballTeamLineup? home;
  final ApiFootballTeamLineup? away;
  final double homeConfidence;
  final double awayConfidence;
  final DateTime computedAt;
  final DateTime? lastOfficialCheckAt;
  final int predictionVersion; // 0 = pre-versioning, always treated as stale

  const LineupCache({
    required this.fixtureId,
    required this.isOfficial,
    this.home,
    this.away,
    this.homeConfidence = 0,
    this.awayConfidence = 0,
    required this.computedAt,
    this.lastOfficialCheckAt,
    this.predictionVersion = 0,
  });

  factory LineupCache.fromMap(Map<String, dynamic> map) => LineupCache(
    fixtureId: map['fixtureId'] as int,
    isOfficial: map['isOfficial'] as bool? ?? false,
    home: map['home'] != null ? ApiFootballTeamLineup.fromMap(Map<String, dynamic>.from(map['home'])) : null,
    away: map['away'] != null ? ApiFootballTeamLineup.fromMap(Map<String, dynamic>.from(map['away'])) : null,
    homeConfidence: (map['homeConfidence'] as num?)?.toDouble() ?? 0,
    awayConfidence: (map['awayConfidence'] as num?)?.toDouble() ?? 0,
    computedAt: (map['computedAt'] as dynamic).toDate(),
    lastOfficialCheckAt: (map['lastOfficialCheckAt'] as dynamic)?.toDate(),
    predictionVersion: map['predictionVersion'] as int? ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'fixtureId': fixtureId,
    'isOfficial': isOfficial,
    'home': home?.toMap(),
    'away': away?.toMap(),
    'homeConfidence': homeConfidence,
    'awayConfidence': awayConfidence,
    'computedAt': computedAt,
    'lastOfficialCheckAt': lastOfficialCheckAt,
    'predictionVersion': predictionVersion,
  };
}