import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'place_fine_screen.dart';
import 'main.dart'; // for AccaColors
import 'package:collection/collection.dart';
import 'manage_fines_screen.dart';

class FinesScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;

  const FinesScreen({super.key, required this.appState, required this.teamId});

  @override
  State<FinesScreen> createState() => _FinesScreenState();
}

class _FinesScreenState extends State<FinesScreen> {
  List<Fine> fines = [];
  List<Member> members = [];
  Member? currentMember;
  bool isLoading = true;
  String? errorMessage;

  bool get isManager => currentMember?.role == MemberRole.manager;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    try {
      final userId = widget.appState.currentUser?.id;
      final loadedMembers = await FirestoreService.instance.fetchMembers(widget.teamId);
      final loadedFines = await FirestoreService.instance.fetchFines(widget.teamId);
      Member? me;
      if (userId != null) {
        me = loadedMembers.where((m) => m.userId == userId).firstOrNull;
      }
      setState(() {
        members = loadedMembers;
        fines = loadedFines;
        currentMember = me;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  List<Fine> get myPendingFines =>
      fines.where((f) => f.memberId == currentMember?.id && f.status == FineStatus.pending).toList();

  List<Fine> get activeDisputes => fines.where((f) => f.status == FineStatus.disputed).toList();

  Map<String, Map<FineType, int>> get allTimeTally {
    final Map<String, Map<FineType, int>> result = {};
    for (final member in members) {
      if (member.id == null) continue;
      result[member.id!] = {for (final t in FineType.values) t: 0};
    }
    for (final fine in fines.where((f) => f.status != FineStatus.overturned)) {
      result.putIfAbsent(fine.memberId, () => {for (final t in FineType.values) t: 0});
      result[fine.memberId]![fine.fineType] = (result[fine.memberId]![fine.fineType] ?? 0) + 1;
    }
    return result;
  }

  Map<String, Map<FineType, int>> get tally {
    final Map<String, Map<FineType, int>> result = {};
    for (final member in members) {
      if (member.id == null) continue;
      result[member.id!] = {for (final t in FineType.values) t: 0};
    }
    for (final fine in fines.where((f) => f.countsTowardTally)) {
      result.putIfAbsent(fine.memberId, () => {for (final t in FineType.values) t: 0});
      result[fine.memberId]![fine.fineType] = (result[fine.memberId]![fine.fineType] ?? 0) + 1;
    }
    return result;
  }

  Future<void> respond(Fine fine, bool accept) async {
    if (fine.id == null) return;
    try {
      await FirestoreService.instance.respondToFine(fineId: fine.id!, accept: accept);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  Future<void> vote(Fine fine, bool upholds) async {
    if (fine.id == null || currentMember?.id == null) return;
    try {
      await FirestoreService.instance.voteOnFine(fineId: fine.id!, memberId: currentMember!.id!, upholds: upholds);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fines'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
        actions: isManager
            ? [
                IconButton(
                  icon: const Icon(Icons.check_circle_outline),
                  tooltip: 'Confirm fines paid',
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ManageFinesScreen(teamId: widget.teamId)),
                    );
                    load();
                  },
                ),
              ]
            : null,
      ),
      backgroundColor: AccaColors.background,
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () async {
                final placed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => PlaceFineScreen(
                      teamId: widget.teamId,
                      members: members,
                      createdByMemberId: currentMember!.id!,
                      createdByName: widget.appState.currentUser?.displayName ?? 'Manager',
                    ),
                  ),
                );
                if (placed == true) load();
              },
              backgroundColor: AccaColors.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add),
              label: const Text('Place fine', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (myPendingFines.isNotEmpty) ...[
                        _sectionHeader('Fines awaiting your response'),
                        for (final fine in myPendingFines) _pendingFineCard(fine),
                        const SizedBox(height: 20),
                      ],
                      if (activeDisputes.isNotEmpty) ...[
                        _sectionHeader('Active disputes — vote now'),
                        for (final fine in activeDisputes) _disputeCard(fine),
                        const SizedBox(height: 20),
                      ],
                      _sectionHeader('Fine tally'),
                      _tallyTable(),
                      const SizedBox(height: 80), // room for the FAB
                    ],
                  ),
                ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _pendingFineCard(Fine fine) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fine.fineType.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('From: ${fine.createdByName}', style: TextStyle(fontSize: 12, color: AccaColors.textSecondary)),
            const SizedBox(height: 4),
            Text(fine.reason),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => respond(fine, true),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => respond(fine, false),
                    style: OutlinedButton.styleFrom(foregroundColor: AccaColors.loss),
                    child: const Text('Dispute'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _disputeCard(Fine fine) {
    final isFinedMember = currentMember?.id == fine.memberId;
    final hasVoted = currentMember?.id != null && fine.votes.containsKey(currentMember!.id);
    final upholdCount = fine.votes.values.where((v) => v == true).length;
    final overturnCount = fine.votes.values.where((v) => v == false).length;
    final daysLeft = fine.disputeDeadline != null ? fine.disputeDeadline!.difference(DateTime.now()).inDays : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${fine.memberName} — ${fine.fineType.displayName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(fine.reason, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text('$daysLeft day${daysLeft == 1 ? '' : 's'} left to vote · Uphold: $upholdCount · Overturn: $overturnCount',
                style: TextStyle(fontSize: 12, color: AccaColors.textSecondary)),
            const SizedBox(height: 8),
            if (isFinedMember)
              const Text('This is your fine — you can\'t vote on it.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12))
            else if (hasVoted)
              Text('You voted: ${fine.votes[currentMember!.id!] == true ? "Uphold" : "Overturn"}',
                  style: const TextStyle(fontWeight: FontWeight.w600))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => vote(fine, true), child: const Text('Uphold fine')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(onPressed: () => vote(fine, false), child: const Text('Overturn')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static const _rowHeight = 32.0;
  static const _headerHeight = 32.0;
  static const _cellTextStyle = TextStyle(fontSize: 11, color: Colors.black);
  static const _headerTextStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black);

  Widget _tallyTable() {
    if (members.isEmpty) return const Text('No members yet.', style: TextStyle(color: Colors.white70));

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
            decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black26))),
            child: Column(
              children: [
                Container(
                  height: _headerHeight,
                  width: 90,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  color: AccaColors.gold,
                  child: const Text('User', style: _headerTextStyle),
                ),
                for (final member in members)
                  if (member.id != null)
                    Container(
                      height: _rowHeight,
                      width: 90,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(member.displayName, style: _cellTextStyle, overflow: TextOverflow.ellipsis),
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
                      for (final type in FineType.values) _headerCell(type.displayName, 90),
                      _headerCell('Total fines', 80),
                      _headerCell('Outstanding', 80),
                    ],
                  ),
                  for (final member in members)
                    if (member.id != null)
                      Row(
                        children: [
                          for (final type in FineType.values) _dataCell('${allTimeTally[member.id]?[type] ?? 0}', 90),
                          _dataCell('${FineType.values.fold<int>(0, (sum, t) => sum + (allTimeTally[member.id]?[t] ?? 0))}', 80),
                          _dataCell('${FineType.values.fold<int>(0, (sum, t) => sum + (tally[member.id]?[t] ?? 0))}', 80),
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
      child: Text(label, style: _headerTextStyle, textAlign: TextAlign.center),
    );
  }

  Widget _dataCell(String value, double width) {
    return Container(height: _rowHeight, width: width, alignment: Alignment.center, child: Text(value, style: _cellTextStyle));
  }
}