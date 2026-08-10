import 'dart:convert';
import 'package:http/http.dart' as http;

enum SoccerLeague {
  premierLeague('soccer_epl', 'Premier League'),
  championsLeague('soccer_uefa_champs_league', 'Champions League'),
  laLiga('soccer_spain_la_liga', 'La Liga'),
  serieA('soccer_italy_serie_a', 'Serie A'),
  bundesliga('soccer_germany_bundesliga', 'Bundesliga'),
  ligue1('soccer_france_ligue_one', 'Ligue 1');

  final String apiKey;
  final String displayName;
  const SoccerLeague(this.apiKey, this.displayName);
}

class OddsOutcome {
  final String name;
  final double price;
  final double? point;
  final String? link;

  OddsOutcome({required this.name, required this.price, this.point, this.link});

  factory OddsOutcome.fromJson(Map<String, dynamic> json) {
    return OddsOutcome(
      name: json['name'],
      price: (json['price'] as num).toDouble(),
      point: (json['point'] as num?)?.toDouble(),
      link: json['link'],
    );
  }
}

class OddsMarket {
  final String key;
  final String? link;
  final List<OddsOutcome> outcomes;

  OddsMarket({required this.key, this.link, required this.outcomes});

  factory OddsMarket.fromJson(Map<String, dynamic> json) {
    return OddsMarket(
      key: json['key'],
      link: json['link'],
      outcomes: (json['outcomes'] as List).map((o) => OddsOutcome.fromJson(o)).toList(),
    );
  }
}

class OddsBookmaker {
  final String key;
  final String title;
  final String? link;
  final List<OddsMarket> markets;

  OddsBookmaker({required this.key, required this.title, this.link, required this.markets});

  factory OddsBookmaker.fromJson(Map<String, dynamic> json) {
    return OddsBookmaker(
      key: json['key'],
      title: json['title'],
      link: json['link'],
      markets: (json['markets'] as List).map((m) => OddsMarket.fromJson(m)).toList(),
    );
  }
}

class OddsEvent {
  final String id;
  final String sportKey;
  final DateTime commenceTime;
  final String homeTeam;
  final String awayTeam;
  final List<OddsBookmaker> bookmakers;

  OddsEvent({
    required this.id,
    required this.sportKey,
    required this.commenceTime,
    required this.homeTeam,
    required this.awayTeam,
    required this.bookmakers,
  });

  factory OddsEvent.fromJson(Map<String, dynamic> json) {
    return OddsEvent(
      id: json['id'],
      sportKey: json['sport_key'],
      commenceTime: DateTime.parse(json['commence_time']),
      homeTeam: json['home_team'],
      awayTeam: json['away_team'],
      bookmakers: (json['bookmakers'] as List).map((b) => OddsBookmaker.fromJson(b)).toList(),
    );
  }
}

class OddsApiService {
  static final OddsApiService instance = OddsApiService._();
  OddsApiService._();

  static const _baseUrl = 'https://api.the-odds-api.com/v4';
  static const _apiKey = 'ff585ca95c3be67ff9e85dd16ad3e75d'; // load from a secrets file, never hardcode for real

  /// Bulk fixture list — only featured markets (h2h, totals, spreads)
  /// are available on this endpoint.
  Future<List<OddsEvent>> fetchOdds({
    required SoccerLeague league,
    List<String> markets = const ['h2h', 'totals', 'spreads'],
  }) async {
    final uri = Uri.parse('$_baseUrl/sports/${league.apiKey}/odds').replace(queryParameters: {
      'apiKey': _apiKey,
      'regions': 'uk',
      'markets': markets.join(','),
      'oddsFormat': 'decimal',
      'includeLinks': 'true',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load odds: ${response.statusCode}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((e) => OddsEvent.fromJson(e)).toList();
  }

  /// Per-event odds — needed for btts and draw_no_bet, which the bulk
  /// endpoint doesn't support.
  Future<OddsEvent> fetchEventOdds({
    required SoccerLeague league,
    required String eventId,
    List<String> markets = const ['h2h', 'totals', 'spreads', 'btts', 'draw_no_bet'],
  }) async {
    final uri = Uri.parse('$_baseUrl/sports/${league.apiKey}/events/$eventId/odds').replace(queryParameters: {
      'apiKey': _apiKey,
      'regions': 'uk',
      'markets': markets.join(','),
      'oddsFormat': 'decimal',
      'includeLinks': 'true',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load event odds: ${response.statusCode}');
    }
    return OddsEvent.fromJson(jsonDecode(response.body));
  }
}