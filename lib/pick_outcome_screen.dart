import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart';
import 'odds_format.dart';
import 'api_football_service.dart';
import 'odds_orchestrator.dart';
import 'fixture_card.dart';
import 'scout_tab.dart';
import 'lineup_tab.dart';

class PickOutcomeScreen extends StatefulWidget {
  final ApiFootballFixture fixture;
  final String leagueKey;
  final String gameWeekId;
  final String memberId;
  final String teamId;
  final String? tournamentMatchId;
  final bool isSecondaryTournamentLeg;
  final List<BetType>? allowedBetTypes;
  const PickOutcomeScreen({
    super.key,
    required this.fixture,
    required this.leagueKey,
    required this.gameWeekId,
    required this.memberId,
    required this.teamId,
    this.tournamentMatchId,
    this.isSecondaryTournamentLeg = false,
    this.allowedBetTypes,
  });
  @override
  State<PickOutcomeScreen> createState() => _PickOutcomeScreenState();
}

class _PickOutcomeScreenState extends State<PickOutcomeScreen> {
  FixtureOddsCache? oddsCache;
  bool isLoading = true;
  bool isSubmitting = false;
  String? errorMessage;
  final Map<String, bool> _expanded = {};
  int? _selectedHomeScore;
  int? _selectedAwayScore;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    loadOdds();
  }

  Future<void> loadOdds() async {
    try {
      final cache = await OddsOrchestrator.instance.fetchOrCache(
        apiFootballFixtureId: widget.fixture.id,
        apiFootballLeagueId: widget.fixture.leagueId,
        leagueKey: widget.leagueKey,
        homeTeam: widget.fixture.homeTeam,
        awayTeam: widget.fixture.awayTeam,
        kickoff: widget.fixture.kickoff,
      );
      if (!mounted) return;
      setState(() {
        oddsCache = cache;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = "Couldn't load odds: $e";
        isLoading = false;
      });
    }
  }

  BetType _mapBetType(String marketName, {String? value}) {
    final n = marketName.toLowerCase();
    if (n.contains('btts') && n.contains('goals')) {
      final v = (value ?? '').toLowerCase();
      if (v.contains('yes') && v.contains('over'))  { return BetType.bttsYesOverCombo; }
      if (v.contains('yes') && v.contains('under')) { return BetType.bttsYesUnderCombo; }
      if (v.contains('no')  && v.contains('over'))  { return BetType.bttsNoOverCombo; }
      if (v.contains('no')  && v.contains('under')) { return BetType.bttsNoUnderCombo; }
    }
    if (n.contains('match winner') || n.contains('1x2')) { return BetType.matchWinner; }
    if (n.contains('both teams')) { return BetType.bothTeamsToScore; }
    if (n.contains('total - home') || n.contains('total - away')) { return BetType.teamTotals; }
    if (n.contains('goals over/under') || n.contains('alternate totals')) { return BetType.overUnderGoals; }
    if (n.contains('draw no bet')) { return BetType.drawNoBet; }
    if (n.contains('handicap')) { return BetType.handicap; }
    if (n.contains('correct score') || n.contains('exact score')) { return BetType.correctScore; }
    if (n.contains('double chance')) { return BetType.doubleChance; }
    if (n.contains('half time') || n.contains('half/full')) { return BetType.halfTimeFullTime; }
    if (n.contains('goalscorer') || n.contains('anytime')) { return BetType.anytimeScorer; }
    return BetType.other;
  }

  int _marketPriority(String marketName) {
    final n = marketName.toLowerCase();
    if (n.contains('match winner')) { return 0; }
    if (n.contains('goals over/under')) { return 1; }
    if (n.contains('both teams')) { return 2; }
    if (n.contains('btts') && n.contains('goals')) { return 3; }
    if (n.contains('total - home') || n.contains('total - away')) { return 4; }
    if (n.contains('double chance')) { return 5; }
    if (n.contains('draw no bet')) { return 6; }
    if (n.contains('correct score') || n.contains('exact score')) { return 7; }
    if (n.contains('alternate totals')) { return 8; }
    return 99;
  }

  bool get isManagerSpecial => widget.allowedBetTypes != null && widget.allowedBetTypes!.isNotEmpty;

  bool _isOutcomeAllowedForManagerSpecial(String marketName, BetType type) {
    if (!isManagerSpecial) return true;
    if (!widget.allowedBetTypes!.contains(type)) return false;
    if (type == BetType.overUnderGoals && marketName.toLowerCase().contains('alternate')) {
      return false;
    }
    return true;
  }

  bool _marketHasAnyAllowedOutcome(String marketName, List<Map<String, dynamic>> outcomes) {
    if (!isManagerSpecial) return true;
    if (_mapBetType(marketName) == BetType.correctScore) {
      return _isOutcomeAllowedForManagerSpecial(marketName, BetType.correctScore);
    }
    for (final o in outcomes) {
      final t = _mapBetType(marketName, value: o['value'] as String);
      if (_isOutcomeAllowedForManagerSpecial(marketName, t)) return true;
    }
    return false;
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _orderedMarkets() {
    if (oddsCache == null) return [];
    var entries = oddsCache!.bestOdds.entries.toList();
    if (isManagerSpecial) {
      entries = entries.where((e) => _marketHasAnyAllowedOutcome(e.key, e.value)).toList();
    }
    entries.sort((a, b) {
      final pa = _marketPriority(a.key);
      final pb = _marketPriority(b.key);
      return pa.compareTo(pb);
    });
    return entries;
  }

  String _formatPickLabel(String value, String? line, BetType betType, String marketName) {
    final base = (line != null && !value.toLowerCase().contains(line.toLowerCase()))
        ? '$value $line'
        : value;
    if (betType == BetType.matchWinner) {
      final v = value.toLowerCase();
      if (v == 'home') return widget.fixture.homeTeam;
      if (v == 'away') return widget.fixture.awayTeam;
      if (v == 'draw') return 'Draw';
    }
    if (betType == BetType.teamTotals) {
      final n = marketName.toLowerCase();
      if (n.contains('home')) return '${widget.fixture.homeTeam} $base Goals';
      if (n.contains('away')) return '${widget.fixture.awayTeam} $base Goals';
    }
    if (betType == BetType.overUnderGoals) return '$base Game Goals';
    return base;
  }

  Future<void> submit({
    required String value,
    required double bestOdd,
    required BetType betType,
    required String marketName,
    String? line,
  }) async {
    if (isSubmitting || oddsCache == null) return;
    setState(() { isSubmitting = true; errorMessage = null; });
    final pickLabel = _formatPickLabel(value, line, betType, marketName);
    final selectionDescription =
        '$pickLabel — ${widget.fixture.homeTeam} vs ${widget.fixture.awayTeam}';
    final bookmakerPrices = <String, double>{};
    for (final bmKey in OddsOrchestrator.allBookmakers) {
      final price = oddsCache!.bookmakerOddFor(bmKey, marketName, value);
      if (price != null && price > 0) bookmakerPrices[bmKey] = price;
    }
    final bestBookmaker = bookmakerPrices.isNotEmpty
        ? bookmakerPrices.entries.reduce((a, b) => a.value > b.value ? a : b).key
        : '';
    try {
      final physioProtected = await FirestoreService.instance.hasPhysioProtectionPending(
        teamId: widget.teamId,
        memberId: widget.memberId,
        gameWeekId: widget.gameWeekId,
      );
      final leg = AccumulatorLeg(
        id: null,
        gameWeekId: widget.gameWeekId,
        teamId: widget.teamId,
        memberId: widget.memberId,
        fixtureId: widget.fixture.id.toString(),
        fixtureDescription: '${widget.fixture.homeTeam} vs ${widget.fixture.awayTeam}',
        kickoff: widget.fixture.kickoff,
        betType: betType,
        selectionDescription: selectionDescription,
        marketName: marketName,
        pickValue: value,
        decimalOddsAtSelection: bestOdd,
        bookmaker: bestBookmaker,
        bookmakerPrices: bookmakerPrices,
        sportmonksFixtureId: null,
        outcome: LegOutcome.pending,
        submittedAt: DateTime.now(),
        physioProtected: physioProtected,
        tournamentMatchId: widget.tournamentMatchId,
        isSecondaryTournamentLeg: widget.isSecondaryTournamentLeg,
        apiFootballFixtureId: widget.fixture.id,
        apiFootballLeagueId: widget.fixture.leagueId,
      );
      await FirestoreService.instance.submitLeg(leg);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() { isSubmitting = false; errorMessage = e.toString(); });
    }
  }

  Future<void> submitCorrectScore({required String marketName}) async {
    if (_selectedHomeScore == null || _selectedAwayScore == null) return;
    String normaliseScore(String s) =>
        s.replaceAll(':', '-').replaceAll(' ', '').trim();
    final selectedValue = '$_selectedHomeScore-$_selectedAwayScore';
    final market = oddsCache?.bestOdds[marketName] ??
        oddsCache?.bestOdds['Correct Score'] ??
        oddsCache?.bestOdds['Exact Score'];
    if (market == null) {
      setState(() => errorMessage = 'No correct score odds available.');
      return;
    }
    final match = market.firstWhere(
      (v) => normaliseScore(v['value'].toString()) == selectedValue,
      orElse: () => {},
    );
    final odd = match.isNotEmpty ? (match['odd'] as num).toDouble() : 0.0;
    if (odd <= 0) {
      setState(() => errorMessage = 'No odds for $_selectedHomeScore-$_selectedAwayScore. Try another score.');
      return;
    }
    await submit(
      value: selectedValue,
      bestOdd: odd,
      betType: BetType.correctScore,
      marketName: marketName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.fixture.homeTeam} vs ${widget.fixture.awayTeam}',
            style: const TextStyle(fontSize: 15)),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: FixtureHeaderCard(
              fixtureId: widget.fixture.id,
              homeLogo: widget.fixture.homeLogo,
              awayLogo: widget.fixture.awayLogo,
              homeName: widget.fixture.homeTeam,
              awayName: widget.fixture.awayTeam,
              isLive: widget.fixture.isLive,
              roundAllCorners: true,
              centerContent: widget.fixture.isNotStarted
                  ? _kickoffCenter(widget.fixture)
                  : _liveCenter(widget.fixture),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _tabBar(),
          ),
          Expanded(child: _tabBody()),
        ],
      ),
    );
  }

  Widget _kickoffCenter(ApiFootballFixture f) {
    final local = f.kickoff.toLocal();
    final dateStr = '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    final timeStr = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        fixtureStatusChip(dateStr),
        const SizedBox(height: 6),
        Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _liveCenter(ApiFootballFixture f) {
    final topLabel = f.isLive ? f.halfLabel : (f.isFinished ? 'FT' : f.statusLabel);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        fixtureStatusChip(topLabel),
        const SizedBox(height: 6),
        Text(f.scoreDisplay, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _tabBar() {
    const labels = ['Selections', 'Scout', 'Line up'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTabIndex = i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedTabIndex == i ? AccaColors.gold : const Color(0xFF23232E),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: _selectedTabIndex == i ? AccaColors.primary : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tabBody() {
    switch (_selectedTabIndex) {
      case 1:
        return ScoutTab(fixtureId: widget.fixture.id);
      case 2:
        return LineupTab(
          fixtureId: widget.fixture.id,
          homeTeamName: widget.fixture.homeTeam,
          awayTeamName: widget.fixture.awayTeam,
        );
      default:
        return _selectionsBody();
    }
  }

  Widget _selectionsBody() {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null && oddsCache == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: loadOdds, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isManagerSpecial)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: AccaColors.gold, borderRadius: BorderRadius.circular(8)),
            child: Text(
              "Manager special: ${widget.allowedBetTypes!.map((t) => t.displayName).join(' / ')} only this week 👩‍💼👨‍💼",
              style: const TextStyle(color: AccaColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(errorMessage!, style: const TextStyle(color: Colors.orange)),
          ),
        for (final entry in _orderedMarkets()) ...[
          _marketSection(entry.key, entry.value),
          const SizedBox(height: 12),
        ],
        if (isSubmitting) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _marketSection(String marketName, List<Map<String, dynamic>> outcomes) {
    final betType = _mapBetType(marketName);
    if (betType == BetType.correctScore) {
      return _correctScoreSection(marketName);
    }
    final isExpanded = _expanded[marketName] ?? _marketPriority(marketName) < 5;
    var display = outcomes.where((o) => (o['odd'] as num).toDouble() > 0).toList();
    if (isManagerSpecial) {
      display = display.where((o) {
        final t = _mapBetType(marketName, value: o['value'] as String);
        return _isOutcomeAllowedForManagerSpecial(marketName, t);
      }).toList();
    }
    display.sort((a, b) {
      final aVal = a['value'] as String;
      final bVal = b['value'] as String;
      return aVal.compareTo(bVal);
    });
    final toShow = isExpanded ? display : display.take(4).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccaColors.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded[marketName] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(marketName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black)),
                  ),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.black54),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: Colors.black12),
            for (final outcome in toShow)
              _outcomeRow(
                value: outcome['value'] as String,
                odd: (outcome['odd'] as num).toDouble(),
                betType: betType,
                marketName: marketName,
              ),
            if (display.length > 4 && !isExpanded)
              TextButton(
                onPressed: () => setState(() => _expanded[marketName] = true),
                child: Text('Show all ${display.length} options'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _outcomeRow({
    required String value,
    required double odd,
    required BetType betType,
    required String marketName,
  }) {
    final resolvedBetType = _mapBetType(marketName, value: value);
    final label = _formatPickLabel(value, null, resolvedBetType, marketName);
    return InkWell(
      onTap: isSubmitting
          ? null
          : () => submit(
                value: value,
                bestOdd: odd,
                betType: resolvedBetType,
                marketName: marketName,
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: Colors.black))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AccaColors.gold, borderRadius: BorderRadius.circular(6)),
              child: Text(decimalToFractional(odd), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _correctScoreSection(String marketName) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccaColors.gold, width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Correct Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _scorePicker(widget.fixture.homeTeam, true)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–', style: TextStyle(fontSize: 18, color: Colors.black))),
              Expanded(child: _scorePicker(widget.fixture.awayTeam, false)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedHomeScore != null && _selectedAwayScore != null && !isSubmitting)
                  ? () => submitCorrectScore(marketName: marketName)
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: Colors.black),
              child: const Text('Select this score'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scorePicker(String teamName, bool isHome) {
    final selected = isHome ? _selectedHomeScore : _selectedAwayScore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(teamName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 4),
        DropdownButton<int>(
          value: selected,
          hint: const Text('Goals', style: TextStyle(color: Colors.black54)),
          dropdownColor: Colors.white,
          style: const TextStyle(color: Colors.black),
          items: [for (int i = 0; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i'))],
          onChanged: (v) => setState(() {
            if (isHome) { _selectedHomeScore = v; } else { _selectedAwayScore = v; }
          }),
        ),
      ],
    );
  }
}