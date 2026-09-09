import 'dart:convert';
import 'package:http/http.dart' as http;

/// Handles all API Football (v3.football.api-sports.io) calls:
///   - Fixture list fetching (used by gameweek setup)
///   - Bet365 odds for all markets (used by odds caching layer)
///   - Live scores and match events (used by live screen + cloud function)
class ApiFootballService {
  static final ApiFootballService instance = ApiFootballService._();
  ApiFootballService._();

  static const String _apiKey = String.fromEnvironment('API_FOOTBALL_KEY');
  static const String _baseUrl = 'https://v3.football.api-sports.io';
  static const int _currentSeason = 2026;
  static const int _bet365Id = 8;

  // Bet type IDs from /odds/bets that we fetch for Bet365.
  static const List<int> _betTypeIds = [
    1,  // Match Winner (1X2)
    8,  // Both Teams Score
    5,  // Goals Over/Under
    10, // Correct Score (Exact Score)
    16, // Total - Home
    17, // Total - Away
    12, // Double Chance
  ];

  // API Football league IDs for each of our 8 supported leagues.
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
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

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
  final DateTime kickoff;
  final String statusShort; // NS, 1H, HT, 2H, ET, FT, AET, PEN
  final String statusLong;
  final int? elapsed;         // minutes played — only present while live
  final int? homeGoals;
  final int? awayGoals;
  final int leagueId;
  final String leagueName;
  final String? venue;

  const ApiFootballFixture({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamId,
    required this.awayTeamId,
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

  String get statusLabel {
    if (statusShort == 'HT') return 'Half time';
    if (isLive && elapsed != null) return "$elapsed'";
    if (isFinished) return 'Full time';
    return 'Kick-off soon';
  }

  String get scoreDisplay =>
      homeGoals != null && awayGoals != null ? '$homeGoals – $awayGoals' : 'vs';

  factory ApiFootballFixture.fromJson(Map<String, dynamic> json) {
    return ApiFootballFixture(
      id: json['fixture']['id'] as int,
      homeTeam: json['teams']['home']['name'] as String,
      awayTeam: json['teams']['away']['name'] as String,
      homeTeamId: json['teams']['home']['id'] as int,
      awayTeamId: json['teams']['away']['id'] as int,
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
  final String type;   // 'Goal', 'Card', 'subst', 'Var'
  final String detail; // 'Normal Goal', 'Yellow Card', 'Red Card', etc.
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

  /// Stable unique ID for this event — used to prevent duplicate notifications.
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