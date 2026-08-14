import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'scoring_engine.dart';
import 'main.dart'; // for AccaColors

class StatsScreen extends StatefulWidget {
  final String teamId;

  const StatsScreen({super.key, required this.teamId});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<LeagueTableEntry> entries = [];
  List<MemberStats> memberStats = [];
  List<(BetType, int)> betTypeCounts = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final members = await FirestoreService.instance.fetchMembers(widget.teamId);
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);
      setState(() {
        entries = ScoringEngine.buildLeagueTable(members: members, legs: legs);
        memberStats = MemberStatsEngine.buildMemberStats(members: members, legs: legs, gameWeeks: gameWeeks);
        betTypeCounts = ScoringEngine.betTypePopularity(legs);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  List<LeagueTableEntry> get currentStreakLeaders =>
      entries.where((e) => e.currentStreak > 0).toList()..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));

  List<LeagueTableEntry> get longestStreakLeaders {
    final list = entries.where((e) => e.longestWinStreak > 0).toList()
      ..sort((a, b) => b.longestWinStreak.compareTo(a.longestWinStreak));
    return list.take(5).toList();
  }

  List<LeagueTableEntry> get biggestWins {
    final list = entries.where((e) => e.biggestWin != null).toList()
      ..sort((a, b) => b.biggestWin!.decimalOddsAtSelection.compareTo(a.biggestWin!.decimalOddsAtSelection));
    return list.take(5).toList();
  }

  List<MemberStats> get lowestOddsWins {
    final list = memberStats.where((m) => m.lowestOddsWin != null).toList()
      ..sort((a, b) => a.lowestOddsWin!.decimalOddsAtSelection.compareTo(b.lowestOddsWin!.decimalOddsAtSelection));
    return list.take(5).toList();
  }

  List<MemberStats> get biggestLosingOdds {
    final list = memberStats.where((m) => m.biggestLosingOdds != null).toList()
      ..sort((a, b) => b.biggestLosingOdds!.decimalOddsAtSelection.compareTo(a.biggestLosingOdds!.decimalOddsAtSelection));
    return list.take(5).toList();
  }

  List<MemberStats> get valueHunters {
    final list = memberStats.where((m) => m.valueHunterCount > 0).toList()
      ..sort((a, b) => b.valueHunterCount.compareTo(a.valueHunterCount));
    return list.take(5).toList();
  }

  List<MemberStats> get fastestPickers {
    final list = memberStats.where((m) => m.avgPickTimeMinutes != null).toList()
      ..sort((a, b) => a.avgPickTimeMinutes!.compareTo(b.avgPickTimeMinutes!));
    return list.take(3).toList();
  }

  List<MemberStats> get slowestPickers {
    final list = memberStats.where((m) => m.avgPickTimeMinutes != null).toList()
      ..sort((a, b) => b.avgPickTimeMinutes!.compareTo(a.avgPickTimeMinutes!));
    return list.take(3).toList();
  }

  String _formatMinutes(double minutes) {
    if (minutes < 60) return '${minutes.round()} min';
    final hours = minutes / 60;
    if (hours < 24) return '${hours.toStringAsFixed(1)} hr';
    return '${(hours / 24).toStringAsFixed(1)} days';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sectionHeader('Current streaks'),
                      if (currentStreakLeaders.isEmpty)
                        _emptyNote('No active streaks yet.')
                      else
                        for (final e in currentStreakLeaders) _streakRow(e),
                      const SizedBox(height: 20),

                      _sectionHeader('Longest win streaks (all time)'),
                      if (longestStreakLeaders.isEmpty)
                        _emptyNote("Nobody's won a leg yet.")
                      else
                        for (final e in longestStreakLeaders)
                          ListTile(
                            title: Text(e.displayName),
                            trailing: Text('${e.longestWinStreak}', style: TextStyle(color: AccaColors.textSecondary)),
                          ),
                      const SizedBox(height: 20),

                      _sectionHeader('Biggest odds win'),
                      if (biggestWins.isEmpty)
                        _emptyNote('No winning legs yet.')
                      else
                        for (final e in biggestWins) _oddsCard(e.displayName, e.biggestWin!, AccaColors.gold),
                      const SizedBox(height: 20),

                      _sectionHeader('Lowest odds win'),
                      if (lowestOddsWins.isEmpty)
                        _emptyNote('No winning legs yet.')
                      else
                        for (final m in lowestOddsWins) _oddsCard(m.displayName, m.lowestOddsWin!, AccaColors.win),
                      const SizedBox(height: 20),

                      _sectionHeader('Biggest losing odds'),
                      if (biggestLosingOdds.isEmpty)
                        _emptyNote('No losing legs yet.')
                      else
                        for (final m in biggestLosingOdds) _oddsCard(m.displayName, m.biggestLosingOdds!, AccaColors.loss),
                      const SizedBox(height: 20),

                      _sectionHeader('Average winning / losing odds'),
                      if (memberStats.where((m) => m.averageWinningOdds != null || m.averageLosingOdds != null).isEmpty)
                        _emptyNote('No settled legs yet.')
                      else
                        for (final m in memberStats)
                          if (m.averageWinningOdds != null || m.averageLosingOdds != null) _averageOddsRow(m),
                      const SizedBox(height: 20),

                      _sectionHeader('Value hunter (3/1+ picks)'),
                      if (valueHunters.isEmpty)
                        _emptyNote('Nobody has picked a 3/1+ leg yet.')
                      else
                        for (final m in valueHunters)
                          ListTile(
                            title: Text(m.displayName),
                            trailing: Text('${m.valueHunterCount}', style: TextStyle(color: AccaColors.textSecondary)),
                          ),
                      const SizedBox(height: 20),

                      _sectionHeader('Fastest picker'),
                      if (fastestPickers.isEmpty)
                        _emptyNote('Not enough data yet.')
                      else
                        for (final m in fastestPickers)
                          ListTile(
                            title: Text(m.displayName),
                            trailing: Text(_formatMinutes(m.avgPickTimeMinutes!), style: TextStyle(color: AccaColors.textSecondary)),
                          ),
                      const SizedBox(height: 20),

                      _sectionHeader('Slowest picker'),
                      if (slowestPickers.isEmpty)
                        _emptyNote('Not enough data yet.')
                      else
                        for (final m in slowestPickers)
                          ListTile(
                            title: Text(m.displayName),
                            trailing: Text(_formatMinutes(m.avgPickTimeMinutes!), style: TextStyle(color: AccaColors.textSecondary)),
                          ),
                      const SizedBox(height: 20),

                      _sectionHeader('Most popular bet types'),
                      if (betTypeCounts.isEmpty)
                        _emptyNote('No legs submitted yet.')
                      else
                        for (final item in betTypeCounts) _popularityRow(item),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );

  Widget _emptyNote(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
      );

  Widget _streakRow(LeagueTableEntry e) => ListTile(
        title: Text(e.displayName),
        trailing: Text('${e.currentStreak} 🔥', style: const TextStyle(color: Colors.green)),
      );

  Widget _oddsCard(String name, AccumulatorLeg leg, Color accent) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(leg.decimalOddsAtSelection.toStringAsFixed(2), style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
              ],
            ),
            Text(leg.selectionDescription, style: TextStyle(fontSize: 12, color: AccaColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _averageOddsRow(MemberStats m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(m.displayName, style: const TextStyle(fontSize: 14)),
          Row(
            children: [
              if (m.averageWinningOdds != null)
                Text('W: ${m.averageWinningOdds!.toStringAsFixed(2)}', style: TextStyle(color: AccaColors.win, fontSize: 13)),
              if (m.averageWinningOdds != null && m.averageLosingOdds != null) const SizedBox(width: 12),
              if (m.averageLosingOdds != null)
                Text('L: ${m.averageLosingOdds!.toStringAsFixed(2)}', style: TextStyle(color: AccaColors.loss, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _popularityRow((BetType, int) item) {
    final maxCount = betTypeCounts.isNotEmpty ? betTypeCounts.first.$2 : 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(item.$1.displayName, style: const TextStyle(fontSize: 14)),
              Text('${item.$2}', style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) => Container(
              height: 6,
              width: constraints.maxWidth * (item.$2 / maxCount),
              decoration: BoxDecoration(color: AccaColors.gold, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ],
      ),
    );
  }
}