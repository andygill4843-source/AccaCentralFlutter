import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'acca_central_prediction_engine.dart';
import 'odds_format.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

class ScoutTab extends StatefulWidget {
  final int fixtureId;
  final int leagueId;
  final int season;
  final int homeTeamId;
  final String homeTeamName;
  final String homeLogo;
  final int awayTeamId;
  final String awayTeamName;
  final String awayLogo;
  final bool isLeagueGame;
  final FixtureOddsCache? oddsCache;

  const ScoutTab({
    super.key,
    required this.fixtureId,
    required this.leagueId,
    required this.season,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.homeLogo,
    required this.awayTeamId,
    required this.awayTeamName,
    required this.awayLogo,
    required this.isLeagueGame,
    this.oddsCache,
  });

  @override
  State<ScoutTab> createState() => _ScoutTabState();
}

class _TeamScoutData {
  final String teamName;
  final List<String> last5Results;
  final double last5GoalsForAvg;
  final double last5GoalsAgainstAvg;
  final List<PlayerAbsence> absences;
  const _TeamScoutData({
    required this.teamName,
    required this.last5Results,
    required this.last5GoalsForAvg,
    required this.last5GoalsAgainstAvg,
    required this.absences,
  });
  int get wins => last5Results.where((r) => r == 'W').length;
}

class _H2HDisplay {
  final DateTime? date;
  final int homeTeamId;
  final int awayTeamId;
  final int homeGoals;
  final int awayGoals;
  const _H2HDisplay({this.date, required this.homeTeamId, required this.awayTeamId, required this.homeGoals, required this.awayGoals});
}

class _ScoutTabState extends State<ScoutTab> {
  MatchProbabilities? probabilities;
  _TeamScoutData? homeData;
  _TeamScoutData? awayData;
  List<_H2HDisplay> h2h = [];
  Map<String, double> bookmakerOdds = {};
  List<MarketValue> strongestSelections = [];
  List<MarketValue> valueHunterPicks = [];
  bool isLoading = true;
  String? errorMessage;

  static const Color _strongColor = Color(0xFFF5A623); // amber
  static const Color _valueColor = Color(0xFF34D399); // green

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getMatchPrediction');
      final response = await callable.call({
        'fixtureId': widget.fixtureId,
        'leagueId': widget.leagueId,
        'season': widget.season,
        'homeTeamId': widget.homeTeamId,
        'homeTeamName': widget.homeTeamName,
        'awayTeamId': widget.awayTeamId,
        'awayTeamName': widget.awayTeamName,
        'isLeagueGame': widget.isLeagueGame,
      });
      final data = Map<String, dynamic>.from(response.data as Map);

      final probs = MatchProbabilities.fromMap(Map<String, dynamic>.from(data['probabilities'] as Map));

      _TeamScoutData parseTeam(Map<String, dynamic> json) {
        return _TeamScoutData(
          teamName: json['teamName'] as String,
          last5Results: List<String>.from(json['last5Results'] as List),
          last5GoalsForAvg: (json['last5GoalsForAvg'] as num).toDouble(),
          last5GoalsAgainstAvg: (json['last5GoalsAgainstAvg'] as num).toDouble(),
          absences: (json['absences'] as List)
              .map((a) => PlayerAbsence(
                    playerId: '',
                    playerName: a['playerName'] as String,
                    type: a['type'] as String,
                    reason: a['reason'] as String?,
                    importance: 0.5,
                    attackingImpact: 0.5,
                    defensiveImpact: 0.5,
                  ))
              .toList(),
        );
      }

      final home = parseTeam(Map<String, dynamic>.from(data['home'] as Map));
      final away = parseTeam(Map<String, dynamic>.from(data['away'] as Map));
      final h2hList = (data['h2h'] as List).map((raw) {
        final m = Map<String, dynamic>.from(raw as Map);
        return _H2HDisplay(
          date: m['date'] != null ? DateTime.tryParse(m['date'] as String) : null,
          homeTeamId: m['homeTeamId'] as int,
          awayTeamId: m['awayTeamId'] as int,
          homeGoals: m['homeGoals'] as int,
          awayGoals: m['awayGoals'] as int,
        );
      }).toList();

      Map<String, double> odds = {};
      List<MarketValue> strongest = [];
      List<MarketValue> valueHunter = [];
      if (widget.oddsCache != null) {
        odds = _extractBookmakerOdds(widget.oddsCache!);
        final values = ValueEngine().calculateAll(probs.toProbabilities(), odds);
        strongest = ValueEngine().strongestSelections(values);
        valueHunter = ValueEngine().valueHunter(values);
      }

      if (!mounted) return;
      setState(() {
        probabilities = probs;
        homeData = home;
        awayData = away;
        h2h = h2hList;
        bookmakerOdds = odds;
        strongestSelections = strongest;
        valueHunterPicks = valueHunter;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = "Couldn't load stats: $e";
        isLoading = false;
      });
    }
  }

  Map<String, double> _extractBookmakerOdds(FixtureOddsCache cache) {
    final result = <String, double>{};

    void addExact(String canonical, String marketName, String value) {
      final odd = cache.bestOddFor(marketName, value);
      if (odd != null && odd > 0) result[canonical] = odd;
    }

    addExact('Home Win', 'Match Winner', 'Home');
    addExact('Draw', 'Match Winner', 'Draw');
    addExact('Away Win', 'Match Winner', 'Away');
    addExact('BTTS Yes', 'Both Teams Score', 'Yes');
    addExact('BTTS No', 'Both Teams Score', 'No');

    void scanLines(String marketName, Map<String, String> valueToCanonical) {
      for (final entry in cache.bestOdds[marketName] ?? const <Map<String, dynamic>>[]) {
        final value = entry['value'] as String? ?? '';
        final price = (entry['odd'] as num?)?.toDouble();
        if (price == null || price <= 0) continue;
        final canonical = valueToCanonical[value];
        if (canonical != null) result[canonical] = price;
      }
    }

    scanLines('Goals Over/Under', {'Over 1.5': 'Over 1.5', 'Over 2.5': 'Over 2.5', 'Over 3.5': 'Over 3.5', 'Under 2.5': 'Under 2.5'});
    scanLines('Total - Home', {'Over 0.5': 'Home Over 0.5', 'Over 1.5': 'Home Over 1.5'});
    scanLines('Total - Away', {'Over 0.5': 'Away Over 0.5', 'Over 1.5': 'Away Over 1.5'});

    return result;
  }

  String _displayMarketLabel(String canonicalMarket, String homeTeamName, String awayTeamName) {
    switch (canonicalMarket) {
      case 'Home Win':
        return '$homeTeamName to Win';
      case 'Away Win':
        return '$awayTeamName to Win';
      case 'Draw':
        return 'Draw';
      case 'Home Over 0.5':
        return '$homeTeamName Over 0.5 goals';
      case 'Home Over 1.5':
        return '$homeTeamName Over 1.5 goals';
      case 'Away Over 0.5':
        return '$awayTeamName Over 0.5 goals';
      case 'Away Over 1.5':
        return '$awayTeamName Over 1.5 goals';
      case 'Over 1.5':
        return 'Over 1.5 Goals';
      case 'Over 2.5':
        return 'Over 2.5 Goals';
      case 'Over 3.5':
        return 'Over 3.5 Goals';
      case 'Under 2.5':
        return 'Under 2.5 Goals';
      case 'BTTS Yes':
        return 'Both Teams to Score';
      case 'BTTS No':
        return 'No — Both Teams to Score';
      default:
        return canonicalMarket;
    }
  }

  String? _crestForMarket(String canonicalMarket) {
    if (canonicalMarket.startsWith('Home')) return widget.homeLogo;
    if (canonicalMarket.startsWith('Away')) return widget.awayLogo;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (probabilities == null || homeData == null || awayData == null) {
      return const Center(child: Text('No stats available for this fixture.', style: TextStyle(color: Colors.white70)));
    }

    final p = probabilities!;
    final home = homeData!;
    final away = awayData!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (strongestSelections.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SwipeableInsightCards(
            dotColor: _strongColor,
            cards: [
              for (final v in strongestSelections)
                _insightCard(
                  value: v,
                  accentColor: _strongColor,
                  icon: '🔥',
                  typeLabel: 'STRONGEST SELECTION',
                  badgeText: 'HIGH PROBABILITY',
                  footerIcon: Icons.emoji_events,
                  footerText: 'One of the highest probability selections based upon the Acca Central scouting.',
                  homeTeamName: home.teamName,
                  awayTeamName: away.teamName,
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (valueHunterPicks.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SwipeableInsightCards(
            dotColor: _valueColor,
            cards: [
              for (final v in valueHunterPicks)
                _insightCard(
                  value: v,
                  accentColor: _valueColor,
                  icon: '💎',
                  typeLabel: 'VALUE HUNTER',
                  badgeText: '+${(v.edge * 100).toStringAsFixed(0)}% VALUE EDGE',
                  footerIcon: Icons.track_changes,
                  footerText: 'Model probability is ${(v.edge * 100).toStringAsFixed(0)}% higher than implied probability.',
                  homeTeamName: home.teamName,
                  awayTeamName: away.teamName,
                  showImplied: true,
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        _sectionCard(
          title: 'WHO WILL WIN?',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _resultRing(percent: p.homeWin * 100, color: AccaColors.win, label: home.teamName, crestUrl: widget.homeLogo),
              _resultRing(percent: p.draw * 100, color: Colors.grey, label: 'Draw', letter: 'D'),
              _resultRing(percent: p.awayWin * 100, color: AccaColors.loss, label: away.teamName, crestUrl: widget.awayLogo),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'GAME GOALS',
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            runSpacing: 12,
            children: [
              _statRing(p.over15 * 100, 'Over 1.5'),
              _statRing(p.over25 * 100, 'Over 2.5'),
              _statRing(p.over35 * 100, 'Over 3.5'),
              _statRing(p.bttsYes * 100, 'BTTS'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'TEAM GOALS',
          child: Column(
            children: [
              Text(home.teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              _marketIconRow(icon: Icons.sports_score, iconColor: _strongColor, label: '${home.teamName} Over 0.5 goals', percent: p.homeOver05 * 100, odds: bookmakerOdds['Home Over 0.5']),
              _marketIconRow(icon: Icons.sports_soccer, iconColor: _valueColor, label: '${home.teamName} Over 1.5 goals', percent: p.homeOver15 * 100, odds: bookmakerOdds['Home Over 1.5']),
              const SizedBox(height: 14),
              Text(away.teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              _marketIconRow(icon: Icons.sports_score, iconColor: _strongColor, label: '${away.teamName} Over 0.5 goals', percent: p.awayOver05 * 100, odds: bookmakerOdds['Away Over 0.5']),
              _marketIconRow(icon: Icons.sports_soccer, iconColor: _valueColor, label: '${away.teamName} Over 1.5 goals', percent: p.awayOver15 * 100, odds: bookmakerOdds['Away Over 1.5']),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: widget.isLeagueGame ? 'LAST 5 LEAGUE GAMES' : 'LAST 5 GAMES',
          child: Column(
            children: [
              _teamFormRow(home),
              const SizedBox(height: 10),
              _teamFormRow(away),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: widget.isLeagueGame ? 'GOALS SCORED / CONCEDED (LAST 5 LEAGUE AVG)' : 'GOALS SCORED / CONCEDED (LAST 5 AVG)',
          child: Column(
            children: [
              _statCompareRow(home.last5GoalsForAvg.toStringAsFixed(1), away.last5GoalsForAvg.toStringAsFixed(1), 'Scored'),
              const SizedBox(height: 8),
              _statCompareRow(home.last5GoalsAgainstAvg.toStringAsFixed(1), away.last5GoalsAgainstAvg.toStringAsFixed(1), 'Conceded'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'HEAD TO HEAD (LAST 5)',
          child: h2h.isEmpty
              ? const Text('No previous meetings on record.', style: TextStyle(color: Colors.white54, fontSize: 13))
              : Column(children: [for (final result in h2h) _h2hRow(result, home.teamName, away.teamName)]),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'INJURIES & SUSPENSIONS',
          child: home.absences.isEmpty && away.absences.isEmpty
              ? const Text('No injury or suspension concerns reported.', style: TextStyle(color: Colors.white54, fontSize: 13))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (home.absences.isNotEmpty) ...[
                      Text(home.teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      for (final a in home.absences) _absenceRow(a),
                      const SizedBox(height: 10),
                    ],
                    if (away.absences.isNotEmpty) ...[
                      Text(away.teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      for (final a in away.absences) _absenceRow(a),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _insightCard({
    required MarketValue value,
    required Color accentColor,
    required String icon,
    required String typeLabel,
    required String badgeText,
    required IconData footerIcon,
    required String footerText,
    required String homeTeamName,
    required String awayTeamName,
    bool showImplied = false,
  }) {
    final label = _displayMarketLabel(value.market, homeTeamName, awayTeamName);
    final crest = _crestForMarket(value.market);
    final percent = (value.modelProbability * 100).clamp(0, 100);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(child: Text(typeLabel, style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(border: Border.all(color: accentColor), borderRadius: BorderRadius.circular(20)),
                child: Text(badgeText, style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (crest != null && crest.isNotEmpty)
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Image.network(crest, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 16, color: Colors.black26)),
                  ),
                )
              else
                const CircleAvatar(radius: 18, backgroundColor: Colors.white12, child: Icon(Icons.sports_soccer, size: 18, color: Colors.white70)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    Text('$homeTeamName vs $awayTeamName', style: const TextStyle(color: Colors.white54, fontSize: 12), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _insightStat('${percent.round()}%', 'MODEL PROBABILITY', Colors.blueAccent),
              const SizedBox(width: 16),
              _insightStat(decimalToFractional(value.bookmakerOdds), 'ODDS', Colors.white),
              if (showImplied) ...[
                const SizedBox(width: 16),
                _insightStat('${(value.impliedProbability * 100).round()}%', 'IMPLIED', Colors.white70),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(accentColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(footerIcon, size: 13, color: Colors.white54),
              const SizedBox(width: 6),
              Expanded(child: Text(footerText, style: const TextStyle(color: Colors.white54, fontSize: 11))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _insightStat(String value, String label, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(color: valueColor, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1A24), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _resultRing({
    required double percent,
    required Color color,
    required String label,
    String? crestUrl,
    String? letter,
  }) {
    return Column(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: (percent / 100).clamp(0.0, 1.0),
                  strokeWidth: 4,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              if (crestUrl != null && crestUrl.isNotEmpty)
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Image.network(crestUrl, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.shield, size: 16, color: Colors.black26)),
                  ),
                )
              else
                CircleAvatar(radius: 18, backgroundColor: color, child: Text(letter ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 76,
          child: Text('$label ${percent.round()}%', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ],
    );
  }

  Widget _statRing(double percent, String label) {
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: (percent / 100).clamp(0.0, 1.0),
                    strokeWidth: 4,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(AccaColors.gold),
                  ),
                ),
                Text('${percent.round()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _marketIconRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required double percent,
    double? odds,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (percent / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 5,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(iconColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text('${percent.round()}%', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          if (odds != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 42,
              child: Text(decimalToFractional(odds), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultDot(String r) {
    final color = r == 'W' ? AccaColors.win : (r == 'L' ? AccaColors.loss : Colors.grey);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 22,
      height: 22,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: Text(r, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _teamFormRow(_TeamScoutData team) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(team.teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis)),
        Expanded(
          child: team.last5Results.isEmpty
              ? const Text('—', style: TextStyle(color: Colors.white38))
              : Row(children: [for (final r in team.last5Results) _resultDot(r)]),
        ),
        if (team.last5Results.isNotEmpty) Text('${team.wins}/${team.last5Results.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _statCompareRow(String homeValue, String awayValue, String metricLabel) {
    return Row(
      children: [
        Expanded(child: Text(homeValue, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center)),
        SizedBox(width: 90, child: Text(metricLabel, style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
        Expanded(child: Text(awayValue, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center)),
      ],
    );
  }

  Widget _h2hRow(_H2HDisplay result, String homeTeamName, String awayTeamName) {
    final dateStr = result.date != null
        ? '${result.date!.day.toString().padLeft(2, '0')}/${result.date!.month.toString().padLeft(2, '0')}/${(result.date!.year % 100).toString().padLeft(2, '0')}'
        : '—';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(dateStr, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${result.homeTeamId == widget.homeTeamId ? homeTeamName : awayTeamName} ${result.homeGoals}-${result.awayGoals} ${result.awayTeamId == widget.awayTeamId ? awayTeamName : homeTeamName}',
                style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _absenceRow(PlayerAbsence a) {
    final isInjury = a.type.toLowerCase().contains('injur');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(isInjury ? Icons.healing : Icons.block, size: 14, color: isInjury ? Colors.orangeAccent : Colors.redAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${a.playerName}${a.reason != null ? ' — ${a.reason}' : ''}', style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Swipeable carousel for the Strongest Selections / Value Hunter cards
/// — one card per page, with dot indicators below. A single-card list
/// renders that one card directly with no PageView/dots at all.
class _SwipeableInsightCards extends StatefulWidget {
  final List<Widget> cards;
  final Color dotColor;
  const _SwipeableInsightCards({required this.cards, required this.dotColor});

  @override
  State<_SwipeableInsightCards> createState() => _SwipeableInsightCardsState();
}

class _SwipeableInsightCardsState extends State<_SwipeableInsightCards> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();
    if (widget.cards.length == 1) return widget.cards.first;
    return Column(
      children: [
        SizedBox(
          height: 240,
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: widget.cards,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.cards.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _page == i ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _page == i ? widget.dotColor : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}