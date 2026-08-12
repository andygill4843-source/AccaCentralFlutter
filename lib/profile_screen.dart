import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors
import 'manage_team_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;

  const ProfileScreen({super.key, required this.appState, required this.teamId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Team? team;
  Member? member;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    final fetchedTeam = await FirestoreService.instance.fetchTeam(widget.teamId);
    final fetchedMember = await FirestoreService.instance.fetchMember(teamId: widget.teamId, userId: userId);
    setState(() {
      team = fetchedTeam;
      member = fetchedMember;
      isLoading = false;
    });
  }

  Future<void> shareInviteCode() async {
    if (team == null) return;
    final text = 'Join my team "${team!.name}" on Acca Central — use invite code: ${team!.inviteCode}';
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/?text=$encoded');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open WhatsApp — is it installed?")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.appState.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Display name', user?.displayName ?? '—'),
                  _row('Username', user?.username ?? '—'),
                  _row('Email', user?.email ?? '—'),
                  const Divider(height: 32),
                  _row('Team', team?.name ?? '—'),
                  _row(
                    'Role',
                    member?.role == MemberRole.manager ? 'Manager' : 'Squad member',
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: shareInviteCode,
                    icon: const Icon(Icons.share),
                    label: const Text('Share team invite code'),
                  ),
                  const SizedBox(height: 12),
                  if (member?.role == MemberRole.manager) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ManageTeamScreen(teamId: widget.teamId)),
                        );
                      },
                      icon: const Icon(Icons.groups),
                      label: const Text('Manage team'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: () async {
                      await widget.appState.logOut();
                      if (mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}