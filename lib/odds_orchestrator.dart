import 'api_football_service.dart';
import 'odds_api_service.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'poisson_combo_service.dart';

/// Coordinates odds fetching across API Football (Bet365) and The Odds API
/// (Paddy Power, Ladbrokes, William Hill, Sky Bet, Coral), merging results
/// into a single FixtureOddsCache stored in Firestore.
///
/// Call fetchOrCache() — it reads from Firestore first and only hits the
/// APIs when no valid cache exists.
class OddsOrchestrator {
  static final OddsOrchestrator instance = OddsOrchestrator._();
  OddsOrchestrator._();

  // All 6 bookmaker keys in display order for the manager's selection screen.
  static const List<String> allBookmakers = [
    'bet365',
    'paddypower',
    'ladbrokes_uk',
    'williamhill',
    'skybet',
    'coral',
  ];

  static String bookmakerDisplayName(String key) =>
      OddsApiService.bookmakerDisplayNames[key] ?? key;

  /// Returns cached odds for a fixture, fetching and caching if needed.
  /// [leagueKey] is the The Odds API league key (e.g. 'soccer_epl').
  Future<FixtureOddsCache?> fetchOrCache({
    required int apiFootballFixtureId,
    required int apiFootballLeagueId,
    required String leagueKey,
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoff,
  }) async {
    // Check Firestore first.
    final existing = await FirestoreService.instance
        .fetchFixtureOddsCache(apiFootballFixtureId);
    if (existing != null) {
      // ignore: avoid_print
      print('OddsOrchestrator: CACHE HIT fixture=$apiFootballFixtureId bookmakers=${existing.bookmakerOdds.keys.join(', ')}');
      return existing;
    }
    // ignore: avoid_print
    print('OddsOrchestrator: no cache for fixture=$apiFootballFixtureId — fetching fresh');

    // Not cached — fetch from both APIs.
    return _fetchAndCache(
      apiFootballFixtureId: apiFootballFixtureId,
      apiFootballLeagueId: apiFootballLeagueId,
      leagueKey: leagueKey,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoff: kickoff,
    );
  }

  /// Force re-fetches odds regardless of cache — used by the refresh button.
  Future<FixtureOddsCache?> refresh({
    required int apiFootballFixtureId,
    required int apiFootballLeagueId,
    required String leagueKey,
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoff,
  }) => _fetchAndCache(
        apiFootballFixtureId: apiFootballFixtureId,
        apiFootballLeagueId: apiFootballLeagueId,
        leagueKey: leagueKey,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        kickoff: kickoff,
      );

  Future<FixtureOddsCache?> _fetchAndCache({
    required int apiFootballFixtureId,
    required int apiFootballLeagueId,
    required String leagueKey,
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoff,
  }) async {
    // Merged per-bookmaker odds: bookmakerKey → marketName → [NormalisedOddsValue]
    final combined = <String, Map<String, List<NormalisedOddsValue>>>{};

    // ── API Football → Bet365 ────────────────────────────────────────────────
    try {
      final bet365Raw = await ApiFootballService.instance
          .fetchBet365Odds(apiFootballFixtureId);
      if (bet365Raw.isNotEmpty) {
        combined['bet365'] = {
          for (final entry in bet365Raw.entries)
            entry.key: entry.value
                .map((v) => NormalisedOddsValue(value: v.value, odd: v.odd))
                .toList(),
        };
      }
    } catch (_) {
      // best-effort — proceed without Bet365 if the call fails
    }

    // ── The Odds API → 5 bookmakers ──────────────────────────────────────────
    try {
      // Step 1: get the Odds API event ID via /events, using improved
      // team name matching that handles "AFC Wimbledon", "Bromley FC" etc.
      final eventId = await OddsApiService.instance.fetchEventId(
        leagueKey:   leagueKey,
        fixtureDate: kickoff,
        homeTeam:    homeTeam,
        awayTeam:    awayTeam,
      );

      if (eventId != null) {
        // ignore: avoid_print
        print('OddsOrchestrator: found event ID $eventId for $homeTeam vs $awayTeam');
        // Step 2: per-event call for ALL markets in one request.
        final perEventRaw = await OddsApiService.instance.fetchPerEventOdds(
          leagueKey: leagueKey,
          eventId:   eventId,
        );
        // ignore: avoid_print
        print('OddsOrchestrator: per-event returned ${perEventRaw.length} bookmakers: ${perEventRaw.keys.join(', ')}');
        final normalised = OddsApiService.normalisePerEventOdds(
          raw:      perEventRaw,
          homeTeam: homeTeam,
          awayTeam: awayTeam,
        );
        combined.addAll(normalised);
      } else {
        // Fallback: no event ID found — try league-level for h2h + totals.
        final fallback = await OddsApiService.instance.fetchLeagueOddsForFixture(
          leagueKey:   leagueKey,
          fixtureDate: kickoff,
          homeTeam:    homeTeam,
          awayTeam:    awayTeam,
        );
        if (fallback != null) {
          combined.addAll(OddsApiService.normaliseOddsApiFixture(fallback));
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('OddsOrchestrator: The Odds API failed for $leagueKey: $e');
    }
    if (combined.isEmpty) return null;

    // ── Fill missing Goals Over/Under from Alternate Totals ──────────────────
    // Paddy Power, Sky Bet, Coral, Ladbrokes don't offer the standard totals
    // market but DO include alternate_totals which has Over/Under 2.5 lines.
    // Extract the 2.5 line so Goals Over/Under is populated for all bookmakers.
    for (final bmKey in combined.keys.toList()) {
      final bmMarkets = combined[bmKey]!;
      if (bmMarkets.containsKey('Goals Over/Under')) continue;
      final altTotals = bmMarkets['Alternate Totals'];
      if (altTotals == null) continue;
      final over25List  = altTotals.where((v) => v.value == 'Over 2.5').toList();
      final under25List = altTotals.where((v) => v.value == 'Under 2.5').toList();
      final extracted = <NormalisedOddsValue>[
        if (over25List.isNotEmpty)  over25List.first,
        if (under25List.isNotEmpty) under25List.first,
      ];
      if (extracted.isNotEmpty) { combined[bmKey]!['Goals Over/Under'] = extracted; }
    }

    // ── Per-bookmaker combo estimate (simple multiplication) ─────────────────
    // Used only for the manager's combined odds view — each bookmaker's own
    // btts × totals gives a per-bookmaker combo price. These are stored in
    // combined so OddsMerger can include them per-bookmaker.
    for (final bmKey in combined.keys.toList()) {
      final bmMarkets = combined[bmKey]!;
      final bttsMarket = bmMarkets['Both Teams Score'];
      final totalsMarket = bmMarkets['Goals Over/Under'];
      if (bttsMarket == null || totalsMarket == null) continue;

      double? oddFor(List<NormalisedOddsValue> market, String value) {
        try {
          return market.firstWhere((v) => v.value.toLowerCase() == value.toLowerCase()).odd;
        } catch (_) { return null; }
      }

      final bttsYes = oddFor(bttsMarket, 'Yes');
      final bttsNo  = oddFor(bttsMarket, 'No');
      final over25  = oddFor(totalsMarket, 'Over 2.5');
      final under25 = oddFor(totalsMarket, 'Under 2.5');

      final combos = <NormalisedOddsValue>[];
      if (bttsYes != null && over25  != null) { combos.add(NormalisedOddsValue(value: 'BTTS Yes & Over 2.5',  odd: double.parse((bttsYes * over25 ).toStringAsFixed(2)))); }
      if (bttsYes != null && under25 != null) { combos.add(NormalisedOddsValue(value: 'BTTS Yes & Under 2.5', odd: double.parse((bttsYes * under25).toStringAsFixed(2)))); }
      if (bttsNo  != null && over25  != null) { combos.add(NormalisedOddsValue(value: 'BTTS No & Over 2.5',   odd: double.parse((bttsNo  * over25 ).toStringAsFixed(2)))); }
      if (bttsNo  != null && under25 != null) { combos.add(NormalisedOddsValue(value: 'BTTS No & Under 2.5',  odd: double.parse((bttsNo  * under25).toStringAsFixed(2)))); }
      if (combos.isNotEmpty) { combined[bmKey]!['BTTS & Goals (Est.)'] = combos; }
    }

    // ── Merge into best odds ─────────────────────────────────────────────────
    final merged = OddsMerger.merge(combined);

    // ── Serialise for Firestore ───────────────────────────────────────────────
    final bookmakerOddsMap = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final bmEntry in combined.entries) {
      bookmakerOddsMap[bmEntry.key] = {
        for (final mEntry in bmEntry.value.entries)
          mEntry.key: mEntry.value.map((v) => v.toMap()).toList(),
      };
    }
    final bestOddsMap = <String, List<Map<String, dynamic>>>{};
    for (final entry in merged.bestOdds.entries) {
      bestOddsMap[entry.key] = entry.value.map((v) => v.toMap()).toList();
    }

    // ── Override combo best odds with Poisson estimates ───────────────────────
    // The merged best odds for BTTS & Goals (Est.) used simple multiplication.
    // Replace them with Poisson-calibrated estimates, which correctly capture
    // the correlation between BTTS and Over/Under outcomes.
    // Uses the best available over/under 2.5 and BTTS prices across all bookmakers.
    double? bestOdd(String market, String value) {
      final entries = bestOddsMap[market];
      if (entries == null) return null;
      try {
        final match = entries.firstWhere((e) => e['value'] == value);
        return (match['odd'] as num?)?.toDouble();
      } catch (_) { return null; }
    }

    final over25   = bestOdd('Goals Over/Under', 'Over 2.5');
    final under25  = bestOdd('Goals Over/Under', 'Under 2.5');
    final bttsYes  = bestOdd('Both Teams Score', 'Yes');
    final bttsNo   = bestOdd('Both Teams Score', 'No');

    if (over25 != null && under25 != null && bttsYes != null && bttsNo != null) {
      final estimate = PoissonComboService.estimateAllCombos(
        over25Odds:   over25,
        under25Odds:  under25,
        bttsYesOdds:  bttsYes,
        bttsNoOdds:   bttsNo,
      );
      if (estimate != null) {
        // Replace the simple-multiplication combo with Poisson values.
        // bookmakerKey = 'estimate' signals to the UI this is a derived price.
        bestOddsMap['BTTS & Goals (Est.)'] = [
          {'value': 'BTTS Yes & Over 2.5',  'odd': double.parse(estimate.bttsYesOver25.toStringAsFixed(2)),  'bookmakerKey': 'estimate'},
          {'value': 'BTTS Yes & Under 2.5', 'odd': double.parse(estimate.bttsYesUnder25.toStringAsFixed(2)), 'bookmakerKey': 'estimate'},
          {'value': 'BTTS No & Over 2.5',   'odd': double.parse(estimate.bttsNoOver25.toStringAsFixed(2)),   'bookmakerKey': 'estimate'},
          {'value': 'BTTS No & Under 2.5',  'odd': double.parse(estimate.bttsNoUnder25.toStringAsFixed(2)),  'bookmakerKey': 'estimate'},
        ];
      }
    }

    final cache = FixtureOddsCache(
      apiFootballFixtureId: apiFootballFixtureId,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      kickoff: kickoff,
      apiFootballLeagueId: apiFootballLeagueId,
      leagueKey: leagueKey,
      bookmakerOdds: bookmakerOddsMap,
      bestOdds: bestOddsMap,
      fetchedAt: DateTime.now(),
    );

    await FirestoreService.instance.saveFixtureOddsCache(cache);
    // ignore: avoid_print
    print('OddsOrchestrator: cache saved with bookmakers: ${cache.bookmakerOdds.keys.join(', ')}');
    // ignore: avoid_print
    print('OddsOrchestrator: bestOdds markets: ${cache.bestOdds.keys.join(', ')}');
    return cache;
  }

  /// Returns the combined decimal odds for a bookmaker across a list of
  /// fixture caches and their selected market values.
  double combinedOddsForBookmaker(
    String bookmakerKey,
    List<({FixtureOddsCache cache, String marketName, String value})> legs,
  ) {
    double product = 1.0;
    for (final leg in legs) {
      final odd = leg.cache.bookmakerOddFor(bookmakerKey, leg.marketName, leg.value);
      if (odd == null || odd <= 0) return 0.0;
      product *= odd;
    }
    return product;
  }
}