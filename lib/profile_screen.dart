import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'manage_team_screen.dart';
import 'team_setup_screen.dart';
import 'main.dart'; // for AccaColors
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  final AppState appState;
  final String teamId;

  const ProfileScreen({super.key, required this.appState, required this.teamId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Team> myTeams = [];
  Member? member;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    final teamIds = widget.appState.currentUser?.teamIds ?? [];
    final teams = await FirestoreService.instance.fetchTeams(teamIds);
    final userId = widget.appState.currentUser?.id;
    Member? loadedMember;
    if (userId != null && widget.appState.activeTeamId != null) {
      loadedMember = await FirestoreService.instance.fetchMember(
        teamId: widget.appState.activeTeamId!,
        userId: userId,
      );
    }
    if (mounted) {
      setState(() {
        myTeams = teams;
        member = loadedMember;
        isLoading = false;
      });
    }
  }

  Future<void> onTeamChanged(String? teamId) async {
    if (teamId == null) return;
    widget.appState.switchActiveTeam(teamId);
    await load();
  }

  Future<void> createNewTeam() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TeamSetupScreen(appState: widget.appState, onTeamReady: () {})),
    );
    // TeamSetupScreen's submit() already updates currentUser.teamIds via
    // didJoinOrCreateTeam — just switch to whichever team is newest and reload.
    final teamIds = widget.appState.currentUser?.teamIds ?? [];
    if (teamIds.isNotEmpty) {
      widget.appState.switchActiveTeam(teamIds.last);
    }
    load();
  }

  

  @override
  Widget build(BuildContext context) {
    final user = widget.appState.currentUser;
    final activeTeamId = widget.appState.activeTeamId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Display name', user?.displayName ?? '—'),
                  _row('Username', user?.username ?? '—'),
                  _row('Email', user?.email ?? '—'),
                  const Divider(height: 32),

                  Text('Team', style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
                  const SizedBox(height: 4),
                  if (myTeams.isEmpty)
                    const Text('No teams yet.')
                  else
                    DropdownButtonFormField<String>(
                      value: activeTeamId,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      items: myTeams
                          .where((t) => t.id != null)
                          .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                          .toList(),
                      onChanged: onTeamChanged,
                    ),
                  const SizedBox(height: 8),
                  _row('Role', member?.role == MemberRole.manager ? 'Manager' : 'Squad member'),

                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: createNewTeam,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Create/Join New Team'),
                  ),


                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: myTeams.isEmpty
                        ? null
                        : () async {
                            final team = myTeams.firstWhere(
                              (t) => t.id == activeTeamId,
                              orElse: () => myTeams.first,
                            );
                            final text = 'Join my team "${team.name}" on Acca Central — use invite code: ${team.inviteCode}';
                            final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (_) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Couldn't open WhatsApp — is it installed?")),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.share),
                    label: const Text('Share team invite code'),
                  ),
                  const SizedBox(height: 12),
                  if (member?.role == MemberRole.manager) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        if (activeTeamId == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ManageTeamScreen(teamId: activeTeamId)),
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