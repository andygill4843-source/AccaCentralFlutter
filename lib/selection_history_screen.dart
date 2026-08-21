import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'profile_screen.dart';
import 'notifications_screen.dart';

class _HistoryRow {
  final AccumulatorLeg leg;
  final GameWeek gameWeek;
  final String memberName;
  _HistoryRow({required this.leg, required this.gameWeek, required this.memberName});
}

extension _OutcomeLabel on LegOutcome {
  String get label {
    switch (this) {
      case LegOutcome.pending: return 'Pending';
      case LegOutcome.won: return 'Won';
      case LegOutcome.lost: return 'Lost';
      case LegOutcome.void_: return 'Void';
    }
  }

  Color get color {
    switch (this) {
      case LegOutcome.pending: return AccaColors.textSecondary;
      case LegOutcome.won: return AccaColors.win;
      case LegOutcome.lost: return AccaColors.loss;
      case LegOutcome.void_: return Colors.orange;
    }
  }
}

class SelectionHistoryScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;
  const SelectionHistoryScreen({super.key, required this.appState, required this.teamId});

  @override
  State<SelectionHistoryScreen> createState() => _SelectionHistoryScreenState();
}

class _SelectionHistoryScreenState extends State<SelectionHistoryScreen> {
  List<Member> rawMembers = [];
  List<AccumulatorLeg> rawLegs = [];
  List<GameWeek> rawGameWeeks = [];
  String? teamCurrentSeason;
  List<String> allSeasons = [];
  String? selectedSeason;

  String? filterMemberId; // null = All
  BetType? filterBetType; // null = All
  LegOutcome? filterOutcome; // null = All
  int? filterWeekNumber; // null = All

  Member? currentMember;
  int unreadNotifications = 0;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final userId = widget.appState.currentUser?.id;
      final team = await FirestoreService.instance.fetchTeam(widget.teamId);
      final members = await FirestoreService.instance.fetchMembers(widget.teamId);
      final legs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final gameWeeks = await FirestoreService.instance.fetchGameWeeks(widget.teamId);
      if (userId != null) {
        currentMember = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
      }
      final unreadCount = currentMember?.id != null
          ? await FirestoreService.instance.fetchUnreadNotificationCount(teamId: widget.teamId, memberId: currentMember!.id!)
          : 0;

      rawMembers = members;
      rawLegs = legs;
      rawGameWeeks = gameWeeks;
      teamCurrentSeason = team?.season;
      selectedSeason ??= teamCurrentSeason;

      final seasonsFromGameWeeks = gameWeeks.map((g) => g.season).toSet();
      allSeasons = (<String>{
        ...seasonsFromGameWeeks,
        if (teamCurrentSeason != null) teamCurrentSeason!,
      }..removeWhere((s) => s.isEmpty)).toList()
        ..sort((a, b) => b.compareTo(a));

      // Filter selections that no longer apply once the season/data changes.
      final seasonMemberIds = _seasonRows.map((r) => r.leg.memberId).toSet();
      if (filterMemberId != null && !seasonMemberIds.contains(filterMemberId)) filterMemberId = null;
      final seasonWeekNumbers = _seasonRows.map((r) => r.gameWeek.weekNumber).toSet();
      if (filterWeekNumber != null && !seasonWeekNumbers.contains(filterWeekNumber)) filterWeekNumber = null;

      setState(() {
        unreadNotifications = unreadCount;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  void onSeasonChanged(String? newSeason) {
    if (newSeason == null) return;
    setState(() {
      selectedSeason = newSeason;
      filterMemberId = null;
      filterBetType = null;
      filterOutcome = null;
      filterWeekNumber = null;
    });
  }

  List<_HistoryRow> get _seasonRows {
    final gwById = {for (final g in rawGameWeeks) if (g.id != null) g.id!: g};
    final memberNameById = {for (final m in rawMembers) if (m.id != null) m.id!: m.displayName};
    final rows = <_HistoryRow>[];
    for (final leg in rawLegs) {
      final gw = gwById[leg.gameWeekId];
      if (gw == null || gw.season != selectedSeason) continue;
      rows.add(_HistoryRow(
        leg: leg,
        gameWeek: gw,
        memberName: memberNameById[leg.memberId] ?? 'Unknown',
      ));
    }
    rows.sort((a, b) {
      final weekCompare = b.gameWeek.weekNumber.compareTo(a.gameWeek.weekNumber);
      if (weekCompare != 0) return weekCompare;
      return a.memberName.compareTo(b.memberName);
    });
    return rows;
  }

  List<_HistoryRow> get _filteredRows {
    return _seasonRows.where((r) {
      if (filterMemberId != null && r.leg.memberId != filterMemberId) return false;
      if (filterBetType != null && r.leg.betType != filterBetType) return false;
      if (filterOutcome != null && r.leg.outcome != filterOutcome) return false;
      if (filterWeekNumber != null && r.gameWeek.weekNumber != filterWeekNumber) return false;
      return true;
    }).toList();
  }

  bool get _hasActiveFilters =>
      filterMemberId != null || filterBetType != null || filterOutcome != null || filterWeekNumber != null;

  String _formatDateOnly(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    final seasonRows = _seasonRows;
    final memberOptions = {for (final r in seasonRows) r.leg.memberId: r.memberName};
    final betTypeOptions = seasonRows.map((r) => r.leg.betType).toSet().toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final weekOptions = seasonRows.map((r) => r.gameWeek.weekNumber).toSet().toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(text: 'Selection ', style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
              TextSpan(text: 'History', style: GoogleFonts.poppins(color: const Color(0xFF00E676), fontSize: 20, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
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
                          style: accaFieldTextStyle,
                          items: allSeasons
                              .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.black))))
                              .toList(),
                          onChanged: onSeasonChanged,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                          if (_hasActiveFilters)
                            TextButton(
                              onPressed: () => setState(() {
                                filterMemberId = null;
                                filterBetType = null;
                                filterOutcome = null;
                                filterWeekNumber = null;
                              }),
                              child: const Text('Clear filters', style: TextStyle(color: AccaColors.gold, fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _filterDropdown<String?>(
                            label: 'User',
                            value: filterMemberId,
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All')),
                              for (final entry in memberOptions.entries)
                                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                            ],
                            onChanged: (v) => setState(() => filterMemberId = v),
                          ),
                          _filterDropdown<BetType?>(
                            label: 'Bet type',
                            value: filterBetType,
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All')),
                              for (final bt in betTypeOptions) DropdownMenuItem(value: bt, child: Text(bt.displayName)),
                            ],
                            onChanged: (v) => setState(() => filterBetType = v),
                          ),
                          _filterDropdown<LegOutcome?>(
                            label: 'Status',
                            value: filterOutcome,
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All')),
                              for (final o in LegOutcome.values) DropdownMenuItem(value: o, child: Text(o.label)),
                            ],
                            onChanged: (v) => setState(() => filterOutcome = v),
                          ),
                          _filterDropdown<int?>(
                            label: 'Gameweek',
                            value: filterWeekNumber,
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All')),
                              for (final w in weekOptions) DropdownMenuItem(value: w, child: Text('GW$w')),
                            ],
                            onChanged: (v) => setState(() => filterWeekNumber = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No selections match these filters.', style: TextStyle(color: Colors.white70)),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AccaColors.gold, width: 1.5),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(AccaColors.gold),
                              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black),
                              dataTextStyle: const TextStyle(fontSize: 12, color: Colors.black),
                              columns: const [
                                DataColumn(label: Text('GW')),
                                DataColumn(label: Text('Date')),
                                DataColumn(label: Text('User')),
                                DataColumn(label: Text('Bet details')),
                                DataColumn(label: Text('Bet type')),
                                DataColumn(label: Text('Status')),
                              ],
                              rows: [
                                for (final r in rows)
                                  DataRow(
                                    cells: [
                                      DataCell(Text('${r.gameWeek.weekNumber}')),
                                      DataCell(Text(_formatDateOnly(r.gameWeek.startDate))),
                                      DataCell(Text(r.memberName)),
                                      DataCell(SizedBox(width: 220, child: Text(r.leg.selectionDescription, overflow: TextOverflow.ellipsis))),
                                      DataCell(Text(r.leg.betType.displayName)),
                                      DataCell(Text(r.leg.outcome.label, style: TextStyle(color: r.leg.outcome.color, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _filterDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T> onChanged,
  }) {
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11, color: Colors.white70),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AccaColors.gold, width: 1.5),
          ),
        ),
        dropdownColor: Colors.white,
        style: const TextStyle(fontSize: 12, color: Colors.black),
        items: items,
        onChanged: (v) => onChanged(v as T),
      ),
    );
  }
}