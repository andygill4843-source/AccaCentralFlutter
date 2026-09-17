import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'odds_format.dart';

class TournamentView extends StatefulWidget {
  final AppState appState;
  final String teamId;
  final Tournament tournament;
  const TournamentView({super.key, required this.appState, required this.teamId, required this.tournament});
  @override
  State<TournamentView> createState() => _TournamentViewState();
}

class _TournamentViewState extends State<TournamentView> {
  Tournament? tournament;
  List<TournamentMatch> allMatches = [];
  List<AccumulatorLeg> tournamentLegs = [];
  bool isManager = false;
  bool isLoading = true;
  bool isBusy = false; // drawing
  final Map<String, double> _selectionsColWidths = {
    'Round': 90, 'Date': 80, 'Member': 90, 'Leg': 70,
    'Selection': 160, 'Odds': 60, 'Winner': 80,
  };
  static const double _minColWidth = 40;
  bool isRevealing = false; // reveal-one-by-one in progress
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant TournamentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tournament.id != widget.tournament.id) {
      load();
    }
  }

  /// Loads the CURRENT state of widget.tournament by ID — not by
  /// team+season, since a team can now have several tournaments at once
  /// and this widget always represents one specific one, passed in from
  /// TournamentScreen's swipeable pages.
  Future<void> load() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final userId = widget.appState.currentUser?.id;
      if (userId != null) {
        final member = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
        isManager = member?.role == MemberRole.manager;
      }
      final tournamentId = widget.tournament.id;
      if (tournamentId == null) {
        if (!mounted) return;
        setState(() {
          tournament = widget.tournament;
          isLoading = false;
        });
        return;
      }
      final t = await FirestoreService.instance.fetchTournamentById(tournamentId);
      List<TournamentMatch> matches = [];
      List<AccumulatorLeg> legs = [];
      if (t != null) {
        matches = await FirestoreService.instance.fetchTournamentMatches(teamId: widget.teamId, tournamentId: tournamentId);
        final matchIds = {for (final m in matches) if (m.id != null) m.id!};
        final allLegs = await FirestoreService.instance.fetchLegs(widget.teamId);
        legs = allLegs.where((l) => l.tournamentMatchId != null && matchIds.contains(l.tournamentMatchId)).toList();
      }
      if (!mounted) return;
      setState(() {
        tournament = t ?? widget.tournament;
        allMatches = matches;
        tournamentLegs = legs;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  List<TournamentMatch> get _currentRoundMatches {
    final t = tournament;
    if (t == null || t.currentRoundSize == null) return [];
    return allMatches.where((m) => m.roundSize == t.currentRoundSize).toList();
  }

  bool get _allRevealed => _currentRoundMatches.isNotEmpty && _currentRoundMatches.every((m) => m.revealed);
  bool get _allSettled => _currentRoundMatches.isNotEmpty && _currentRoundMatches.every((m) => m.winnerMemberId != null);

  Future<void> drawRound() async {
    final t = tournament;
    if (t == null) return;
    setState(() {
      isBusy = true;
      errorMessage = null;
    });
    try {
      if (t.currentRoundSize == null) {
        await FirestoreService.instance.drawInitialTournamentRound(t);
      } else {
        await FirestoreService.instance.drawNextTournamentRound(t);
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  Future<void> revealAll() async {
    final t = tournament;
    if (t == null || t.id == null || t.currentRoundSize == null) return;
    setState(() => isRevealing = true);
    try {
      await FirestoreService.instance.revealAllTournamentMatches(
        tournamentId: t.id!,
        roundSize: t.currentRoundSize!,
        teamId: widget.teamId,
        tournamentName: t.name,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't reveal draw: $e")));
      }
    } finally {
      if (mounted) setState(() => isRevealing = false);
    }
  }

  Future<void> revealOneByOne() async {
    final t = tournament;
    if (t == null || t.id == null || t.currentRoundSize == null) return;
    setState(() => isRevealing = true);
    try {
      await FirestoreService.instance.notifyTournamentDrawStarting(teamId: widget.teamId, tournamentName: t.name);
      var hasMore = true;
      while (hasMore && mounted) {
        hasMore = await FirestoreService.instance.revealNextTournamentMatch(
          tournamentId: t.id!,
          roundSize: t.currentRoundSize!,
          teamId: widget.teamId,
          tournamentName: t.name,
        );
        await load();
        if (hasMore && mounted) await Future.delayed(const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't reveal draw: $e")));
      }
    } finally {
      if (mounted) setState(() => isRevealing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No RefreshIndicator/Scaffold here deliberately — this widget is
    // designed to be embedded inside another screen's own scrollable body
    // (e.g. TournamentScreen's PageView pages), so it can't own its own
    // scroll gesture or pull-to-refresh without conflicting with the
    // parent. shrinkWrap + non-scrollable physics let it size itself to
    // its content and let whatever wraps it handle scrolling instead.
    return isLoading
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: _buildBody(),
          );
  }

  List<Widget> _buildBody() {
    final t = tournament;
    if (t == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text('No tournament set up this season.', style: TextStyle(color: Colors.white70)),
        ),
      ];
    }

    final widgets = <Widget>[];

    if (errorMessage != null) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
      ));
    }

    // No draw yet.
    if (t.currentRoundSize == null) {
      widgets.add(const Text(
        'The draw hasn\'t happened yet.',
        style: TextStyle(color: Colors.white70, fontSize: 15),
      ));
      if (isManager) {
        widgets.add(const SizedBox(height: 16));
        widgets.add(ElevatedButton(
          onPressed: isBusy ? null : drawRound,
          style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: AccaColors.primary),
          child: isBusy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Draw Tournament'),
        ));
      }
      return widgets;
    }

    // Draw/reveal controls for the current round.
    if (!_allRevealed) {
      final currentRoundMatches = _currentRoundMatches;
      final unrevealedCount = currentRoundMatches.where((m) => !m.revealed).length;
      widgets.add(Text(
        tournamentRoundLabel(t.currentRoundSize!),
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ));
      widgets.add(const SizedBox(height: 12));
      if (isManager) {
        widgets.add(Text(
          '$unrevealedCount fixture${unrevealedCount == 1 ? '' : 's'} waiting to be revealed.',
          style: const TextStyle(color: Colors.white70),
        ));
        widgets.add(const SizedBox(height: 12));
        widgets.add(Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: isRevealing ? null : revealAll,
                style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: AccaColors.primary),
                child: const Text('Reveal All at Once'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: isRevealing ? null : revealOneByOne,
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AccaColors.gold), foregroundColor: AccaColors.gold),
                child: isRevealing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Reveal One by One'),
              ),
            ),
          ],
        ));
      } else {
        widgets.add(const Text(
          'Waiting for the manager to reveal the draw...',
          style: TextStyle(color: Colors.white70),
        ));
      }
      widgets.add(const SizedBox(height: 20));
    }

    // The bracket chart — every round, side by side.
    widgets.add(const Text('Round', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)));
    widgets.add(const SizedBox(height: 10));
    widgets.add(_bracketChart(t));
    widgets.add(const SizedBox(height: 20));

    // Champion banner / draw-next-round controls.
    if (t.currentRoundSize == 2 && _allRevealed && _allSettled) {
      final finalMatch = _currentRoundMatches.first;
      final champion = finalMatch.winnerName ?? finalMatch.memberAName;
      widgets.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AccaColors.gold, borderRadius: BorderRadius.circular(10)),
        child: Text(
          '🏆 Champion: $champion',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AccaColors.primary, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ));
      widgets.add(const SizedBox(height: 20));
    } else if (_allRevealed && isManager && t.currentRoundSize != 2) {
      if (_allSettled) {
        widgets.add(ElevatedButton(
          onPressed: isBusy ? null : drawRound,
          style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: AccaColors.primary),
          child: isBusy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Draw Next Round'),
        ));
      } else {
        widgets.add(const Text(
          'Waiting for every match in this round to be settled before the next round can be drawn.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ));
      }
      widgets.add(const SizedBox(height: 20));
    }

    // Results table — every leg, across every round.
    widgets.add(const Text('Selections', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)));
    widgets.add(const SizedBox(height: 10));
    widgets.add(_resultsTable());

    return widgets;
  }

  // ============================================================
  // BRACKET CHART
  // ============================================================

  List<int> _roundSizesInOrder(Tournament t) {
    final sizes = <int>[];
    if (allMatches.any((m) => m.roundSize == 0)) sizes.add(0);
    if (t.mainBracketSize != null) {
      var size = t.mainBracketSize!;
      while (size >= 2) {
        sizes.add(size);
        size ~/= 2;
      }
    }
    return sizes;
  }

  Widget _bracketChart(Tournament t) {
    final sizes = _roundSizesInOrder(t);
    if (sizes.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final size in sizes) _roundColumn(t, size)],
      ),
    );
  }

  Widget _roundColumn(Tournament t, int roundSize) {
    final roundMatches = allMatches.where((m) => m.roundSize == roundSize).toList()
      ..sort((a, b) => a.memberAName.compareTo(b.memberAName));
    // Placeholder count for a round that hasn't been drawn yet (main
    // bracket rounds only — the qualifying tier's size can't be predicted
    // ahead of its own draw, so it only ever appears once real).
    final expectedCount = roundSize == 0 ? roundMatches.length : roundSize ~/ 2;
    final isCurrentRound = t.currentRoundSize == roundSize;

    final boxes = <Widget>[];
    if (roundMatches.isNotEmpty) {
      for (final m in roundMatches) {
        // Respect the reveal mechanic — an unrevealed current-round match
        // shows as a placeholder here too, even though the real data
        // already exists in Firestore.
        final hideForReveal = isCurrentRound && !m.revealed;
        boxes.add(hideForReveal ? _placeholderBox() : _matchBox(m));
        boxes.add(const SizedBox(height: 12));
      }
    } else {
      for (var i = 0; i < expectedCount; i++) {
        boxes.add(_placeholderBox());
        boxes.add(const SizedBox(height: 12));
      }
    }

    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tournamentRoundLabel(roundSize), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 10),
          ...boxes,
        ],
      ),
    );
  }

  Widget _matchBox(TournamentMatch m) {
    if (m.isBye) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
        child: Text('${m.memberAName} — Bye', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600)),
      );
    }
    final aStatus = m.winnerMemberId == null ? 'TBC' : (m.winnerMemberId == m.memberAId ? 'won' : 'lost');
    final bStatus = m.winnerMemberId == null ? 'TBC' : (m.winnerMemberId == m.memberBId ? 'won' : 'lost');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: m.isBigCupTie ? AccaColors.gold : Colors.black12, width: m.isBigCupTie ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _participantRow(m.memberAName, aStatus),
          const SizedBox(height: 4),
          _participantRow(m.memberBName ?? 'TBC', bStatus),
        ],
      ),
    );
  }

  Widget _placeholderBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TBC', style: TextStyle(color: Colors.white54, fontSize: 12)),
          SizedBox(height: 4),
          Text('TBC', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _participantRow(String name, String status) {
    final color = status == 'won' ? AccaColors.win : (status == 'lost' ? AccaColors.loss : Colors.black54);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(name, style: const TextStyle(color: Colors.black, fontSize: 12), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ============================================================
  // RESULTS TABLE — every leg, across the whole tournament
  // ============================================================

  String _formatDateOnly(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  void _resizeSelCol(String col, double delta) {
    setState(() => _selectionsColWidths[col] = ((_selectionsColWidths[col] ?? 90) + delta).clamp(_minColWidth, 500));
  }
  Widget _selResizeHandle(String col) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => _resizeSelCol(col, d.delta.dx),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: Container(width: 12, alignment: Alignment.center, child: Container(width: 2, color: Colors.black26)),
        ),
      );
  Widget _selHeader(String col) => Container(
        height: 36,
        width: _selectionsColWidths[col] ?? 90,
        color: AccaColors.gold,
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(col, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black), overflow: TextOverflow.ellipsis),
              ),
            ),
            _selResizeHandle(col),
          ],
        ),
      );
  Widget _selCell(String col, Widget child) => Container(
        height: 36,
        width: _selectionsColWidths[col] ?? 90,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: child,
      );
  Widget _resultsTable() {
    if (tournamentLegs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No selections submitted yet.', style: TextStyle(color: Colors.white70)),
      );
    }
    final matchesById = {for (final m in allMatches) if (m.id != null) m.id!: m};
    final rows = [...tournamentLegs]..sort((a, b) {
        final matchA = matchesById[a.tournamentMatchId];
        final matchB = matchesById[b.tournamentMatchId];
        final roundCompare = (matchB?.roundSize ?? 0).compareTo(matchA?.roundSize ?? 0);
        if (roundCompare != 0) return roundCompare;
        return a.submittedAt.compareTo(b.submittedAt);
      });
    const cols = ['Round', 'Date', 'Member', 'Leg', 'Selection', 'Odds', 'Winner'];
    const cellStyle = TextStyle(fontSize: 12, color: Colors.black);
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
              Row(children: [for (final c in cols) _selHeader(c)]),
              for (final leg in rows)
                Row(children: [
                  _selCell('Round', Text(tournamentRoundLabel(matchesById[leg.tournamentMatchId]?.roundSize ?? 0), style: cellStyle)),
                  _selCell('Date', Text(_formatDateOnly(leg.kickoff), style: cellStyle)),
                  _selCell('Member', Text(
                    leg.memberId == matchesById[leg.tournamentMatchId]?.memberAId
                        ? matchesById[leg.tournamentMatchId]?.memberAName ?? '—'
                        : matchesById[leg.tournamentMatchId]?.memberBName ?? '—',
                    style: cellStyle, overflow: TextOverflow.ellipsis,
                  )),
                  _selCell('Leg', Text(leg.isSecondaryTournamentLeg ? 'Secondary' : 'Primary', style: cellStyle)),
                  _selCell('Selection', Text(leg.selectionDescription, style: cellStyle, overflow: TextOverflow.ellipsis)),
                  _selCell('Odds', Text(decimalToFractional(leg.decimalOddsAtSelection), style: cellStyle)),
                  _selCell('Winner', Text(matchesById[leg.tournamentMatchId]?.winnerName ?? 'TBC', style: cellStyle)),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}