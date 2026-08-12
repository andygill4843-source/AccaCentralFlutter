import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'submit_leg_screen.dart';
import 'main.dart'; // for AccaColors

class CurrentLegScreen extends StatefulWidget {
  final AccumulatorLeg leg;
  final String gameWeekId;
  final String memberId;
  final String teamId;
  final DateTime windowStart;
  final DateTime windowEnd;

  const CurrentLegScreen({
    super.key,
    required this.leg,
    required this.gameWeekId,
    required this.memberId,
    required this.teamId,
    required this.windowStart,
    required this.windowEnd,
  });

  @override
  State<CurrentLegScreen> createState() => _CurrentLegScreenState();
}

class _CurrentLegScreenState extends State<CurrentLegScreen> {
  bool isRevising = false;

  String? errorMessage;

  Future<void> reviseSelection() async {
    setState(() {
      isRevising = true;
      errorMessage = null;
    });

    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SubmitLegScreen(
          gameWeekId: widget.gameWeekId,
          memberId: widget.memberId,
          teamId: widget.teamId,
          windowStart: widget.windowStart,
          windowEnd: widget.windowEnd,
        ),
      ),
    );

    if (submitted == true) {
      try {
        if (widget.leg.id != null) {
          await FirestoreService.instance.deleteLeg(widget.leg.id!);
        }

        // Fetch the newly submitted leg and land on ITS view, instead of
        // popping all the way back to the League table.
        final newLeg = await FirestoreService.instance.fetchMemberLegForGameWeek(
          teamId: widget.teamId,
          memberId: widget.memberId,
          gameWeekId: widget.gameWeekId,
        );

        if (mounted && newLeg != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => CurrentLegScreen(
                leg: newLeg,
                gameWeekId: widget.gameWeekId,
                memberId: widget.memberId,
                teamId: widget.teamId,
                windowStart: widget.windowStart,
                windowEnd: widget.windowEnd,
              ),
            ),
          );
        } else if (mounted) {
          // Fallback — couldn't find the new leg for some reason, at least
          // don't leave the user on stale data.
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            isRevising = false;
            errorMessage = "Couldn't remove your old pick: ${e.toString()}";
          });
        }
      }
      return;
    }

    if (mounted) setState(() => isRevising = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Leg'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        const Text('Locked in', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(widget.leg.fixtureDescription, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(widget.leg.selectionDescription, style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.leg.decimalOddsAtSelection.toStringAsFixed(2)} — ${widget.leg.bookmaker}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (errorMessage != null) ...[
              Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            OutlinedButton(
              onPressed: isRevising ? null : reviseSelection,
              child: isRevising
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Revise selection'),
            ),
          ],
        ),
      ),
    );
  }
}