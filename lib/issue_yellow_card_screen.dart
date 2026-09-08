import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

class IssueYellowCardScreen extends StatefulWidget {
  final String teamId;
  final String season;
  final List<Member> members;
  final String issuedByMemberId;
  final String issuedByName;
  const IssueYellowCardScreen({
    super.key,
    required this.teamId,
    required this.season,
    required this.members,
    required this.issuedByMemberId,
    required this.issuedByName,
  });
  @override
  State<IssueYellowCardScreen> createState() => _IssueYellowCardScreenState();
}

class _IssueYellowCardScreenState extends State<IssueYellowCardScreen> {
  String? selectedMemberId;
  final reasonController = TextEditingController();
  bool isSaving = false;
  String? errorMessage;

  Future<void> submit() async {
    if (selectedMemberId == null || reasonController.text.trim().isEmpty) {
      setState(() => errorMessage = 'Pick a member and enter a reason.');
      return;
    }
    final member = widget.members.firstWhere((m) => m.id == selectedMemberId);
    setState(() {
      isSaving = true;
      errorMessage = null;
    });
    try {
      await FirestoreService.instance.createYellowCard(YellowCard(
        teamId: widget.teamId,
        memberId: member.id!,
        memberName: member.displayName,
        reason: reasonController.text.trim(),
        season: widget.season,
        issuedByMemberId: widget.issuedByMemberId,
        issuedByName: widget.issuedByName,
        createdAt: DateTime.now(),
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        isSaving = false;
        errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Issue Yellow Card'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Member', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedMemberId,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AccaColors.gold, width: 1.5),
                ),
              ),
              dropdownColor: Colors.white,
              style: const TextStyle(color: Colors.black),
              items: [
                for (final m in widget.members)
                  if (m.id != null) DropdownMenuItem(value: m.id, child: Text(m.displayName)),
              ],
              onChanged: (v) => setState(() => selectedMemberId = v),
            ),
            const SizedBox(height: 16),
            const Text('Reason', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 3,
              style: const TextStyle(color: Colors.black),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                hintText: 'What happened?',
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AccaColors.gold, width: 1.5),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Two yellow cards in a season automatically trigger a fine — the fined member can still dispute the fine itself, but not the yellow card.',
                style: TextStyle(fontSize: 12, color: AccaColors.textSecondary),
              ),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isSaving ? null : submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AccaColors.gold,
                foregroundColor: AccaColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Issue yellow card'),
            ),
          ],
        ),
      ),
    );
  }
}