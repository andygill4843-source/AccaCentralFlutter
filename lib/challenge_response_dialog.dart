import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'odds_format.dart';

/// Shown as a popup whenever a member opens the app with an unanswered
/// challenge against one of their legs. Declining still uses up the
/// challenger's attempt for the gameweek — it isn't a free pass for them
/// to try someone else instead.
class ChallengeResponseDialog extends StatefulWidget {
  final Challenge challenge;
  const ChallengeResponseDialog({super.key, required this.challenge});

  @override
  State<ChallengeResponseDialog> createState() => _ChallengeResponseDialogState();
}

class _ChallengeResponseDialogState extends State<ChallengeResponseDialog> {
  bool isSubmitting = false;
  String? errorMessage;

  Future<void> respond(bool accept) async {
    if (widget.challenge.id == null) return;
    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });
    try {
      await FirestoreService.instance.respondToChallenge(
        challengeId: widget.challenge.id!,
        accept: accept,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        isSubmitting = false;
        errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.challenge;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        '${challenge.challengerName} has challenged you 😱',
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Are you brave enough to accept?',
            style: TextStyle(color: Colors.black87, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AccaColors.background.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AccaColors.gold.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${challenge.challengerName}\'s pick',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                if (challenge.challengerLegDescription != null) ...[
                  Text(
                    challenge.challengerLegDescription!,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
                  ),
                  if (challenge.challengerLegOdds != null)
                    Text(
                      decimalToFractional(challenge.challengerLegOdds!),
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                ] else
                  const Text(
                    'They haven\'t picked their own leg yet.',
                    style: TextStyle(fontSize: 13, color: Colors.black54, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your pick: "${challenge.challengedLegDescription}"',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: isSubmitting ? null : () => respond(false),
          style: TextButton.styleFrom(foregroundColor: AccaColors.loss),
          child: const Text('Reject'),
        ),
        ElevatedButton(
          onPressed: isSubmitting ? null : () => respond(true),
          style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: Colors.black),
          child: isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}