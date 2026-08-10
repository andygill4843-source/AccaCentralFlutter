import 'package:flutter/material.dart';
import 'odds_api_service.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'package:collection/collection.dart';
import 'fixture_matching_service.dart';

class _PricedOutcome {
  final String name;
  final double? point;
  final double bestPrice;
  final String bestBookmaker;
  final Map<String, double> allPrices;
  final Map<String, String> allLinks;

  _PricedOutcome({
    required this.name,
    this.point,
    required this.bestPrice,
    required this.bestBookmaker,
    required this.allPrices,
    required this.allLinks,
  });
}

class PickOutcomeScreen extends StatefulWidget {
  final OddsEvent event;
  final SoccerLeague league;
  final String gameWeekId;
  final String memberId;
  final String teamId;

  const PickOutcomeScreen({
    super.key,
    required this.event,
    required this.league,
    required this.gameWeekId,
    required this.memberId,
    required this.teamId,
  });

  @override
  State<PickOutcomeScreen> createState() => _PickOutcomeScreenState();
}

class _PickOutcomeScreenState extends State<PickOutcomeScreen> {
  static const _marketConfig = [
    ('h2h', 'Match Winner', BetType.matchWinner),
    ('totals', 'Over/Under', BetType.overUnderGoals),
    ('btts', 'Both Teams to Score', BetType.bothTeamsToScore),
    ('draw_no_bet', 'Draw No Bet', BetType.drawNoBet),
    ('spreads', 'Handicap', BetType.handicap),
  ];

  OddsEvent? fullEvent;
  bool isLoadingOdds = true;
  bool isSubmitting = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadFullOdds();
  }

  Future<void> loadFullOdds() async {
    try {
      final event = await OddsApiService.instance.fetchEventOdds(league: widget.league, eventId: widget.event.id);
      setState(() {
        fullEvent = event;
        isLoadingOdds = false;
      });
    } catch (_) {
      setState(() {
        fullEvent = widget.event; // fall back to the featured-market data from the list screen
        isLoadingOdds = false;
      });
    }
  }

  List<_PricedOutcome> bestOutcomes(String marketKey) {
    final source = fullEvent;
    if (source == null) return [];

    final Map<String, Map<String, double>> prices = {};
    final Map<String, Map<String, String>> links = {};
    final Map<String, (String, double?)> names = {};

    for (final bookmaker in source.bookmakers) {
      final market = bookmaker.markets.where((m) => m.key == marketKey).firstOrNull;
      if (market == null) continue;
      for (final outcome in market.outcomes) {
        final groupKey = '${outcome.name}|${outcome.point ?? 0}';
        names[groupKey] = (outcome.name, outcome.point);
        prices.putIfAbsent(groupKey, () => {})[bookmaker.title] = outcome.price;
        final link = outcome.link ?? market.link ?? bookmaker.link;
        if (link != null) {
          links.putIfAbsent(groupKey, () => {})[bookmaker.title] = link;
        }
      }
    }

    return names.keys.map((groupKey) {
      final priceMap = prices[groupKey]!;
      final best = priceMap.entries.reduce((a, b) => a.value > b.value ? a : b);
      final meta = names[groupKey]!;
      return _PricedOutcome(
        name: meta.$1,
        point: meta.$2,
        bestPrice: best.value,
        bestBookmaker: best.key,
        allPrices: priceMap,
        allLinks: links[groupKey] ?? {},
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  String displayName(_PricedOutcome outcome, BetType betType) {
    if (betType == BetType.overUnderGoals) {
      final pointText = outcome.point != null ? ' ${outcome.point}' : '';
      return '${outcome.name}$pointText goals';
    }
    if (betType == BetType.handicap) {
      final pointText = outcome.point != null ? (outcome.point! > 0 ? ' +${outcome.point}' : ' ${outcome.point}') : '';
      return '${outcome.name}$pointText';
    }
    return outcome.name;
  }

 Future<void> submit(_PricedOutcome outcome, BetType betType) async {
    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });

    final sportmonksId = await FixtureMatchingService.resolveSportmonksFixtureId(
      homeTeam: widget.event.homeTeam,
      awayTeam: widget.event.awayTeam,
      kickoff: widget.event.commenceTime,
    );

    final selectionDescription = '${displayName(outcome, betType)} — ${widget.event.homeTeam} vs ${widget.event.awayTeam}';

    final leg = AccumulatorLeg(
      id: null,
      gameWeekId: widget.gameWeekId,
      teamId: widget.teamId,
      memberId: widget.memberId,
      fixtureId: widget.event.id,
      fixtureDescription: '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
      kickoff: widget.event.commenceTime,
      betType: betType,
      selectionDescription: selectionDescription,
      decimalOddsAtSelection: outcome.bestPrice,
      bookmaker: outcome.bestBookmaker,
      bookmakerPrices: outcome.allPrices,
      bookmakerLinks: outcome.allLinks,
      sportmonksFixtureId: sportmonksId,
      outcome: LegOutcome.pending,
      submittedAt: DateTime.now(),
    );

    try {
      await FirestoreService.instance.submitLeg(leg);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        isSubmitting = false;
        errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.event.homeTeam} vs ${widget.event.awayTeam}'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoadingOdds
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  children: [
                    for (final config in _marketConfig)
                      if (bestOutcomes(config.$1).isNotEmpty)
                        _marketSection(config.$2, bestOutcomes(config.$1), config.$3),
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
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

  Widget _marketSection(String title, List<_PricedOutcome> outcomes, BetType betType) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          for (final outcome in outcomes)
            ListTile(
              tileColor: Colors.white,
              title: Text(displayName(outcome, betType)),
              subtitle: Text('Best price: ${outcome.bestBookmaker} · ${outcome.allPrices.length} bookmakers compared'),
              trailing: Text(outcome.bestPrice.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: isSubmitting ? null : () => submit(outcome, betType),
            ),
        ],
      ),
    );
  }
}