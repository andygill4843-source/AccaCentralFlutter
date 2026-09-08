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

  Future<void> remove(Member member) async {
    if (member.id == null) return;

    // Guard: can't remove the last manager.
    final managers = members.where((m) => m.role == MemberRole.manager).toList();
    if (member.role == MemberRole.manager && managers.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Can't remove the only manager — promote someone else first.")),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member'),
        content: Text(
          "Remove ${member.displayName} from the team? Their historical selections and stats will remain, but they will lose access.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AccaColors.loss),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await FirestoreService.instance.removeMember(
        teamId: widget.teamId,
        memberId: member.id!,
        userId: member.userId,
      );
      load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't remove member: $e")),
        );
      }
    }
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
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final isManager = member.role == MemberRole.manager;
                    return ListTile(
                      title: Text(member.displayName),
                      subtitle: Text(isManager ? 'Manager' : 'Squad member'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isManager)
                            const Icon(Icons.shield, color: AccaColors.gold)
                          else
                            OutlinedButton(
                              onPressed: () => promote(member),
                              child: const Text('Make manager'),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.person_remove_outlined),
                            color: AccaColors.loss,
                            tooltip: 'Remove from team',
                            onPressed: () => remove(member),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}