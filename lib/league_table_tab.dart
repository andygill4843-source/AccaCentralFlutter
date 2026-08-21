import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'firestore_service.dart';
import 'scoring_engine.dart';
import 'main.dart'; // for AccaColors
import 'app_state.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import 'models.dart';

class LeagueTableTab extends StatefulWidget {
  final AppState appState;
  final String teamId;
  final int refreshToken;
  const LeagueTableTab({super.key, required this.appState, required this.teamId, this.refreshToken = 0});
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
  Member? currentMember;
  Member? member;
  int unreadNotifications = 0;

  // --- Graph state ---
  Set<String>? _selectedMemberIds; // null = show every member
  int? _touchedGameWeek; // gameweek currently highlighted by a tap, null = none

  static const _brandGreen = Color(0xFF00E676); // swap for your real AccaColors green if you have one

  bool get isManager => currentMember?.role == MemberRole.manager;

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

      final userId = widget.appState.currentUser?.id;
      if (userId != null) {
        currentMember = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
      }
      final unreadCount = currentMember?.id != null
          ? await FirestoreService.instance.fetchUnreadNotificationCount(teamId: widget.teamId, memberId: currentMember!.id!)
          : 0;
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
        unreadNotifications = unreadCount;
        isLoading = false;
        // Keep the existing filter selection if it's still valid; otherwise fall back to "show everyone".
        if (_selectedMemberIds != null) {
          final validIds = currentEntries.map((e) => e.memberId).toSet();
          _selectedMemberIds = _selectedMemberIds!.intersection(validIds);
          if (_selectedMemberIds!.isEmpty) _selectedMemberIds = null;
        }
        _touchedGameWeek = null;
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
        title: currentSeason != null
            ? RichText(
                text: TextSpan(
                  children: [
                    const TextSpan(text: 'League Table — ', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                    TextSpan(text: currentSeason, style: const TextStyle(color: AccaColors.gold, fontSize: 20, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            : const Text('League Table'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Badge(
              label: Text('$unreadNotifications'),
              isLabelVisible: unreadNotifications > 0,
              child: Icon(Icons.notifications_outlined, color: unreadNotifications > 0 ? AccaColors.gold : Colors.white),
            ),
            onPressed: currentMember?.id == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => NotificationsScreen(teamId: widget.teamId, memberId: currentMember!.id!)),
                    );
                    load();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileScreen(appState: widget.appState, teamId: widget.teamId)),
            ),
          ),
        ],
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
                            _positionChart(),
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

  /// Evenly-spaced hues so any number of members gets a visually distinct colour,
  /// rather than a fixed 7-colour list that repeats once you pass 7 members.
  Color _memberColor(int index, int total) {
    final hue = (index * (360 / (total == 0 ? 1 : total))) % 360;
    return HSLColor.fromAHSL(1, hue, 0.65, 0.5).toColor();
  }

  Widget _memberFilterChips() {
    final allSelected = _selectedMemberIds == null;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        FilterChip(
          label: const Text('All'),
          selected: allSelected,
          onSelected: (_) => setState(() => _selectedMemberIds = null),
          selectedColor: _brandGreen.withValues(alpha: 0.25),
          checkmarkColor: _brandGreen,
          labelStyle: const TextStyle(fontSize: 11, color: Colors.white),
        ),
        for (final entry in entries)
          FilterChip(
            label: Text(entry.displayName),
            selected: allSelected || _selectedMemberIds!.contains(entry.memberId),
            onSelected: (selected) {
              setState(() {
                final current = _selectedMemberIds ?? entries.map((e) => e.memberId).toSet();
                final updated = Set<String>.from(current);
                if (selected) {
                  updated.add(entry.memberId);
                } else {
                  updated.remove(entry.memberId);
                }
                _selectedMemberIds = updated.length == entries.length ? null : updated;
              });
            },
            selectedColor: _brandGreen.withValues(alpha: 0.25),
            checkmarkColor: _brandGreen,
            labelStyle: const TextStyle(fontSize: 11, color: Colors.white),
          ),
      ],
    );
  }

  Widget _positionChart() {
    final weeks = positionHistory.keys.toList()..sort();
    final allMemberIds = entries.map((e) => e.memberId).toList();
    final visibleMemberIds = _selectedMemberIds == null
        ? allMemberIds
        : allMemberIds.where((id) => _selectedMemberIds!.contains(id)).toList();
    final worstPosition = entries.length; // highest position number = bottom of the table

    // fl_chart always plots low values at the bottom, high at the top. To get
    // position 1 at the TOP, we plot (worstPosition + 1 - position) and map the
    // axis tick labels back to real positions on display.
    double toChartY(int position) => (worstPosition + 1 - position).toDouble();
    int fromChartY(double chartY) => (worstPosition + 1 - chartY).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _brandGreen, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'League Table Tracker',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 2),
          const Text(
            'The race for the championship',
            style: TextStyle(fontWeight: FontWeight.normal, fontSize: 12, color: Colors.white),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: LineChart(
              LineChartData(
                minY: 1,
                maxY: worstPosition.toDouble(),
                minX: 1,
                maxX: weeks.isEmpty ? 2 : weeks.last.toDouble(),
                backgroundColor: Colors.transparent,
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) => FlLine(color: _brandGreen.withValues(alpha: 0.25), strokeWidth: 1),
                  getDrawingVerticalLine: (_) => FlLine(color: _brandGreen.withValues(alpha: 0.25), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('League Position', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (v, _) => Text(
                        '${fromChartY(v)}',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text('Gameweek', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                    axisNameSize: 20,
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: _brandGreen, width: 1),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    if (event is FlTapUpEvent &&
                        response != null &&
                        response.lineBarSpots != null &&
                        response.lineBarSpots!.isNotEmpty) {
                      final gw = response.lineBarSpots!.first.x.round();
                      setState(() {
                        _touchedGameWeek = (_touchedGameWeek == gw) ? null : gw;
                      });
                    }
                  },
                ),
                extraLinesData: _touchedGameWeek == null
                    ? const ExtraLinesData()
                    : ExtraLinesData(
                        verticalLines: [
                          VerticalLine(
                            x: _touchedGameWeek!.toDouble(),
                            color: _brandGreen,
                            strokeWidth: 2,
                            dashArray: [6, 4],
                            label: VerticalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.only(bottom: 4, left: 4),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _brandGreen),
                              labelResolver: (line) => 'GW${_touchedGameWeek}',
                            ),
                          ),
                        ],
                      ),
                lineBarsData: [
                  for (int i = 0; i < visibleMemberIds.length; i++)
                    LineChartBarData(
                      isCurved: true,
                      curveSmoothness: 0.55,
                      preventCurveOverShooting: true,
                      preventCurveOvershootingThreshold: 5,
                      color: _memberColor(allMemberIds.indexOf(visibleMemberIds[i]), allMemberIds.length),
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                          radius: 2.5,
                          color: bar.color ?? _brandGreen,
                          strokeWidth: 0,
                        ),
                      ),
                      spots: [
                        for (final week in weeks)
                          FlSpot(
                            week.toDouble(),
                            toChartY(positionHistory[week]!.indexWhere((e) => e.memberId == visibleMemberIds[i]) + 1),
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
              for (final id in visibleMemberIds)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: _memberColor(allMemberIds.indexOf(id), allMemberIds.length)),
                    const SizedBox(width: 4),
                    Text(
                      entries.firstWhere((e) => e.memberId == id).displayName,
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          _memberFilterChips(),
        ],
      ),
    );
  }
}