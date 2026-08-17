import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

class ChallengesScreen extends StatefulWidget {
  final String teamId;

  const ChallengesScreen({super.key, required this.teamId});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  List<Member> members = [];
  List<Challenge> challenges = [];
  bool isLoading = true;
  String? errorMessage;

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
      final loadedChallenges = await FirestoreService.instance.fetchChallenges(teamId: widget.teamId, season: team?.season ?? '');
      setState(() {
        members = loadedMembers;
        challenges = loadedChallenges;
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
    final remaining = (2 - lost).clamp(0, 2);
    return (remaining: remaining, placed: placed.length, won: won, lost: lost);
  }

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
                    child: _table(),
                  ),
                ),
    );
  }

  Widget _table() {
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
                      _headerCell('Remaining', 80),
                      _headerCell('Placed', 70),
                      _headerCell('Won', 60),
                      _headerCell('Lost', 60),
                      _headerCell('Win %', 70),
                    ],
                  ),
                  for (final member in members)
                    if (member.id != null)
                      Builder(builder: (context) {
                        final s = statsFor(member.id!);
                        final winPct = s.placed == 0 ? 0 : ((s.won / (s.won + s.lost).clamp(1, 999999)) * 100).round();
                        return Row(
                          children: [
                            _dataCell('${s.remaining}', 80),
                            _dataCell('${s.placed}', 70),
                            _dataCell('${s.won}', 60),
                            _dataCell('${s.lost}', 60),
                            _dataCell('$winPct%', 70),
                          ],
                        );
                      }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String label, double width) => Container(
        height: _headerHeight,
        width: width,
        alignment: Alignment.center,
        color: AccaColors.gold,
        child: Text(label, style: _headerTextStyle, textAlign: TextAlign.center),
      );

  Widget _dataCell(String value, double width) => Container(
        height: _rowHeight,
        width: width,
        alignment: Alignment.center,
        child: Text(value, style: _cellTextStyle),
      );
}