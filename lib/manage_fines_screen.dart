import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors, accaFieldDecoration, accaFieldTextStyle

class ManageFinesScreen extends StatefulWidget {
  final String teamId;

  const ManageFinesScreen({super.key, required this.teamId});

  @override
  State<ManageFinesScreen> createState() => _ManageFinesScreenState();
}

class _ManageFinesScreenState extends State<ManageFinesScreen> {
  List<Member> members = [];
  List<Fine> fines = [];
  Member? selectedMember;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    final loadedMembers = await FirestoreService.instance.fetchMembers(widget.teamId);
    final loadedFines = await FirestoreService.instance.fetchFines(widget.teamId);
    setState(() {
      members = loadedMembers;
      fines = loadedFines;
      isLoading = false;
    });
  }

  List<Fine> get activeFinesForSelected {
    if (selectedMember?.id == null) return [];
    return fines.where((f) => f.memberId == selectedMember!.id && f.countsTowardTally).toList();
  }

  Future<void> markPaid(Fine fine) async {
    if (fine.id == null) return;
    try {
      await FirestoreService.instance.markFinePaid(fine.id!);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Fines Paid'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<Member>(
                    initialValue: selectedMember,
                    decoration: accaFieldDecoration('Member'),
                    dropdownColor: Colors.white,
                    style: accaFieldTextStyle,
                    items: members
                        .where((m) => m.id != null)
                        .map((m) => DropdownMenuItem(value: m, child: Text(m.displayName, style: const TextStyle(color: Colors.black))))
                        .toList(),
                    onChanged: (value) => setState(() => selectedMember = value),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: selectedMember == null
                        ? const Center(child: Text('Select a member to see their active fines.', style: TextStyle(color: Colors.white70)))
                        : activeFinesForSelected.isEmpty
                            ? const Center(child: Text('No active fines for this member.', style: TextStyle(color: Colors.white70)))
                            : ListView(
                                children: [
                                  for (final fine in activeFinesForSelected)
                                    Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(fine.fineType.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                                  Text(fine.reason, style: const TextStyle(fontSize: 13)),
                                                  if (fine.status == FineStatus.upheld)
                                                    Text('Upheld after dispute', style: TextStyle(fontSize: 11, color: AccaColors.textSecondary)),
                                                ],
                                              ),
                                            ),
                                            OutlinedButton(
                                              onPressed: () => markPaid(fine),
                                              child: const Text('Mark paid'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                  ),
                ],
              ),
            ),
    );
  }
}