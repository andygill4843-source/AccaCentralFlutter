import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors, accaFieldDecoration, accaFieldTextStyle

class PlaceFineScreen extends StatefulWidget {
  final String teamId;
  final List<Member> members;
  final String createdByMemberId;
  final String createdByName;

  const PlaceFineScreen({
    super.key,
    required this.teamId,
    required this.members,
    required this.createdByMemberId,
    required this.createdByName,
  });

  @override
  State<PlaceFineScreen> createState() => _PlaceFineScreenState();
}

class _PlaceFineScreenState extends State<PlaceFineScreen> {
  Member? selectedMember;
  FineType selectedType = FineType.lateSelection;
  final reasonController = TextEditingController();
  bool isSubmitting = false;
  String? errorMessage;

  Future<void> submit() async {
    if (selectedMember == null || selectedMember!.id == null || reasonController.text.trim().isEmpty) {
      setState(() => errorMessage = 'Select a member and enter a reason.');
      return;
    }
    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });

    final fine = Fine(
      id: null,
      teamId: widget.teamId,
      memberId: selectedMember!.id!,
      memberName: selectedMember!.displayName,
      fineType: selectedType,
      reason: reasonController.text.trim(),
      status: FineStatus.pending,
      createdByMemberId: widget.createdByMemberId,
      createdByName: widget.createdByName,
      createdAt: DateTime.now(),
    );

    try {
      await FirestoreService.instance.createFine(fine);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        isSubmitting = false;
        errorMessage = e.toString();
      });
    }
  }

  Widget _labeledField(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Place a fine'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _labeledField(
              'Member',
              DropdownButtonFormField<Member>(
                initialValue: selectedMember,
                decoration: accaFieldDecoration(''),
                dropdownColor: Colors.white,
                style: accaFieldTextStyle,
                items: widget.members
                    .where((m) => m.id != null)
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.displayName, style: const TextStyle(color: Colors.black))))
                    .toList(),
                onChanged: (value) => setState(() => selectedMember = value),
              ),
            ),
            const SizedBox(height: 16),
            _labeledField(
              'Fine type',
              DropdownButtonFormField<FineType>(
                initialValue: selectedType,
                decoration: accaFieldDecoration(''),
                dropdownColor: Colors.white,
                style: accaFieldTextStyle,
                items: FineType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, style: const TextStyle(color: Colors.black))))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedType = value);
                },
              ),
            ),
            const SizedBox(height: 16),
            _labeledField(
              'Reason',
              TextField(
                controller: reasonController,
                maxLines: 3,
                style: accaFieldTextStyle,
                decoration: accaFieldDecoration(''),
              ),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isSubmitting ? null : submit,
              style: ElevatedButton.styleFrom(backgroundColor: AccaColors.gold, foregroundColor: Colors.black),
              child: isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send fine', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}