import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

class PlaceChallengeScreen extends StatefulWidget {
  final String teamId;
  final String season;
  final GameWeek gameWeek;
  final AccumulatorLeg challengedLeg;
  final String challengedMemberName;
  final Member challenger;
  final AccumulatorLeg? challengerLeg;
  final int challengesRemaining;

  const PlaceChallengeScreen({
    super.key,
    required this.teamId,
    required this.season,
    required this.gameWeek,
    required this.challengedLeg,
    required this.challengedMemberName,
    required this.challenger,
    required this.challengerLeg,
    required this.challengesRemaining,
  });

  @override
  State<PlaceChallengeScreen> createState() => _PlaceChallengeScreenState();
}

class _PlaceChallengeScreenState extends State<PlaceChallengeScreen> {
  bool isSubmitting = false;
  String? errorMessage;

  Future<void> submit() async {
    if (widget.challengesRemaining <= 0) {
      setState(() => errorMessage = 'You have no challenges remaining this season.');
      return;
    }
    if (DateTime.now().isAfter(widget.challengedLeg.kickoff)) {
      setState(() => errorMessage = 'Too late — this leg has already kicked off.');
      return;
    }
    if (widget.challenger.id == widget.challengedLeg.memberId) {
      setState(() => errorMessage = "You can't challenge your own leg.");
      return;
    }

    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });

    final challenge = Challenge(
      id: null,
      teamId: widget.teamId,
      season: widget.season,
      gameWeekId: widget.gameWeek.id ?? '',
      challengerMemberId: widget.challenger.id!,
      challengerName: widget.challenger.displayName,
      challengedMemberId: widget.challengedLeg.memberId,
      challengedName: widget.challengedMemberName,
      challengedLegId: widget.challengedLeg.id!,
      challengedLegDescription: widget.challengedLeg.selectionDescription,
      challengedLegOdds: widget.challengedLeg.decimalOddsAtSelection,
      challengerLegId: widget.challengerLeg?.id,
      challengerLegDescription: widget.challengerLeg?.selectionDescription,
      challengerLegOdds: widget.challengerLeg?.decimalOddsAtSelection,
      status: ChallengeStatus.active,
      createdAt: DateTime.now(),
    );

    try {
      await FirestoreService.instance.createChallenge(challenge);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        isSubmitting = false;
        errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Place a Challenge'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Challenge ${widget.challengedMemberName}\'s pick:\n"${widget.challengedLeg.selectionDescription}"',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 16),
            const Text(
              'If this leg loses, you get its hypothetical win value added to your score. If it wins, they get your own leg\'s hypothetical win value instead — win or lose your own bet.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text('Challenges remaining: ${widget.challengesRemaining}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isSubmitting ? null : submit,
              style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: Colors.black),
              child: isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirm Challenge', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}