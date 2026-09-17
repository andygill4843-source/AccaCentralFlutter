import 'package:flutter/material.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

/// Wraps the result of TournamentLinkPickerScreen so a plain `null` from
/// Navigator.pop (the system back button) can be distinguished from the
/// manager explicitly choosing "No" — both would otherwise collapse to
/// the same value.
class TournamentLinkChoice {
  final Tournament? tournament; // null = explicitly chose "No"
  const TournamentLinkChoice(this.tournament);
}

class TournamentLinkPickerScreen extends StatelessWidget {
  final List<Tournament> options;
  final Tournament? current;
  const TournamentLinkPickerScreen({super.key, required this.options, required this.current});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Part of a tournament round?'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: RadioGroup<String?>(
        groupValue: current?.id,
        onChanged: (selectedId) {
          if (selectedId == null) {
            Navigator.of(context).pop(const TournamentLinkChoice(null));
            return;
          }
          final match = options.where((t) => t.id == selectedId).firstOrNull;
          Navigator.of(context).pop(TournamentLinkChoice(match));
        },
        child: ListView(
          children: [
            const RadioListTile<String?>(
              value: null,
              title: Text('No', style: TextStyle(color: Colors.white)),
              activeColor: AccaColors.gold,
            ),
            for (final t in options)
              RadioListTile<String?>(
                value: t.id,
                title: Text(
                  '${t.name} (${tournamentRoundLabel(t.currentRoundSize!)})',
                  style: const TextStyle(color: Colors.white),
                ),
                activeColor: AccaColors.gold,
              ),
          ],
        ),
      ),
    );
  }
}