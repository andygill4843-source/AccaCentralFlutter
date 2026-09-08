import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'odds_format.dart';
import 'submit_leg_screen.dart';

class TournamentLegSelectionScreen extends StatefulWidget {
  final String teamId;
  final String memberId;
  final String gameWeekId;
  final String tournamentMatchId;
  final DateTime windowStart;
  final DateTime windowEnd;
  const TournamentLegSelectionScreen({
    super.key,
    required this.teamId,
    required this.memberId,
    required this.gameWeekId,
    required this.tournamentMatchId,
    required this.windowStart,
    required this.windowEnd,
  });
  @override
  State<TournamentLegSelectionScreen> createState() => _TournamentLegSelectionScreenState();
}

class _TournamentLegSelectionScreenState extends State<TournamentLegSelectionScreen> {
  AccumulatorLeg? primaryLeg;
  AccumulatorLeg? secondaryLeg;
  bool isLoading = true;
  bool isBusy = false;
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
      final legs = await FirestoreService.instance.fetchMemberLegsForGameWeek(
        teamId: widget.teamId,
        memberId: widget.memberId,
        gameWeekId: widget.gameWeekId,
      );
      AccumulatorLeg? primary;
      AccumulatorLeg? secondary;
      for (final leg in legs) {
        if (leg.tournamentMatchId != widget.tournamentMatchId) continue;
        if (leg.isSecondaryTournamentLeg) {
          secondary = leg;
        } else {
          primary = leg;
        }
      }
      if (!mounted) return;
      setState(() {
        primaryLeg = primary;
        secondaryLeg = secondary;
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

  Future<void> changeLeg({required bool isSecondary}) async {
    final existing = isSecondary ? secondaryLeg : primaryLeg;
    if (existing?.id != null) {
      try {
        await FirestoreService.instance.deleteLeg(existing!.id!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Couldn't remove the existing pick: $e")),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubmitLegScreen(
          gameWeekId: widget.gameWeekId,
          memberId: widget.memberId,
          teamId: widget.teamId,
          windowStart: widget.windowStart,
          windowEnd: widget.windowEnd,
          tournamentMatchId: widget.tournamentMatchId,
          isSecondaryTournamentLeg: isSecondary,
        ),
      ),
    );
    load();
  }

  Future<void> swap() async {
    if (primaryLeg?.id == null || secondaryLeg?.id == null) return;
    setState(() => isBusy = true);
    try {
      await FirestoreService.instance.swapPrimaryAndSecondaryLegs(
        primaryLegId: primaryLeg!.id!,
        secondaryLegId: secondaryLeg!.id!,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't swap: $e")));
      }
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournament Picks'),
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
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _legCard(
                        title: 'Primary Leg',
                        subtitle: 'Counts toward the main league table',
                        leg: primaryLeg,
                        onChange: () => changeLeg(isSecondary: false),
                      ),
                      const SizedBox(height: 16),
                      _legCard(
                        title: 'Secondary Leg',
                        subtitle: 'Tournament only',
                        leg: secondaryLeg,
                        onChange: () => changeLeg(isSecondary: true),
                      ),
                      if (primaryLeg != null && secondaryLeg != null) ...[
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: isBusy ? null : swap,
                          icon: const Icon(Icons.swap_horiz, color: AccaColors.gold),
                          label: const Text(
                            'Switch Primary and Secondary',
                            style: TextStyle(color: AccaColors.gold),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AccaColors.gold),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _legCard({
    required String title,
    required String subtitle,
    required AccumulatorLeg? leg,
    required VoidCallback onChange,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccaColors.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: onChange,
                child: Text(leg == null ? 'Pick' : 'Change', style: const TextStyle(color: AccaColors.primary)),
              ),
            ],
          ),
          Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 8),
          if (leg == null)
            const Text('Not yet picked.', style: TextStyle(color: Colors.black54))
          else ...[
            Text(leg.fixtureDescription, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(leg.selectionDescription, style: const TextStyle(color: Colors.black87, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Odds: ${decimalToFractional(leg.decimalOddsAtSelection)}', style: const TextStyle(color: Colors.black87, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}