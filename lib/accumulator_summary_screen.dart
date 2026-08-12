import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'package:flutter/services.dart';

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
  Map<String, String> memberNames = {}; // memberId -> displayName
  bool isRejecting = false;

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
      final members = await FirestoreService.instance.fetchMembers(widget.gameWeek.teamId);
      setState(() {
        legs = allLegs.where((l) => l.gameWeekId == widget.gameWeek.id).toList();
        memberNames = {for (final m in members) if (m.id != null) m.id!: m.displayName};
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> rejectLeg(AccumulatorLeg leg) async {
    if (leg.id == null) return;
    setState(() => isRejecting = true);
    try {
      await FirestoreService.instance.deleteLeg(leg.id!);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't reject leg: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => isRejecting = false);
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

      if (mounted) {
        await offerTransfer(option);
      }
    } catch (e) {
      setState(() => isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error locking gameweek: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> offerTransfer(_BookmakerOption option) async {
    final links = option.legLinks.where((pair) => pair.$2 != null).toList();

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Go to ${option.bookmaker}?'),
        content: Text(
          links.isEmpty
              ? "No direct betslip links are available for ${option.bookmaker} on these legs. "
                  "You can still copy or share the leg list below to place the bets manually."
              : 'Would you like to be transferred to the ${option.bookmaker} website? '
                  "All ${links.length} leg${links.length == 1 ? '' : 's'} of the accumulator will open there — "
                  'please double-check the betslip is complete before staking anything, '
                  "as this depends on ${option.bookmaker}'s own website behaviour.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(context, 'whatsapp'), child: const Text('Share on WhatsApp')),
          TextButton(onPressed: () => Navigator.pop(context, 'copy'), child: const Text('Copy leg list')),
          if (links.isNotEmpty)
            TextButton(onPressed: () => Navigator.pop(context, 'transfer'), child: const Text('Transfer me')),
        ],
      ),
    );

    switch (action) {
      case 'transfer':
        for (final pair in links) {
          final url = Uri.parse(pair.$2!);
          await launchUrl(url, mode: LaunchMode.externalApplication);
          // Small pause between opens so the bookmaker's site has a moment
          // to register each selection before the next one loads, on
          // bookmakers where that matters.
          await Future.delayed(const Duration(milliseconds: 800));
        }
        break;
      case 'copy':
        await copyLegList(option);
        break;
      case 'whatsapp':
        await shareViaWhatsApp(option);
        break;
      default:
        break;
    }
  }

  String buildLegListText(_BookmakerOption option) {
    final buffer = StringBuffer();
    buffer.writeln('Acca Central — Gameweek ${widget.gameWeek.weekNumber}');
    buffer.writeln('Bookmaker: ${option.bookmaker}');
    buffer.writeln('Combined odds: ${option.combinedOdds.toStringAsFixed(2)}');
    buffer.writeln();
    for (final leg in legs) {
      final name = memberNames[leg.memberId] ?? 'Unknown';
      buffer.writeln('$name: ${leg.selectionDescription}');
      final price = (leg.bookmakerPrices ?? {})[option.bookmaker];
      if (price != null) {
        buffer.writeln('  ${price.toStringAsFixed(2)} @ ${option.bookmaker}');
      }
    }
    return buffer.toString();
  }

  Future<void> copyLegList(_BookmakerOption option) async {
    await Clipboard.setData(ClipboardData(text: buildLegListText(option)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leg list copied to clipboard.')),
      );
    }
  }

  Future<void> shareViaWhatsApp(_BookmakerOption option) async {
    final text = buildLegListText(option);
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/?text=$encoded');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open WhatsApp — is it installed?")),
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
                        if (!isLocked) ...[
                          const Text('Leg review', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 8),
                          for (final leg in legs) _legReviewCard(leg),
                          const SizedBox(height: 20),
                        ],
                        if (selectedBookmaker != null) ...[
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

  Widget _legReviewCard(AccumulatorLeg leg) {
    final name = leg.id != null ? (memberNames[leg.memberId] ?? 'Unknown') : 'Unknown';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(fontSize: 12, color: AccaColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(leg.fixtureDescription, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(leg.selectionDescription, style: const TextStyle(fontSize: 13)),
                  Text(
                    '${leg.decimalOddsAtSelection.toStringAsFixed(2)} — ${leg.bookmaker}',
                    style: TextStyle(fontSize: 12, color: AccaColors.textSecondary),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: isRejecting ? null : () => rejectLeg(leg),
              style: OutlinedButton.styleFrom(foregroundColor: AccaColors.loss, side: BorderSide(color: AccaColors.loss)),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
  }

}