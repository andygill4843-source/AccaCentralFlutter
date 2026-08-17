import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'firestore_service.dart';
import 'scoring_engine.dart';
import 'main.dart'; // for AccaColors

class LeagueTableTab extends StatefulWidget {
  final String teamId;
  final int refreshToken;

  const LeagueTableTab({super.key, required this.teamId, this.refreshToken = 0});


  @override
  State<LeagueTableTab> createState() => _LeagueTableTabState();
}

class _LeagueTableTabState extends State<LeagueTableTab> {
  List<LeagueTableEntry> entries = [];
  Map<String, int?> formDelta = {};
  Map<int, List<LeagueTableEntry>> positionHistory = {};
  bool isLoading = true;
  String? errorMessage;
  String? currentSeason;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant LeagueTableTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId || oldWidget.refreshToken != widget.refreshToken) {
      load();
    }
  }

  Future<void> load() async {
    try {
      final team = await FirestoreService.instance.fetchTeam(widget.teamId);
      currentSeason = team?.season;

      final members = await FirestoreService.instance.fetchMembers(widget.teamId);
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);

      final currentSeasonGameWeeks = gameWeeks.where((g) => g.season == team?.season).toList();
      final currentSeasonGameWeekIds = currentSeasonGameWeeks.map((g) => g.id).toSet();
      final currentSeasonLegs = legs.where((l) => currentSeasonGameWeekIds.contains(l.gameWeekId)).toList();

      final challenges = await FirestoreService.instance.fetchChallenges(teamId: widget.teamId, season: team?.season ?? '');

      final currentEntries = ScoringEngine.buildLeagueTable(members: members, legs: currentSeasonLegs, challenges: challenges);

      final settledWeeks = currentSeasonGameWeeks.where((g) => g.isSettled).toList()
        ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));

      final Map<String, int?> delta = {};
      if (settledWeeks.length >= 2) {
        final latestWeek = settledWeeks.last;
        final previousGameWeekIds = settledWeeks.where((g) => g.weekNumber < latestWeek.weekNumber).map((g) => g.id).toSet();
        final previousLegs = currentSeasonLegs.where((l) => previousGameWeekIds.contains(l.gameWeekId)).toList();
        final previousEntries = ScoringEngine.buildLeagueTable(members: members, legs: previousLegs, challenges: challenges);

        final Map<String, int> previousPosition = {
          for (int i = 0; i < previousEntries.length; i++) previousEntries[i].memberId: i + 1,
        };
        for (int i = 0; i < currentEntries.length; i++) {
          final memberId = currentEntries[i].memberId;
          final currentPos = i + 1;
          final prevPos = previousPosition[memberId];
          delta[memberId] = prevPos != null ? prevPos - currentPos : null;
        }
      } else {
        for (final e in currentEntries) {
          delta[e.memberId] = null;
        }
      }

      final Map<int, List<LeagueTableEntry>> history = {};
      for (final week in settledWeeks) {
        final upToWeekIds = settledWeeks.where((g) => g.weekNumber <= week.weekNumber).map((g) => g.id).toSet();
        final legsUpToWeek = currentSeasonLegs.where((l) => upToWeekIds.contains(l.gameWeekId)).toList();
        history[week.weekNumber] = ScoringEngine.buildLeagueTable(members: members, legs: legsUpToWeek, challenges: challenges);
      }

      setState(() {
        entries = currentEntries;
        formDelta = delta;
        positionHistory = history;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(currentSeason != null ? 'League Table — $currentSeason' : 'League Table'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: RefreshIndicator(
        onRefresh: load,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
                : entries.isEmpty
                    ? const Center(child: Text('No members found for this team.'))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _frozenColumnTable(),
                            const SizedBox(height: 24),
                            if (positionHistory.length >= 2) _positionChart(),
                          ],
                        ),
                      ),
      ),
    );
  }

  static const _rowHeight = 36.0;
  static const _headerHeight = 34.0;
  static const _cellTextStyle = TextStyle(fontSize: 12, color: Colors.black);
  static const _headerTextStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black);

  Widget _frozenColumnTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccaColors.gold, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Colors.black26)),
            ),
            child: Column(
              children: [
                Container(
                  height: _headerHeight,
                  width: 100,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  color: AccaColors.gold,
                  child: const Text('User', style: _headerTextStyle),
                ),
                for (final entry in entries)
                  Container(
                    height: _rowHeight,
                    width: 100,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(entry.displayName, style: _cellTextStyle, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                children: [
                  Row(
                    children: [
                      _headerCell('Legs', 60),
                      _headerCell('Points', 70),
                      _headerCell('Weighted', 80),
                      _headerCell('Form', 70),
                    ],
                  ),
                  for (final entry in entries)
                    Row(
                      children: [
                        _dataCell('${entry.legsPlayed}', 60),
                        _dataCell('${entry.totalBasePoints}', 70),
                        _dataCell(entry.totalWeightedPoints.toStringAsFixed(1), 80),
                        _formCell(formDelta[entry.memberId], 70),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String label, double width) {
    return Container(
      height: _headerHeight,
      width: width,
      alignment: Alignment.center,
      color: AccaColors.gold,
      child: Text(label, style: _headerTextStyle),
    );
  }

  Widget _dataCell(String value, double width) {
    return Container(
      height: _rowHeight,
      width: width,
      alignment: Alignment.center,
      child: Text(value, style: _cellTextStyle),
    );
  }

  Widget _formCell(int? delta, double width) {
    Widget content;
    if (delta == null || delta == 0) {
      content = const Text('—', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFCA8A04)));
    } else if (delta > 0) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_upward, size: 13, color: AccaColors.win),
          Text(' $delta', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AccaColors.win)),
        ],
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_downward, size: 13, color: AccaColors.loss),
          Text(' ${delta.abs()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AccaColors.loss)),
        ],
      );
    }
    return Container(height: _rowHeight, width: width, alignment: Alignment.center, child: content);
  }

  Widget _positionChart() {
    final weeks = positionHistory.keys.toList()..sort();
    final memberIds = entries.map((e) => e.memberId).toList();
    final colors = [AccaColors.gold, Colors.blue, Colors.orange, Colors.purple, Colors.pink, Colors.teal, Colors.brown];

    return Container(
      height: 260,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccaColors.gold, width: 1.5),
      ),
      child: Column(
        children: [
          const Align(alignment: Alignment.centerLeft, child: Text('Position over the season', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black))),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 1,
                maxY: entries.length.toDouble(),
                gridData: const FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: 1, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 10))),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, interval: 1, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 10))),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                lineTouchData: const LineTouchData(enabled: true),
                lineBarsData: [
                  for (int i = 0; i < memberIds.length; i++)
                    LineChartBarData(
                      isCurved: false,
                      color: colors[i % colors.length],
                      barWidth: 2,
                      dotData: const FlDotData(show: true),
                      spots: [
                        for (final week in weeks)
                          FlSpot(
                            week.toDouble(),
                            (positionHistory[week]!.indexWhere((e) => e.memberId == memberIds[i]) + 1).toDouble(),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              for (int i = 0; i < memberIds.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: colors[i % colors.length]),
                    const SizedBox(width: 4),
                    Text(entries.firstWhere((e) => e.memberId == memberIds[i]).displayName, style: const TextStyle(fontSize: 10, color: Colors.black)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}