import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

class ManageTeamScreen extends StatefulWidget {
  final String teamId;

  const ManageTeamScreen({super.key, required this.teamId});

  @override
  State<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends State<ManageTeamScreen> {
  List<Member> members = [];
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
      final list = await FirestoreService.instance.fetchMembers(widget.teamId);
      list.sort((a, b) => a.displayName.compareTo(b.displayName));
      setState(() {
        members = list;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> promote(Member member) async {
    if (member.id == null) return;
    await FirestoreService.instance.setMemberRole(memberDocId: member.id!, role: MemberRole.manager);
    load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Team'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red)))
              : ListView.separated(
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final isManager = member.role == MemberRole.manager;
                    return ListTile(
                      title: Text(member.displayName),
                      subtitle: Text(isManager ? 'Manager' : 'Squad member'),
                      trailing: isManager
                          ? const Icon(Icons.shield, color: AccaColors.gold)
                          : OutlinedButton(
                              onPressed: () => promote(member),
                              child: const Text('Make manager'),
                            ),
                    );
                  },
                ),
    );
  }
}