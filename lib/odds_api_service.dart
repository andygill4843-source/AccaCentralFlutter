import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

enum SoccerLeague {
  premierLeague('soccer_epl'),
  championsLeague('soccer_uefa_champs_league'),
  laLiga('soccer_spain_la_liga'),
  serieA('soccer_italy_serie_a'),
  bundesliga('soccer_germany_bundesliga'),
  ligue1('soccer_france_ligue_one');

  final String apiKey;
  const SoccerLeague(this.apiKey);
}

class OddsAPIService {
  static final OddsAPIService instance = OddsAPIService._();
  OddsAPIService._();

  static const _baseUrl = 'https://api.the-odds-api.com/v4';
  static const _apiKey = 'ff585ca95c3be67ff9e85dd16ad3e75d'; // load from a secrets file, never hardcode for real

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
    final json = jsonDecode(response.body);
    return OddsEvent.fromJson(json);
  }

  /// Best-effort: finds this fixture on The Odds API by team name/date match,
  /// and returns a bookmaker name -> deep link map from its h2h market.
  /// UK Odds API (our main odds/market source) doesn't provide links at all,
  /// so this is a secondary lookup used purely for that purpose.
  Future<Map<String, String>> fetchBookmakerLinks({
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoff,
    required SoccerLeague league,
  }) async {
    try {
      final fixtures = await fetchOdds(league: league, markets: ['h2h']);
      debugPrint('The Odds API: fetched ${fixtures.length} fixtures for $league');
      final match = fixtures.where((f) {
        final homeMatches = f.homeTeam.toLowerCase().contains(homeTeam.toLowerCase()) ||
            homeTeam.toLowerCase().contains(f.homeTeam.toLowerCase());
        final awayMatches = f.awayTeam.toLowerCase().contains(awayTeam.toLowerCase()) ||
            awayTeam.toLowerCase().contains(f.awayTeam.toLowerCase());
        return homeMatches && awayMatches;
      }).firstOrNull;

      if (match == null) {
        debugPrint('The Odds API: NO MATCH found for $homeTeam vs $awayTeam');
        return {};
      }
      debugPrint('The Odds API: matched ${match.homeTeam} vs ${match.awayTeam}, bookmakers: ${match.bookmakers.map((b) => b.title).toList()}');

      final Map<String, String> links = {};
      for (final bookmaker in match.bookmakers) {
        final h2hMarket = bookmaker.markets.where((m) => m.key == 'h2h').firstOrNull;
        if (h2hMarket == null) continue;
        final link = h2hMarket.link ?? bookmaker.link;
        if (link != null) links[bookmaker.title] = link;
      }
      debugPrint('The Odds API: resolved ${links.length} links: $links');
      return links;
    } catch (e) {
      debugPrint('The Odds API: fetchBookmakerLinks error: $e');
      return {};
    }
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
      bookmakers: (json['bookmakers'] as List? ?? [])
          .map((b) => OddsBookmaker.fromJson(b))
          .toList(),
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
      markets: (json['markets'] as List? ?? [])
          .map((m) => OddsMarket.fromJson(m))
          .toList(),
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
      outcomes: (json['outcomes'] as List? ?? [])
          .map((o) => OddsOutcome.fromJson(o))
          .toList(),
    );
  }
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