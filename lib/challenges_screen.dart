import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'odds_format.dart';
class ChallengesScreen extends StatefulWidget {
  final String teamId;
  const ChallengesScreen({super.key, required this.teamId});
  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}
class _ChallengesScreenState extends State<ChallengesScreen> {
  List<Member> members = [];
  List<Challenge> challenges = [];
  List<GameWeek> rawGameWeeks = [];
  String? teamCurrentSeason;
  List<String> allSeasons = [];
  String? selectedSeason;
  bool isLoading = true;
  String? errorMessage;
  int maxChallenges = 2;
  final Map<String, double> _statsColWidths = {
    'Remaining': 80, 'Placed': 70, 'Won': 60, 'Lost': 60, 'Win %': 70,
  };
  final Map<String, double> _historyColWidths = {
    'GW': 50, 'Date': 80, 'Challenger': 90, 'Challenged': 90,
    'Challenger Leg': 180, 'Challenger Odds': 80,
    'Challenged Leg': 180, 'Challenged Odds': 80, 'Outcome': 80,
  };
  static const double _minColWidth = 40;
  @override
  void initState() {
    super.initState();
    load();
  }
  Future<void> load() async {
    setState(() => isLoading = true);
    try {
      final team = await FirestoreService.instance.fetchTeam(widget.teamId);
      final loadedMembers = await FirestoreService.instance.fetchMembers(widget.teamId);
      final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);
      teamCurrentSeason = team?.season;
      selectedSeason ??= teamCurrentSeason;
      final seasonsFromGameWeeks = gameWeeks.map((g) => g.season).toSet();
      allSeasons = (<String>{
        ...seasonsFromGameWeeks,
        ?teamCurrentSeason,
      }..removeWhere((s) => s.isEmpty)).toList()
        ..sort((a, b) => b.compareTo(a));
      final activeSeason = selectedSeason ?? teamCurrentSeason ?? '';
      final loadedChallenges = await FirestoreService.instance.fetchChallenges(teamId: widget.teamId, season: activeSeason);
      final seasonSettings = await FirestoreService.instance.fetchSeasonSettings(teamId: widget.teamId, season: activeSeason);
      setState(() {
        members = loadedMembers;
        rawGameWeeks = gameWeeks;
        challenges = loadedChallenges;
        maxChallenges = seasonSettings?.maxChallengesPerMember ?? 2;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }
  Future<void> onSeasonChanged(String? newSeason) async {
    if (newSeason == null || newSeason == selectedSeason) return;
    setState(() {
      selectedSeason = newSeason;
      isLoading = true;
    });
    try {
      final loadedChallenges = await FirestoreService.instance.fetchChallenges(teamId: widget.teamId, season: newSeason);
      final seasonSettings = await FirestoreService.instance.fetchSeasonSettings(teamId: widget.teamId, season: newSeason);
      setState(() {
        challenges = loadedChallenges;
        maxChallenges = seasonSettings?.maxChallengesPerMember ?? 2;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }
  ({int remaining, int placed, int won, int lost}) statsFor(String memberId) {
    final placed = challenges.where((c) => c.challengerMemberId == memberId);
    final resolved = placed.where((c) => c.status == ChallengeStatus.resolved);
    final won = resolved.where((c) => c.challengerWon == true).length;
    final lost = resolved.where((c) => c.challengerWon == false).length;
    final remaining = (maxChallenges - lost).clamp(0, maxChallenges);
    return (remaining: remaining, placed: placed.length, won: won, lost: lost);
  }
  List<Challenge> get _sortedChallenges {
    final gwById = {for (final g in rawGameWeeks) if (g.id != null) g.id!: g};
    final sorted = [...challenges];
    sorted.sort((a, b) {
      final gwA = gwById[a.gameWeekId]?.weekNumber ?? 0;
      final gwB = gwById[b.gameWeekId]?.weekNumber ?? 0;
      final weekCompare = gwB.compareTo(gwA);
      if (weekCompare != 0) return weekCompare;
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }
  String _outcomeLabel(Challenge c) {
    switch (c.status) {
      case ChallengeStatus.pendingAcceptance:
        return 'Awaiting response';
      case ChallengeStatus.declined:
        return 'Declined';
      case ChallengeStatus.active:
        return 'In progress';
      case ChallengeStatus.resolved:
        if (c.challengerWon == null) return 'Pending';
        return c.challengerWon! ? 'Challenger Won' : 'Challenger Lost';
    }
  }
  Color _outcomeColor(Challenge c) {
    switch (c.status) {
      case ChallengeStatus.pendingAcceptance:
        return AccaColors.gold;
      case ChallengeStatus.declined:
        return AccaColors.loss;
      case ChallengeStatus.active:
        return AccaColors.textSecondary;
      case ChallengeStatus.resolved:
        if (c.challengerWon == null) return AccaColors.textSecondary;
        return c.challengerWon! ? AccaColors.win : AccaColors.loss;
    }
  }
  String _formatDateOnly(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
  static const _rowHeight = 32.0;
  static const _headerHeight = 32.0;
  static const _cellTextStyle = TextStyle(fontSize: 11, color: Colors.black);
  static const _headerTextStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenges'),
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (allSeasons.isNotEmpty) ...[
                          const Text('Season', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: selectedSeason,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AccaColors.gold, width: 1.5),
                              ),
                            ),
                            dropdownColor: Colors.white,
                            style: const TextStyle(fontSize: 14, color: Colors.black),
                            items: allSeasons
                                .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.black))))
                                .toList(),
                            onChanged: onSeasonChanged,
                          ),
                          const SizedBox(height: 20),
                        ],
                        _table(),
                        const SizedBox(height: 28),
                        const Text('Challenge History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                        const SizedBox(height: 8),
                        _historyTable(),
                      ],
                    ),
                  ),
                ),
    );
  }
  void _resizeCol(Map<String, double> map, String col, double delta) {
    setState(() => map[col] = ((map[col] ?? 80) + delta).clamp(_minColWidth, 500));
  }
  Widget _resizeHandle(Map<String, double> map, String col) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => _resizeCol(map, col, d.delta.dx),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: Container(width: 12, alignment: Alignment.center, child: Container(width: 2, color: Colors.black26)),
        ),
      );
  Widget _rHeaderCell(Map<String, double> map, String label) => Container(
        height: _headerHeight,
        width: map[label] ?? 80,
        color: AccaColors.gold,
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(label, style: _headerTextStyle, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              ),
            ),
            _resizeHandle(map, label),
          ],
        ),
      );
  Widget _rDataCell(Map<String, double> map, String col, Widget child) => Container(
        height: _rowHeight,
        width: map[col] ?? 80,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: child,
      );
  Widget _table() {
    if (members.isEmpty) return const Text('No members yet.', style: TextStyle(color: Colors.white70));
    final statsCols = ['Remaining', 'Placed', 'Won', 'Lost', 'Win %'];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccaColors.gold, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black26))),
              child: Column(
                children: [
                  Container(height: _headerHeight, width: 90, alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8), color: AccaColors.gold,
                      child: const Text('User', style: _headerTextStyle)),
                  for (final member in members)
                    if (member.id != null)
                      Container(height: _rowHeight, width: 90, alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(member.displayName, style: _cellTextStyle, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: [
                    Row(children: [for (final c in statsCols) _rHeaderCell(_statsColWidths, c)]),
                    for (final member in members)
                      if (member.id != null)
                        Builder(builder: (context) {
                          final s = statsFor(member.id!);
                          final winPct = s.placed == 0 ? 0 : ((s.won / (s.won + s.lost).clamp(1, 999999)) * 100).round();
                          return Row(children: [
                            _rDataCell(_statsColWidths, 'Remaining', Text('${s.remaining}', style: _cellTextStyle)),
                            _rDataCell(_statsColWidths, 'Placed', Text('${s.placed}', style: _cellTextStyle)),
                            _rDataCell(_statsColWidths, 'Won', Text('${s.won}', style: _cellTextStyle)),
                            _rDataCell(_statsColWidths, 'Lost', Text('${s.lost}', style: _cellTextStyle)),
                            _rDataCell(_statsColWidths, 'Win %', Text('$winPct%', style: _cellTextStyle)),
                          ]);
                        }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _historyTable() {
    final gwById = {for (final g in rawGameWeeks) if (g.id != null) g.id!: g};
    final sorted = _sortedChallenges;
    if (sorted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No challenges placed this season.', style: TextStyle(color: Colors.white70)),
      );
    }
    final historyCols = ['GW', 'Date', 'Challenger', 'Challenged', 'Challenger Leg', 'Challenger Odds', 'Challenged Leg', 'Challenged Odds', 'Outcome'];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccaColors.gold, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [for (final c in historyCols) _rHeaderCell(_historyColWidths, c)]),
              for (final c in sorted)
                Row(children: [
                  _rDataCell(_historyColWidths, 'GW', Text('${gwById[c.gameWeekId]?.weekNumber ?? '—'}', style: _cellTextStyle)),
                  _rDataCell(_historyColWidths, 'Date', Text(gwById[c.gameWeekId] != null ? _formatDateOnly(gwById[c.gameWeekId]!.startDate) : '—', style: _cellTextStyle)),
                  _rDataCell(_historyColWidths, 'Challenger', Text(c.challengerName, style: _cellTextStyle, overflow: TextOverflow.ellipsis)),
                  _rDataCell(_historyColWidths, 'Challenged', Text(c.challengedName, style: _cellTextStyle, overflow: TextOverflow.ellipsis)),
                  _rDataCell(_historyColWidths, 'Challenger Leg', Text(c.challengerLegDescription ?? '—', style: _cellTextStyle, overflow: TextOverflow.ellipsis)),
                  _rDataCell(_historyColWidths, 'Challenger Odds', Text(c.challengerLegOdds != null ? decimalToFractional(c.challengerLegOdds!) : '—', style: _cellTextStyle)),
                  _rDataCell(_historyColWidths, 'Challenged Leg', Text(c.challengedLegDescription, style: _cellTextStyle, overflow: TextOverflow.ellipsis)),
                  _rDataCell(_historyColWidths, 'Challenged Odds', Text(decimalToFractional(c.challengedLegOdds), style: _cellTextStyle)),
                  _rDataCell(_historyColWidths, 'Outcome', Text(_outcomeLabel(c), style: TextStyle(fontSize: 12, color: _outcomeColor(c), fontWeight: FontWeight.bold))),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}