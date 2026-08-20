import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ============================================================
/// ALLOWED BOOKMAKERS
/// ============================================================

const kAllowedBookmakers = {
  'Sky Bet',
  'Bet365',
  'Betfair',
  'Paddy Power',
  'William Hill',
  'Ladbrokes',
  'Coral',
};

/// ============================================================
/// LEAGUE QUERIES
///
/// We intentionally DO NOT send these to the API anymore.
///
/// UK Odds API's league search can return similarly named
/// competitions. We therefore retrieve the events for the
/// requested date window and perform the final league filtering
/// ourselves using the actual league_name returned by the API.
/// ============================================================

const Map<String, String> kUkOddsLeagueQueries = {
  'english premier': 'premier-league',
  'english championship': 'championship',
  'champions league': 'champions-league',
  'la liga': 'la-liga',
  'serie a': 'serie-a',
  'bundesliga': 'bundesliga',
  'ligue 1': 'ligue-1',
};

/// ============================================================
/// UK ODDS SELECTION
/// ============================================================

class UkOddsSelection {
  final String selectionName;
  final String? line;
  final double odds;
  final String bookmakerCode;
  final String bookmakerName;

  UkOddsSelection({
    required this.selectionName,
    this.line,
    required this.odds,
    required this.bookmakerCode,
    required this.bookmakerName,
  });

  factory UkOddsSelection.fromJson(
    Map<String, dynamic> json,
  ) {
    return UkOddsSelection(
      selectionName:
          json['selection_name']?.toString() ?? '',
      line:
          json['line']?.toString(),
      odds:
          (json['odds'] as num?)?.toDouble() ?? 0,
      bookmakerCode:
          json['bookmaker_code']?.toString() ?? '',
      bookmakerName:
          json['bookmaker_name']?.toString() ?? '',
    );
  }
}

/// ============================================================
/// UK ODDS MARKET
/// ============================================================

class UkOddsMarket {
  final String marketName;
  final String marketGroup;
  final List<UkOddsSelection> selections;

  UkOddsMarket({
    required this.marketName,
    required this.marketGroup,
    required this.selections,
  });

  factory UkOddsMarket.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawSelections =
        (json['selections'] as List?) ?? [];

    final allSelections = rawSelections
        .whereType<Map>()
        .map(
          (selection) =>
              UkOddsSelection.fromJson(
            Map<String, dynamic>.from(
              selection,
            ),
          ),
        )
        .toList();

    final filteredSelections =
        allSelections.where(
      (selection) =>
          kAllowedBookmakers.contains(
        selection.bookmakerName,
      ),
    ).toList();

    return UkOddsMarket(
      marketName:
          json['market_name']?.toString() ?? '',
      marketGroup:
          json['market_group']?.toString() ?? '',
      selections:
          filteredSelections,
    );
  }
}

/// ============================================================
/// UK ODDS EVENT
/// ============================================================

class UkOddsEvent {
  final String eventId;
  final String eventTitle;
  final DateTime kickoffUtc;
  final List<UkOddsMarket> markets;

  UkOddsEvent({
    required this.eventId,
    required this.eventTitle,
    required this.kickoffUtc,
    required this.markets,
  });
}

/// ============================================================
/// FIXTURE SUMMARY
/// ============================================================

class UkOddsFixtureSummary {
  final String eventId;
  final String leagueName;
  final String homeTeam;
  final String awayTeam;
  final DateTime kickoffUtc;

  UkOddsFixtureSummary({
    required this.eventId,
    required this.leagueName,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffUtc,
  });

  factory UkOddsFixtureSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return UkOddsFixtureSummary(
      eventId:
          json['event_id']?.toString() ?? '',
      leagueName:
          json['league_name']?.toString() ?? '',
      homeTeam:
          json['home_team']?.toString() ?? '',
      awayTeam:
          json['away_team']?.toString() ?? '',
      kickoffUtc:
          DateTime.parse(
        json['kickoff_utc'].toString(),
      ),
    );
  }
}

/// ============================================================
/// API SERVICE
/// ============================================================

class UkOddsApiService {
  static final UkOddsApiService instance =
      UkOddsApiService._();

  UkOddsApiService._();

  static const String _baseUrl =
      'https://api.ukoddsapi.com/v1';

  static const String _apiKey =
      'uko_live_1d0cf96bd797924397a5ef64eab59e7e';

  /// ==========================================================
  /// NORMALISE
  /// ==========================================================

  static String _normalise(
    String value,
  ) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
  }

  /// ==========================================================
  /// STRICT LEAGUE MATCHING
  ///
  /// This works against the actual `league_name` returned by
  /// UK Odds API.
  ///
  /// It deliberately does NOT use `contains`.
  /// ==========================================================

  static bool _isCorrectLeague(
    String apiLeague,
    String selectedLeague,
  ) {
    final api =
        _normalise(apiLeague);

    final selected =
        _normalise(selectedLeague);

    switch (selected) {
      case 'english premier':
      case 'premier league':
        return api == 'premier league' ||
            api == 'english premier league';

      case 'english championship':
      case 'championship':
        return api == 'english championship' ||
            api == 'championship' ||
            api == 'efl championship';

      case 'champions league':
        return api == 'champions league' ||
            api == 'uefa champions league';

      case 'la liga':
        return api == 'la liga';

      case 'serie a':
        return api == 'serie a' ||
            api == 'italian serie a';

      case 'bundesliga':
        return api == 'bundesliga' ||
            api == 'german bundesliga';

       case 'ligue 1':
        return api == 'ligue 1' ||
            api == 'french ligue 1';

       case 'english league one':
       case 'league one':
        return api == 'english league one';

       case 'english league two':
       case 'league two':
        return api == 'english league two';
      
       case 'fa cup':
        return api == 'fa cup' ||
            api == 'english fa cup';
      
       default:
        return false;
    }
  }

  /// ==========================================================
  /// FETCH FIXTURES
  ///
  /// IMPORTANT:
  /// We deliberately DO NOT send `league` to UK Odds API.
  ///
  /// We retrieve the complete date-window event list and then
  /// perform our own strict filtering.
  ///
  /// This avoids:
  ///
  /// La Liga -> La Liga 2
  /// Serie A -> Serie B
  /// Bundesliga -> Bundesliga 2
  /// Ligue 1 -> Ligue 2
  ///
  /// while still allowing:
  ///
  /// English Championship
  /// ==========================================================

  Future<List<UkOddsFixtureSummary>> fetchFixtures({
    required DateTime from,
    required DateTime to,
    String? league,
  }) async {
    final formatter =
        (DateTime date) =>
            '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';

    final params = <String, String>{
      'from': formatter(from),
      'to': formatter(to),
      'per_page': '200',
    };

    /// IMPORTANT:
    ///
    /// No `league` parameter here.
    ///
    /// We filter locally using the actual league_name returned
    /// by the API.

    final uri =
        Uri.parse(
      '$_baseUrl/football/events',
    ).replace(
      queryParameters: params,
    );

    debugPrint(
      '========== UK ODDS API REQUEST ==========',
    );

    debugPrint(
      'From: ${params['from']}',
    );

    debugPrint(
      'To: ${params['to']}',
    );

    debugPrint(
      'League filtering: LOCAL',
    );

    debugPrint(
      '=========================================',
    );

    final response = await http.get(
      uri,
      headers: {
        'X-Api-Key': _apiKey,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load fixtures: '
        '${response.statusCode} '
        '${response.body}',
      );
    }

    final decoded =
        jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'Unexpected UK Odds API response.',
      );
    }

    final rawEvents =
        decoded['events'];

    final List<dynamic> eventList =
        rawEvents is List
            ? rawEvents
            : <dynamic>[];

    final allEvents = eventList
        .whereType<Map>()
        .map(
          (event) =>
              UkOddsFixtureSummary.fromJson(
            Map<String, dynamic>.from(
              event,
            ),
          ),
        )
        .toList();

    debugPrint(
      'UK Odds API returned '
      '${allEvents.length} total events.',
    );

    /// ========================================================
    /// PRINT ALL LEAGUES
    /// ========================================================

    debugPrint(
      '========== UK ODDS LEAGUES ==========',
    );

    for (final event in allEvents) {
      debugPrint(
        '${event.leagueName} | '
        '${event.homeTeam} vs ${event.awayTeam}',
      );
    }

    debugPrint(
      '=====================================',
    );

    /// ========================================================
    /// NO FILTER
    /// ========================================================

    if (league == null ||
        league.trim().isEmpty) {
      return allEvents;
    }

    final selectedLeague =
        _normalise(league);

    /// ========================================================
    /// FILTER
    /// ========================================================

    final filteredEvents =
        allEvents.where(
      (event) {
        final matches =
            _isCorrectLeague(
          event.leagueName,
          selectedLeague,
        );

        /// Extra Championship debugging.
        if (selectedLeague ==
            'english championship') {
          debugPrint(
            'Championship check: '
            '"${event.leagueName}" '
            '=> $matches',
          );
        }

        return matches;
      },
    ).toList();

    debugPrint(
      '========== UK ODDS FILTER ==========',
    );

    debugPrint(
      'Selected league: $selectedLeague',
    );

    debugPrint(
      'Events before filtering: '
      '${allEvents.length}',
    );

    debugPrint(
      'Events after filtering: '
      '${filteredEvents.length}',
    );

    for (final event in filteredEvents) {
      debugPrint(
        'MATCH: ${event.leagueName} | '
        '${event.homeTeam} vs ${event.awayTeam}',
      );
    }

    debugPrint(
      '===================================',
    );

    return filteredEvents;
  }

  /// ==========================================================
  /// FETCH ODDS
  /// ==========================================================

  Future<UkOddsEvent> fetchOdds({
    required String eventId,
    String package = 'core',
    String? market,
  }) async {
    final params = <String, String>{
      'package': package,
      'odds_format': 'decimal',
      'bookmakers':
          kAllowedBookmakers.join(','),
    };

    if (market != null &&
        market.trim().isNotEmpty) {
      params['market'] = market;
    }

    final uri =
        Uri.parse(
      '$_baseUrl/football/events/$eventId/odds',
    ).replace(
      queryParameters: params,
    );

    debugPrint(
      'Loading odds for event: $eventId',
    );

    final response = await http.get(
      uri,
      headers: {
        'X-Api-Key': _apiKey,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load odds: '
        '${response.statusCode} '
        '${response.body}',
      );
    }

    final decoded =
        jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'Unexpected UK Odds API odds response.',
      );
    }

    final rawMarkets =
        decoded['markets'];

    final List<dynamic> marketsJson =
        rawMarkets is List
            ? rawMarkets
            : <dynamic>[];

    final markets = marketsJson
        .whereType<Map>()
        .map(
          (marketJson) =>
              UkOddsMarket.fromJson(
            Map<String, dynamic>.from(
              marketJson,
            ),
          ),
        )
        .where(
          (market) =>
              market.selections.isNotEmpty,
        )
        .toList();

    return UkOddsEvent(
      eventId:
          decoded['event_id']?.toString() ??
              eventId,
      eventTitle:
          decoded['event_title']?.toString() ??
              '',
      kickoffUtc:
          DateTime.parse(
        decoded['kickoff_utc'].toString(),
      ),
      markets: markets,
    );
  }
}