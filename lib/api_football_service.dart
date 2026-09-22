import 'dart:convert';
import 'package:http/http.dart' as http;

/// Handles all API Football (v3.football.api-sports.io) calls:
///   - Fixture list fetching (used by gameweek setup)
///   - Bet365 odds for all markets (used by odds caching layer)
///   - Live scores and match events (used by live screen + cloud function)
///   - Team form/H2H data (used by the Scout tab's Poisson model)
///   - Lineups (used by the Line-up tab)
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
    'soccer_italy_serie_a':     135,
    'soccer_spain_la_liga':     140,
    'soccer_france_ligue_one':  61,
    'soccer_germany_bundesliga': 78,
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

  /// A team's most recent completed fixtures, used to derive real W/D/L
  /// results — the /predictions endpoint's own last_5.form field is a
  /// percentage, not a literal result sequence, so it can't be used for
  /// this directly.
  Future<List<ApiFootballFixture>> fetchLastFixtures(int teamId, {int last = 5}) async {
    final data = await _get('/fixtures?team=$teamId&last=$last');
    final fixtures = (data['response'] as List<dynamic>)
        .map((j) => ApiFootballFixture.fromJson(j as Map<String, dynamic>))
        .toList();
    fixtures.sort((a, b) => b.kickoff.compareTo(a.kickoff)); // most recent first
    return fixtures;
  }

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

  Future<ApiFootballFixture?> fetchFixture(int fixtureId) async {
    final data = await _get('/fixtures?id=$fixtureId');
    final response = data['response'] as List<dynamic>;
    if (response.isEmpty) return null;
    return ApiFootballFixture.fromJson(response[0] as Map<String, dynamic>);
  }

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

  Future<List<ApiFootballEvent>> fetchEvents(int fixtureId) async {
    final data = await _get('/fixtures/events?fixture=$fixtureId');
    return (data['response'] as List<dynamic>)
        .map((j) => ApiFootballEvent.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Team form + head-to-head data for the Scout tab. The raw win/draw/
  /// away percentages and other pre-computed fields in this response are
  /// deliberately NOT used for the displayed predictions — those are
  /// computed independently via PoissonPrediction from the last-5 goals
  /// data returned here, per the explicit weighted-Poisson requirement.
  Future<ApiFootballPredictionData?> fetchPredictions(int fixtureId) async {
    final data = await _get('/predictions?fixture=$fixtureId');
    final response = data['response'] as List<dynamic>;
    if (response.isEmpty) return null;
    return ApiFootballPredictionData.fromJson(response[0] as Map<String, dynamic>);
  }

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
  });

  bool get isLive => const {'1H', 'HT', '2H', 'ET', 'BT', 'P'}.contains(statusShort);
  bool get isFinished => const {'FT', 'AET', 'PEN', 'AWD', 'WO'}.contains(statusShort);
  bool get isNotStarted => statusShort == 'NS';
  bool get isUnavailableForSelection =>
      const {'PST', 'CANC', 'ABD', 'SUSP', 'INT', 'TBD'}.contains(statusShort);

  String get statusLabel {
    if (statusShort == 'HT') return 'Half time';
    if (isLive && elapsed != null) return "$elapsed'";
    if (isFinished) return 'Full time';
    final local = kickoff.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = _monthAbbrev[local.month - 1];
    final year = (local.year % 100).toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day $month $year $hour:$minute';
  }

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
      detail: json['detail'] as String,
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
/// /predictions response. goalsForAvg/goalsAgainstAvg feed directly into
/// PoissonPrediction.compute. The exact nested field path for these two
/// numbers is best-effort based on available documentation — not
/// independently verified against a live payload — so double.tryParse
/// is used defensively throughout rather than assuming the path is
/// exactly right; a missing/renamed field falls back to 0.0 rather than
/// crashing. Worth confirming against a real response the first time
/// this runs.
class ApiFootballTeamForm {
  final int teamId;
  final String teamName;
  final String logo;
  final String formString; // e.g. "WWDLW", most recent last per usual convention
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

  /// Last 5 results, most recent first, as single-letter W/D/L codes.
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
/// array — reused fixture-shaped objects, same format as the main
/// /fixtures endpoint.
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

/// A single player's lineup entry. gridRow/gridCol come from
/// API-Football's own "X:Y" grid field per player — row 1 is the
/// goalkeeper, increasing rows moving forward. Used directly to place
/// each player on the pitch diagram without hardcoding formation-shape
/// coordinates for every possible formation string.
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
}

class ApiFootballLineups {
  final ApiFootballTeamLineup? home;
  final ApiFootballTeamLineup? away;
  const ApiFootballLineups({this.home, this.away});
  bool get isAvailable => home != null && away != null;
}