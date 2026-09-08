import 'dart:convert';
import 'package:http/http.dart' as http;

/// Handles all The Odds API (api.the-odds-api.com) calls.
/// Used for: Paddy Power, Ladbrokes, William Hill, Sky Bet, Coral.
///
/// Flow per fixture:
///   1. fetchEventId() — calls /events to get the Odds API event ID,
///      matching to the API Football fixture by team name.
///   2. fetchPerEventOdds() — calls /events/{id}/odds for ALL markets
///      (h2h, btts, totals, alternate_totals, draw_no_bet) in one call.
///
/// This avoids the league-level /odds endpoint which returns 422 for some
/// leagues when certain markets aren't available.
class OddsApiService {
  static final OddsApiService instance = OddsApiService._();
  OddsApiService._();

  static const String _apiKey  = String.fromEnvironment('ODDS_API_KEY');
  static const String _baseUrl = 'https://api.the-odds-api.com/v4';
  static const String _region  = 'uk';

  // All markets fetched via the per-event endpoint.
  static const String _allMarkets = 'h2h,btts,totals,alternate_totals,draw_no_bet';

  // Only extract these bookmakers from the full UK response.
  static const Set<String> _targetBookmakers = {
    'paddypower',
    'ladbrokes_uk',
    'williamhill',
    'skybet',
    'coral',
  };

  static const Map<String, String> bookmakerDisplayNames = {
    'paddypower':   'Paddy Power',
    'ladbrokes_uk': 'Ladbrokes',
    'williamhill':  'William Hill',
    'skybet':       'Sky Bet',
    'coral':        'Coral',
    'bet365':       'Bet365',
  };

  static const Map<String, String> _marketKeyToName = {
    'h2h':              'Match Winner',
    'btts':             'Both Teams Score',
    'totals':           'Goals Over/Under',
    'alternate_totals': 'Alternate Totals',
    'draw_no_bet':      'Draw No Bet',
  };

  // ══════════════════════════════════════════════════════════════════════════
  // TEAM NAME NORMALISATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Normalises a team name for matching across APIs that use different
  /// naming conventions (e.g. "AFC Wimbledon" vs "Wimbledon",
  /// "Bromley FC" vs "Bromley", "Brighton & Hove Albion" vs "Brighton").
  static String normaliseTeamName(String name) {
    return name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\bafc\s+'), '')        // strip AFC prefix
        .replaceAll(RegExp(r'\s+f\.?c\.?$'), '')    // strip FC/F.C. suffix
        .replaceAll(RegExp(r'&'), 'and')             // & → and
        .replaceAll(RegExp(r"'"), '')                // remove apostrophes
        .replaceAll(RegExp(r'\s+'), ' ')             // collapse whitespace
        .trim();
  }

  /// Returns true when two team names refer to the same club, allowing for
  /// common API naming differences.
  static bool matchTeamName(String a, String b) {
    final na = normaliseTeamName(a);
    final nb = normaliseTeamName(b);
    if (na == nb) return true;
    // One name contains the other — handles "Bromley FC" ↔ "Bromley",
    // "Brighton & Hove Albion" ↔ "Brighton".
    if (na.contains(nb) || nb.contains(na)) return true;
    // Prefix match for abbreviated names — first word must match AND be ≥4 chars.
    final na0 = na.split(' ').first;
    final nb0 = nb.split(' ').first;
    if (na0.length >= 4 && nb0.length >= 4 && na0 == nb0) return true;
    return false;
  }

  static bool matchFixture(String aHome, String aAway, String bHome, String bAway) =>
      matchTeamName(aHome, bHome) && matchTeamName(aAway, bAway);

  // ══════════════════════════════════════════════════════════════════════════
  // EVENTS — get Odds API event ID
  // ══════════════════════════════════════════════════════════════════════════

  /// Finds the Odds API event ID for a fixture by calling /events and
  /// matching team names. Returns null if no match found.
  Future<String?> fetchEventId({
    required String leagueKey,
    required DateTime fixtureDate,
    required String homeTeam,
    required String awayTeam,
  }) async {
    final from = DateTime.utc(
        fixtureDate.toUtc().year,
        fixtureDate.toUtc().month,
        fixtureDate.toUtc().day);
    final to = from.add(const Duration(hours: 23, minutes: 59, seconds: 59));

    final url = Uri.parse(
      '$_baseUrl/sports/$leagueKey/events'
      '?apiKey=$_apiKey'
      '&commenceTimeFrom=${_isoStr(from)}'
      '&commenceTimeTo=${_isoStr(to)}',
    );

    final response = await http.get(url);
    // ignore: avoid_print
    print('OddsApiService.fetchEventId: status=${response.statusCode} league=$leagueKey looking for "$homeTeam vs $awayTeam"');
    if (response.statusCode != 200) return null;

    final List<dynamic> events = jsonDecode(response.body);
    // ignore: avoid_print
    print('OddsApiService.fetchEventId: ${events.length} events returned');
    for (final event in events) {
      final h = event['home_team'] as String;
      final a = event['away_team'] as String;
      if (matchFixture(h, a, homeTeam, awayTeam)) {
        // ignore: avoid_print
        print('OddsApiService.fetchEventId: matched "$h vs $a" → ${event['id']}');
        return event['id'] as String;
      }
    }
    // ignore: avoid_print
    print('OddsApiService.fetchEventId: no match found among: ${events.map((e) => '"${e['home_team']} vs ${e['away_team']}"').join(', ')}');
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PER-EVENT ODDS — all markets in one call
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetches all markets (h2h, btts, totals, alternate_totals, draw_no_bet)
  /// for our 5 target bookmakers from the per-event odds endpoint.
  /// Returns bookmakerKey → marketKey → list of outcomes.
  Future<Map<String, Map<String, List<OddsApiOutcome>>>> fetchPerEventOdds({
    required String leagueKey,
    required String eventId,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/sports/$leagueKey/events/$eventId/odds'
      '?apiKey=$_apiKey'
      '&regions=$_region'
      '&markets=$_allMarkets'
      '&oddsFormat=decimal',
    );

    final response = await http.get(url);
    // ignore: avoid_print
    print('OddsApiService.fetchPerEventOdds: status=${response.statusCode} eventId=$eventId');
    if (response.statusCode != 200) return {};

    final Map<String, dynamic> data = jsonDecode(response.body);
    final result = <String, Map<String, List<OddsApiOutcome>>>{};

    for (final bm in (data['bookmakers'] as List<dynamic>? ?? [])) {
      final bmKey = bm['key'] as String;
      if (!_targetBookmakers.contains(bmKey)) continue;
      final markets = <String, List<OddsApiOutcome>>{};
      for (final market in (bm['markets'] as List<dynamic>? ?? [])) {
        final marketKey = market['key'] as String;
        markets[marketKey] = (market['outcomes'] as List<dynamic>? ?? [])
            .map((o) => OddsApiOutcome(
                  name:  o['name']  as String,
                  price: (o['price'] as num).toDouble(),
                  point: (o['point'] as num?)?.toDouble(),
                ))
            .toList();
      }
      if (markets.isNotEmpty) result[bmKey] = markets;
    }
    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FALLBACK LEAGUE-LEVEL FETCH (h2h + totals only)
  // ══════════════════════════════════════════════════════════════════════════

  /// Used as a fallback when no event ID can be found. Returns h2h and
  /// totals odds from the league-level endpoint, matched by team name.
  Future<OddsApiFixture?> fetchLeagueOddsForFixture({
    required String leagueKey,
    required DateTime fixtureDate,
    required String homeTeam,
    required String awayTeam,
  }) async {
    final from = DateTime.utc(
        fixtureDate.toUtc().year,
        fixtureDate.toUtc().month,
        fixtureDate.toUtc().day);
    final to = from.add(const Duration(hours: 23, minutes: 59, seconds: 59));

    final url = Uri.parse(
      '$_baseUrl/sports/$leagueKey/odds'
      '?apiKey=$_apiKey'
      '&regions=$_region'
      '&markets=h2h,totals'
      '&oddsFormat=decimal'
      '&dateFormat=iso'
      '&commenceTimeFrom=${_isoStr(from)}'
      '&commenceTimeTo=${_isoStr(to)}',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final List<dynamic> data = jsonDecode(response.body);
    for (final j in data) {
      final fixture = OddsApiFixture.fromJson(
        j as Map<String, dynamic>,
        targetBookmakers: _targetBookmakers,
      );
      if (matchFixture(fixture.homeTeam, fixture.awayTeam, homeTeam, awayTeam)) {
        return fixture;
      }
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NORMALISATION — convert to common format for merging with API Football
  // ══════════════════════════════════════════════════════════════════════════

  /// Converts raw per-event odds into the normalised format used by
  /// OddsMerger — home/away outcomes become "Home"/"Away" etc.
  static Map<String, Map<String, List<NormalisedOddsValue>>>
      normalisePerEventOdds({
    required Map<String, Map<String, List<OddsApiOutcome>>> raw,
    required String homeTeam,
    required String awayTeam,
  }) {
    final result = <String, Map<String, List<NormalisedOddsValue>>>{};
    for (final bmEntry in raw.entries) {
      final bmKey = bmEntry.key;
      final markets = <String, List<NormalisedOddsValue>>{};
      for (final mEntry in bmEntry.value.entries) {
        final marketKey  = mEntry.key;
        final marketName = _marketKeyToName[marketKey] ?? marketKey;
        markets[marketName] = mEntry.value.map((o) {
          String value = o.name;
          if (marketKey == 'h2h') {
            if (matchTeamName(value, homeTeam)) { value = 'Home'; }
            else if (matchTeamName(value, awayTeam)) { value = 'Away'; }
            else { value = 'Draw'; }
          } else if (marketKey == 'draw_no_bet') {
            if (matchTeamName(value, homeTeam)) { value = 'Home'; }
            else if (matchTeamName(value, awayTeam)) { value = 'Away'; }
          } else if ((marketKey == 'totals' || marketKey == 'alternate_totals') &&
              o.point != null) {
            final pt = o.point!;
            final ptStr = pt == pt.roundToDouble()
                ? pt.toInt().toString()
                : pt.toString();
            value = '${o.name} $ptStr';
          }
          return NormalisedOddsValue(value: value, odd: o.price);
        }).toList();
      }
      result[bmKey] = markets;
    }
    return result;
  }

  /// Normalises a league-level OddsApiFixture (fallback path).
  static Map<String, Map<String, List<NormalisedOddsValue>>>
      normaliseOddsApiFixture(OddsApiFixture fixture) {
    final raw = <String, Map<String, List<OddsApiOutcome>>>{};
    for (final bmEntry in fixture.bookmakerOdds.entries) {
      raw[bmEntry.key] = bmEntry.value;
    }
    return normalisePerEventOdds(
      raw: raw,
      homeTeam: fixture.homeTeam,
      awayTeam: fixture.awayTeam,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  static String _isoStr(DateTime dt) =>
      dt.toIso8601String().replaceAll('.000000', '').replaceAll('.000', '');
}

// ════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

class OddsApiFixture {
  final String oddsApiId;
  final String homeTeam;
  final String awayTeam;
  final DateTime kickoff;
  final String sportKey;
  final Map<String, Map<String, List<OddsApiOutcome>>> bookmakerOdds;

  const OddsApiFixture({
    required this.oddsApiId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoff,
    required this.sportKey,
    required this.bookmakerOdds,
  });

  factory OddsApiFixture.fromJson(
    Map<String, dynamic> json, {
    Set<String>? targetBookmakers,
  }) {
    final bookmakerOdds = <String, Map<String, List<OddsApiOutcome>>>{};
    for (final bm in (json['bookmakers'] as List<dynamic>? ?? [])) {
      final bmKey = bm['key'] as String;
      if (targetBookmakers != null && !targetBookmakers.contains(bmKey)) {
        continue;
      }
      final markets = <String, List<OddsApiOutcome>>{};
      for (final market in (bm['markets'] as List<dynamic>? ?? [])) {
        final marketKey = market['key'] as String;
        markets[marketKey] = (market['outcomes'] as List<dynamic>? ?? [])
            .map((o) => OddsApiOutcome(
                  name:  o['name']  as String,
                  price: (o['price'] as num).toDouble(),
                  point: (o['point'] as num?)?.toDouble(),
                ))
            .toList();
      }
      bookmakerOdds[bmKey] = markets;
    }
    return OddsApiFixture(
      oddsApiId:    json['id']            as String,
      homeTeam:     json['home_team']     as String,
      awayTeam:     json['away_team']     as String,
      kickoff:      DateTime.parse(json['commence_time'] as String),
      sportKey:     json['sport_key']     as String,
      bookmakerOdds: bookmakerOdds,
    );
  }
}

class OddsApiOutcome {
  final String name;
  final double price;
  final double? point;

  const OddsApiOutcome({
    required this.name,
    required this.price,
    this.point,
  });
}

class NormalisedOddsValue {
  final String value;
  final double odd;

  const NormalisedOddsValue({required this.value, required this.odd});

  Map<String, dynamic> toMap() => {'value': value, 'odd': odd};

  factory NormalisedOddsValue.fromMap(Map<String, dynamic> map) =>
      NormalisedOddsValue(
        value: map['value'] as String,
        odd:   (map['odd'] as num).toDouble(),
      );
}

class BestOddsValue {
  final String value;
  final double odd;
  final String bookmakerKey;

  const BestOddsValue({
    required this.value,
    required this.odd,
    required this.bookmakerKey,
  });

  String get bookmakerName =>
      OddsApiService.bookmakerDisplayNames[bookmakerKey] ?? bookmakerKey;

  Map<String, dynamic> toMap() => {
    'value':        value,
    'odd':          odd,
    'bookmakerKey': bookmakerKey,
  };

  factory BestOddsValue.fromMap(Map<String, dynamic> map) => BestOddsValue(
    value:        map['value']        as String,
    odd:          (map['odd'] as num).toDouble(),
    bookmakerKey: map['bookmakerKey'] as String,
  );
}

class OddsMerger {
  static ({
    Map<String, List<BestOddsValue>> bestOdds,
    Map<String, Map<String, List<NormalisedOddsValue>>> allBookmakerOdds,
  }) merge(Map<String, Map<String, List<NormalisedOddsValue>>> combined) {
    final bestOdds  = <String, List<BestOddsValue>>{};
    final allMarkets = <String>{};
    for (final bmOdds in combined.values) {
      allMarkets.addAll(bmOdds.keys);
    }
    for (final market in allMarkets) {
      final byValue = <String, BestOddsValue>{};
      for (final bmEntry in combined.entries) {
        final bmKey     = bmEntry.key;
        final marketOdds = bmEntry.value[market];
        if (marketOdds == null) continue;
        for (final oddsVal in marketOdds) {
          final existing = byValue[oddsVal.value];
          if (existing == null || oddsVal.odd > existing.odd) {
            byValue[oddsVal.value] = BestOddsValue(
              value:        oddsVal.value,
              odd:          oddsVal.odd,
              bookmakerKey: bmKey,
            );
          }
        }
      }
      if (byValue.isNotEmpty) bestOdds[market] = byValue.values.toList();
    }
    return (bestOdds: bestOdds, allBookmakerOdds: combined);
  }
}