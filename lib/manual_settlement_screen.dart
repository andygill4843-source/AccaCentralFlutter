import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

class ManualSettlementScreen extends StatefulWidget {
  final String teamId;

  const ManualSettlementScreen({super.key, required this.teamId});

  @override
  State<ManualSettlementScreen> createState() => _ManualSettlementScreenState();
}

class _ManualSettlementScreenState extends State<ManualSettlementScreen> {
  List<AccumulatorLeg> pendingLegs = [];
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
      final allLegs = await FirestoreService.instance.fetchLegs(widget.teamId);
      final now = DateTime.now();
      final pending = allLegs
          .where((l) => l.outcome == LegOutcome.pending && l.kickoff.isBefore(now))
          .toList()
        ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
      setState(() {
        pendingLegs = pending;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> settle(AccumulatorLeg leg, LegOutcome outcome) async {
    if (leg.id == null) return;
    await FirestoreService.instance.updateLegOutcome(legId: leg.id!, outcome: outcome);
    setState(() {
      pendingLegs.removeWhere((l) => l.id == leg.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Settlement'),
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
                : pendingLegs.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Nothing waiting on manual settlement.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: pendingLegs.length,
                        itemBuilder: (context, index) {
                          final leg = pendingLegs[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(leg.fixtureDescription, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                Text(
                                  leg.selectionDescription,
                                  style: TextStyle(fontSize: 12, color: AccaColors.textSecondary),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _settleButton('Won', LegOutcome.won, AccaColors.win, leg),
                                    const SizedBox(width: 8),
                                    _settleButton('Lost', LegOutcome.lost, AccaColors.loss, leg),
                                    const SizedBox(width: 8),
                                    _settleButton('Void', LegOutcome.void_, AccaColors.textSecondary, leg),
                                  ],
                                ),
                                const Divider(height: 24),
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  Widget _settleButton(String label, LegOutcome outcome, Color color, AccumulatorLeg leg) {
    return OutlinedButton(
      onPressed: () => settle(leg, outcome),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
      ),
      child: Text(label),
    );
  }
}