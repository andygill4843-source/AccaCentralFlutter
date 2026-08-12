import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

class _BookmakerOption {
  final String bookmaker;
  final double combinedOdds;
  final List<(AccumulatorLeg leg, String? link)> legLinks;

  _BookmakerOption({required this.bookmaker, required this.combinedOdds, required this.legLinks});
}

class AccumulatorSummaryScreen extends StatefulWidget {
  final GameWeek gameWeek;

  const AccumulatorSummaryScreen({super.key, required this.gameWeek});

  @override
  State<AccumulatorSummaryScreen> createState() => _AccumulatorSummaryScreenState();
}

class _AccumulatorSummaryScreenState extends State<AccumulatorSummaryScreen> {
  List<AccumulatorLeg> legs = [];
  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;
  String? selectedBookmaker;
  double? combinedOdds;

  @override
  void initState() {
    super.initState();
    selectedBookmaker = widget.gameWeek.selectedBookmaker;
    combinedOdds = widget.gameWeek.combinedOdds;
    isLocked = widget.gameWeek.isLocked;
    load();
  }

  Future<void> load() async {
    if (widget.gameWeek.id == null) return;
    try {
      final allLegs = await FirestoreService.instance.fetchLegs(widget.gameWeek.teamId);
      setState(() {
        legs = allLegs.where((l) => l.gameWeekId == widget.gameWeek.id).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  /// Only a bookmaker present on EVERY leg qualifies — you can't place one
  /// accumulator bet with a bookmaker missing a price on any leg of it.
  List<_BookmakerOption> get bookmakerOptions {
    if (legs.isEmpty) return [];

    final bookmakerSets = legs.map((l) => (l.bookmakerPrices ?? {}).keys.toSet()).toList();
    var common = bookmakerSets.first;
    for (final s in bookmakerSets.skip(1)) {
      common = common.intersection(s);
    }

    final options = common.map((bookmaker) {
      final combined = legs.fold<double>(1.0, (product, leg) => product * ((leg.bookmakerPrices ?? {})[bookmaker] ?? 1.0));
      final links = legs.map((l) => (l, (l.bookmakerLinks ?? {})[bookmaker])).toList();
      return _BookmakerOption(bookmaker: bookmaker, combinedOdds: combined, legLinks: links);
    }).toList();

    options.sort((a, b) => b.combinedOdds.compareTo(a.combinedOdds));
    return options;
  }

  bool isLocked = false;

  Future<void> select(_BookmakerOption option) async {
    if (widget.gameWeek.id == null) return;
    setState(() => isSaving = true);
    try {
      await FirestoreService.instance.setGameWeekBookmaker(
        gameWeekId: widget.gameWeek.id!,
        bookmaker: option.bookmaker,
        combinedOdds: option.combinedOdds,
        legs: legs,
      );
      setState(() {
        selectedBookmaker = option.bookmaker;
        combinedOdds = option.combinedOdds;
        isLocked = true;
        isSaving = false;
      });
    } catch (e) {
      setState(() => isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error locking gameweek: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Best Odds'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : legs.isEmpty
                  ? const Center(child: Text('No legs submitted yet.'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (isLocked) ...[
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.lock, size: 16, color: Colors.grey),
                                SizedBox(width: 6),
                                Text('Gameweek locked — selections are closed', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                        if (selectedBookmaker != null) ...[
                          Card(
                            color: AccaColors.gold.withOpacity(0.15),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Selected bookmaker', style: TextStyle(fontSize: 12)),
                                  Text(selectedBookmaker!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  if (combinedOdds != null)
                                    Text('Combined odds: ${combinedOdds!.toStringAsFixed(2)}'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const Text('Compare bookmakers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        if (bookmakerOptions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No single bookmaker covers every leg of this accumulator — legs may need placing across multiple bookmakers.',
                              style: TextStyle(fontSize: 13),
                            ),
                          )
                        else
                          for (final option in bookmakerOptions) _bookmakerCard(option),
                      ],
                    ),
    );
  }

  Widget _bookmakerCard(_BookmakerOption option) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.bookmaker, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('Combined odds: ${option.combinedOdds.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: isSaving || isLocked ? null : () => select(option),
                  child: Text(selectedBookmaker == option.bookmaker ? 'Selected' : (isLocked ? 'Locked' : 'Select')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final pair in option.legLinks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: pair.$2 != null
                    ? InkWell(
                        onTap: () => launchUrl(Uri.parse(pair.$2!)),
                        child: Text(
                          '${pair.$1.fixtureDescription}: open bet →',
                          style: TextStyle(fontSize: 11, color: AccaColors.gold),
                        ),
                      )
                    : Text(
                        '${pair.$1.fixtureDescription}: no direct link',
                        style: TextStyle(fontSize: 11, color: AccaColors.textSecondary),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}