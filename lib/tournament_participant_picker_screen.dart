import 'package:flutter/material.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

/// Lets the manager pick exactly [requiredCount] members to take part in
/// a tournament bracket smaller than the full team — used when the
/// manual selection method is chosen at tournament creation. Returns the
/// selected member IDs via Navigator.pop, or null if the manager backs out.
class TournamentParticipantPickerScreen extends StatefulWidget {
  final List<Member> members;
  final int requiredCount;
  const TournamentParticipantPickerScreen({
    super.key,
    required this.members,
    required this.requiredCount,
  });

  @override
  State<TournamentParticipantPickerScreen> createState() => _TournamentParticipantPickerScreenState();
}

class _TournamentParticipantPickerScreenState extends State<TournamentParticipantPickerScreen> {
  final Set<String> selected = {};

  void _toggle(String memberId) {
    setState(() {
      if (selected.contains(memberId)) {
        selected.remove(memberId);
      } else if (selected.length < widget.requiredCount) {
        selected.add(memberId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = selected.length == widget.requiredCount;
    return Scaffold(
      appBar: AppBar(
        title: Text('Select ${widget.requiredCount} participants'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${selected.length} / ${widget.requiredCount} selected',
              style: TextStyle(
                color: canConfirm ? AccaColors.gold : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final member in widget.members)
                  if (member.id != null)
                    CheckboxListTile(
                      value: selected.contains(member.id),
                      onChanged: (isChecked) {
                        // Prevents ticking past the required count —
                        // still allows immediately unticking one already
                        // selected, even once the limit is reached.
                        if (isChecked == true && selected.length >= widget.requiredCount && !selected.contains(member.id)) {
                          return;
                        }
                        _toggle(member.id!);
                      },
                      title: Text(member.displayName, style: const TextStyle(color: Colors.white)),
                      activeColor: AccaColors.gold,
                      checkColor: AccaColors.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canConfirm ? () => Navigator.of(context).pop(selected.toList()) : null,
                style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: AccaColors.primary),
                child: const Text('Confirm selection', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}