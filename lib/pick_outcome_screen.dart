import 'package:flutter/material.dart';
import 'uk_odds_api_service.dart';
import 'odds_api_service.dart';
import 'poisson_combo_service.dart';
import 'firestore_service.dart';
import 'fixture_matching_service.dart';
import 'models.dart';
import 'main.dart';
import 'odds_format.dart';

class _PricedOutcome {
  final String name;
  final String? line;
  final double bestPrice;
  final String bestBookmaker;
  final Map<String, double> allPrices;

  _PricedOutcome({
    required this.name,
    this.line,
    required this.bestPrice,
    required this.bestBookmaker,
    required this.allPrices,
  });
}

class PickOutcomeScreen extends StatefulWidget {
  final UkOddsFixtureSummary fixture;
  final String gameWeekId;
  final String memberId;
  final String teamId;
  final SoccerLeague? theOddsApiLeague;

  const PickOutcomeScreen({
    super.key,
    required this.fixture,
    required this.gameWeekId,
    required this.memberId,
    required this.teamId,
    this.theOddsApiLeague,
  });

  @override
  State<PickOutcomeScreen> createState() => _PickOutcomeScreenState();
}

class _PickOutcomeScreenState extends State<PickOutcomeScreen> {
  UkOddsEvent? fullEvent;
  Map<String, String> bookmakerLinks = {};
  bool isLoading = true;
  bool isSubmitting = false;
  String? errorMessage;

  final Map<String, bool> _expanded = {};
  int? _selectedHomeScore;
  int? _selectedAwayScore;

  @override
  void initState() {
    super.initState();
    loadOdds();
  }

  Future<void> loadOdds() async {
    try {
      final event = await UkOddsApiService.instance.fetchOdds(
        eventId: widget.fixture.eventId,
        package: 'core',
      );
      if (!mounted) return;
      setState(() {
        fullEvent = event;
        isLoading = false;
      });

      if (widget.theOddsApiLeague != null) {
        try {
          final links = await OddsAPIService.instance.fetchBookmakerLinks(
            homeTeam: widget.fixture.homeTeam,
            awayTeam: widget.fixture.awayTeam,
            kickoff: widget.fixture.kickoffUtc,
            league: widget.theOddsApiLeague!,
          );
          if (mounted) setState(() => bookmakerLinks = links);
        } catch (_) {
          // Links are supplementary — never block the main odds display.
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = "Couldn't load odds for this fixture: $e";
        isLoading = false;
      });
    }
  }

  BetType _mapBetType(String marketName) {
    final n = marketName.toLowerCase();
    if (n.contains('match result') ||
        n.contains('1x2') ||
        n.contains('match winner') ||
        n.contains('win market')) return BetType.matchWinner;
    if (n == 'both teams to score' || n == 'btts') return BetType.bothTeamsToScore;
    if (n.contains('total home goals') || n.contains('total away goals')) return BetType.teamTotals;
    if (n.contains('total goals over/under') || (n.contains('total') && n.contains('over/under'))) return BetType.overUnderGoals;
    if (n.contains('draw no bet')) return BetType.drawNoBet;
    if (n.contains('handicap')) return BetType.handicap;
    if (n.contains('correct score')) return BetType.correctScore;
    if (n.contains('double chance')) return BetType.doubleChance;
    if (n.contains('half time') || n.contains('halftime') || n.contains('half/full')) return BetType.halfTimeFullTime;
    if (n.contains('goalscorer') || n.contains('anytime')) return BetType.anytimeScorer;
    return BetType.other;
  }

  int _marketPriority(String marketName) {
    final n = marketName.toLowerCase();
    if (n.contains('match result') ||
        n.contains('1x2') ||
        n.contains('match winner') ||
        n.contains('win market')) return 0;
    if (n.contains('total goals over/under')) return 1;
    if (n == 'both teams to score' || n == 'btts') return 2;
    if (n.contains('total home goals') || n.contains('total away goals')) return 3;
    if (n.contains('handicap')) return 4;
    return 99;
  }

  List<UkOddsMarket> _orderedMarkets() {
    if (fullEvent == null) return [];
    final indexed = fullEvent!.markets.asMap().entries.toList();
    indexed.sort((a, b) {
      final pa = _marketPriority(a.value.marketName);
      final pb = _marketPriority(b.value.marketName);
      if (pa != pb) return pa.compareTo(pb);
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  List<_PricedOutcome> _bestOutcomesFor(UkOddsMarket market) {
    final Map<String, Map<String, double>> prices = {};
    final Map<String, (String, String?)> meta = {};

    for (final selection in market.selections) {
      final groupKey = '${selection.selectionName}|${selection.line ?? ''}';
      meta[groupKey] = (selection.selectionName, selection.line);
      prices.putIfAbsent(groupKey, () => {})[selection.bookmakerName] = selection.odds;
    }

    final outcomes = meta.keys.map((groupKey) {
      final priceMap = prices[groupKey]!;
      if (priceMap.isEmpty) {
        final m = meta[groupKey]!;
        return _PricedOutcome(name: m.$1, line: m.$2, bestPrice: 0, bestBookmaker: '', allPrices: const {});
      }
      final best = priceMap.entries.reduce((a, b) => a.value > b.value ? a : b);
      final m = meta[groupKey]!;
      return _PricedOutcome(name: m.$1, line: m.$2, bestPrice: best.value, bestBookmaker: best.key, allPrices: priceMap);
    }).where((o) => o.allPrices.isNotEmpty).toList();

    outcomes.sort((a, b) => a.name.compareTo(b.name));
    return outcomes;
  }

  Future<void> submit(_PricedOutcome outcome, BetType betType) async {
    if (isSubmitting) return;
    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });
    final pickLabel = (outcome.line != null && !outcome.name.toLowerCase().contains(outcome.line!.toLowerCase()))
        ? '${outcome.name} ${outcome.line}'
        : outcome.name;
    final selectionDescription = '$pickLabel — ${widget.fixture.homeTeam} vs ${widget.fixture.awayTeam}';
    try {
      final sportmonksId = await FixtureMatchingService.resolveSportmonksFixtureId(
        homeTeam: widget.fixture.homeTeam,
        awayTeam: widget.fixture.awayTeam,
        kickoff: widget.fixture.kickoffUtc,
      );

      final leg = AccumulatorLeg(
        id: null,
        gameWeekId: widget.gameWeekId,
        teamId: widget.teamId,
        memberId: widget.memberId,
        fixtureId: widget.fixture.eventId,
        fixtureDescription: '${widget.fixture.homeTeam} vs ${widget.fixture.awayTeam}',
        kickoff: widget.fixture.kickoffUtc,
        betType: betType,
        selectionDescription: selectionDescription,
        decimalOddsAtSelection: outcome.bestPrice,
        bookmaker: outcome.bestBookmaker,
        bookmakerPrices: outcome.allPrices,
        bookmakerLinks: bookmakerLinks.isEmpty ? null : bookmakerLinks,
        sportmonksFixtureId: sportmonksId,
        outcome: LegOutcome.pending,
        submittedAt: DateTime.now(),
      );

      await FirestoreService.instance.submitLeg(leg);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isSubmitting = false;
        errorMessage = e.toString();
      });
    }
  }

  Future<void> submitCombo(
    String label,
    BetType betType,
    Map<String, ComboEstimate> perBookmaker,
    double Function(ComboEstimate) selector,
  ) async {
    if (isSubmitting) return;
    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });

    final priceMap = {for (final e in perBookmaker.entries) e.key: selector(e.value)};
    final best = priceMap.entries.reduce((a, b) => a.value > b.value ? a : b);

    try {
      final sportmonksId = await FixtureMatchingService.resolveSportmonksFixtureId(
        homeTeam: widget.fixture.homeTeam,
        awayTeam: widget.fixture.awayTeam,
        kickoff: widget.fixture.kickoffUtc,
      );

      final leg = AccumulatorLeg(
        id: null,
        gameWeekId: widget.gameWeekId,
        teamId: widget.teamId,
        memberId: widget.memberId,
        fixtureId: widget.fixture.eventId,
        fixtureDescription: '${widget.fixture.homeTeam} vs ${widget.fixture.awayTeam}',
        kickoff: widget.fixture.kickoffUtc,
        betType: betType,
        selectionDescription: '$label (Estimate) — ${widget.fixture.homeTeam} vs ${widget.fixture.awayTeam}',
        decimalOddsAtSelection: best.value,
        bookmaker: best.key,
        bookmakerPrices: priceMap,
        bookmakerLinks: bookmakerLinks.isEmpty ? null : bookmakerLinks,
        sportmonksFixtureId: sportmonksId,
        outcome: LegOutcome.pending,
        submittedAt: DateTime.now(),
      );

      await FirestoreService.instance.submitLeg(leg);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isSubmitting = false;
        errorMessage = e.toString();
      });
    }
  }

  Map<String, ComboEstimate> _computeCombosPerBookmaker() {
    if (fullEvent == null) return {};

    UkOddsMarket? bttsMarket;
    UkOddsMarket? totalsMarket;
    for (final market in fullEvent!.markets) {
      final betType = _mapBetType(market.marketName);
      if (betType == BetType.bothTeamsToScore) bttsMarket = market;
      if (betType == BetType.overUnderGoals) totalsMarket = market;
    }
    if (bttsMarket == null || totalsMarket == null) return {};

    final Map<String, double> bttsYes = {};
    final Map<String, double> bttsNo = {};
    for (final s in bttsMarket.selections) {
      final n = s.selectionName.toLowerCase();
      if (n.contains('yes')) bttsYes[s.bookmakerName] = s.odds;
      if (n.contains('no')) bttsNo[s.bookmakerName] = s.odds;
    }

    final Map<String, double> over25 = {};
    final Map<String, double> under25 = {};
    for (final s in totalsMarket.selections) {
      if (s.line != '2.5') continue;
      final n = s.selectionName.toLowerCase();
      if (n.contains('over')) over25[s.bookmakerName] = s.odds;
      if (n.contains('under')) under25[s.bookmakerName] = s.odds;
    }

    final Map<String, ComboEstimate> result = {};
    for (final bookmaker in bttsYes.keys) {
      if (!bttsNo.containsKey(bookmaker) || !over25.containsKey(bookmaker) || !under25.containsKey(bookmaker)) continue;
      final estimate = PoissonComboService.estimateAllCombos(
        over25Odds: over25[bookmaker]!,
        under25Odds: under25[bookmaker]!,
        bttsYesOdds: bttsYes[bookmaker]!,
        bttsNoOdds: bttsNo[bookmaker]!,
      );
      if (estimate != null) result[bookmaker] = estimate;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.fixture.homeTeam} vs ${widget.fixture.awayTeam}'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _buildContent(),
                if (isSubmitting)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x88000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildContent() {
    if (errorMessage != null && fullEvent == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ),
      );
    }

    if (fullEvent == null || fullEvent!.markets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No odds available for the selected bookmakers on this fixture.', textAlign: TextAlign.center),
        ),
      );
    }

    final markets = _orderedMarkets();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _comboMarketSection(),
        for (final market in markets)
          if (_bestOutcomesFor(market).isNotEmpty) _marketSection(market),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  Widget _comboMarketSection() {
    final perBookmaker = _computeCombosPerBookmaker();
    if (perBookmaker.isEmpty) return const SizedBox.shrink();

    final rows = <(String label, BetType betType, double Function(ComboEstimate) selector)>[
      ('BTTS & Over 2.5', BetType.bttsYesOverCombo, (c) => c.bttsYesOver25),
      ('BTTS & Under 2.5', BetType.bttsYesUnderCombo, (c) => c.bttsYesUnder25),
      ('No BTTS & Over 2.5', BetType.bttsNoOverCombo, (c) => c.bttsNoOver25),
      ('No BTTS & Under 2.5', BetType.bttsNoUnderCombo, (c) => c.bttsNoUnder25),
    ];

    final isExpanded = _expanded['__combo'] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded['__combo'] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('BTTS & Goals Combos (Estimate)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AccaColors.gold)),
                  ),
                  Icon(isExpanded ? Icons.remove_circle_outline : Icons.add_circle_outline, color: AccaColors.primary),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      "Odds for this market are statistical estimates, not real bookmaker prices — each calculated from a single bookmaker's own BTTS and Over/Under 2.5 odds.",
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ),
                  for (final row in rows)
                    Builder(builder: (context) {
                      final priceMap = {for (final e in perBookmaker.entries) e.key: row.$3(e.value)};
                      final best = priceMap.entries.reduce((a, b) => a.value > b.value ? a : b);
                      return ListTile(
                        title: Text(row.$1, style: const TextStyle(color: Colors.black)),
                        subtitle: Text('Best: ${best.key} · ${priceMap.length} of your bookmakers compared', style: const TextStyle(color: Colors.black54)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AccaColors.gold, borderRadius: BorderRadius.circular(6)),
                          child: Text(decimalToFractional(best.value), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                        onTap: isSubmitting ? null : () => submitCombo(row.$1, row.$2, perBookmaker, row.$3),
                      );
                    }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _marketSection(UkOddsMarket market) {
    final betType = _mapBetType(market.marketName);
    final outcomes = _bestOutcomesFor(market);
    final isExpanded = _expanded[market.marketName] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded[market.marketName] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(market.marketName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AccaColors.gold)),
                  ),
                  Icon(isExpanded ? Icons.remove_circle_outline : Icons.add_circle_outline, color: AccaColors.primary),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: betType == BetType.correctScore
                  ? _correctScoreDropdown(outcomes, betType)
                  : Column(
                      children: [for (final outcome in outcomes) _outcomeRow(outcome, betType)],
                    ),
            ),
        ],
      ),
    );
  }

  Widget _outcomeRow(_PricedOutcome outcome, BetType betType) {
    final displayName = outcome.line != null ? '${outcome.name} (${outcome.line})' : outcome.name;
    return ListTile(
      title: Text(displayName, style: const TextStyle(color: Colors.black)),
      subtitle: Text('Best: ${outcome.bestBookmaker} · ${outcome.allPrices.length} of your bookmakers compared', style: const TextStyle(color: Colors.black54)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AccaColors.gold, borderRadius: BorderRadius.circular(6)),
        child: Text(decimalToFractional(outcome.bestPrice), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
      ),
      onTap: isSubmitting ? null : () => submit(outcome, betType),
    );
  }

  Widget _correctScoreDropdown(List<_PricedOutcome> outcomes, BetType betType) {
    // Parse each outcome's name into (home, away) goals — only handles
    // standard "H-A" scorelines; anything that doesn't parse (e.g. an
    // "Any Other Score" catch-all some bookmakers include) is left out
    // of the two dropdowns below.
    final scorePattern = RegExp(r'^(\d+)\s*-\s*(\d+)$');
    final Map<(int, int), _PricedOutcome> byScore = {};
    for (final outcome in outcomes) {
      if (outcome.line == null) continue;
      final match = scorePattern.firstMatch(outcome.line!.trim());
      if (match == null) continue;
      final home = int.parse(match.group(1)!);
      final away = int.parse(match.group(2)!);
      byScore[(home, away)] = outcome;
    }

    final homeScores = byScore.keys.map((k) => k.$1).toSet().toList()..sort();
    final awayScores = byScore.keys.map((k) => k.$2).toSet().toList()..sort();

    final selectedOutcome = (_selectedHomeScore != null && _selectedAwayScore != null)
        ? byScore[(_selectedHomeScore!, _selectedAwayScore!)]
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedHomeScore,
                  decoration: InputDecoration(labelText: widget.fixture.homeTeam, border: const OutlineInputBorder()),
                  items: homeScores.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                  onChanged: isSubmitting ? null : (value) => setState(() => _selectedHomeScore = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedAwayScore,
                  decoration: InputDecoration(labelText: widget.fixture.awayTeam, border: const OutlineInputBorder()),
                  items: awayScores.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                  onChanged: isSubmitting ? null : (value) => setState(() => _selectedAwayScore = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_selectedHomeScore != null && _selectedAwayScore != null && selectedOutcome == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'No odds available for this exact scoreline from your bookmakers.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          if (selectedOutcome != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AccaColors.gold, borderRadius: BorderRadius.circular(6)),
                    child: Text(decimalToFractional(selectedOutcome.bestPrice), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                  const SizedBox(width: 8),
                  Text('(${selectedOutcome.bestBookmaker})', style: const TextStyle(color: Colors.black)),
                ],
              ),
            ),
          ElevatedButton(
            onPressed: (isSubmitting || selectedOutcome == null) ? null : () => submit(selectedOutcome, betType),
            style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: AccaColors.primary),
            child: const Text('Confirm scoreline'),
          ),
        ],
      ),
    );
  }
}