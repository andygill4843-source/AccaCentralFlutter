import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'manage_team_screen.dart';
import 'team_setup_screen.dart';
import 'main.dart'; // for AccaColors
import 'package:url_launcher/url_launcher.dart';
import 'season_summary_screen.dart';
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
  List<SeasonSummary> seasonSummaries = [];
  bool isLoading = true;
  String? errorMessage;
  bool isSavingDisplayName = false;
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
    // Load season summaries for this team if we have a member.
    if (loadedMember?.id != null && widget.appState.activeTeamId != null) {
      final summaries = await FirestoreService.instance.fetchSeasonSummariesForMember(
        teamId: widget.appState.activeTeamId!,
        memberId: loadedMember!.id!,
      );
      if (mounted) setState(() => seasonSummaries = summaries);
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

  /// Display name is per-team (Member.displayName), not account-wide —
  /// this only updates how the current member appears on the active team.
  /// Other teams the user belongs to are unaffected, and historical
  /// records (fines, reactions, past challenges, etc.) that snapshot a
  /// name at the time keep their original text — only future references
  /// (which look up the live member list) show the new name.
  Future<void> editDisplayName() async {
    if (member?.id == null) return;
    final controller = TextEditingController(text: member!.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update display name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This changes how you appear on this team only.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Display name'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.pop(dialogContext, trimmed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName == member!.displayName || !mounted) return;
    setState(() => isSavingDisplayName = true);
    try {
      await FirestoreService.instance.updateMemberDisplayName(
        memberDocId: member!.id!,
        newDisplayName: newName,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't update display name: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => isSavingDisplayName = false);
    }
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _row('Display name', member?.displayName ?? user?.displayName ?? '—'),
                      ),
                      if (member?.id != null)
                        isSavingDisplayName
                            ? const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'Edit display name',
                                onPressed: editDisplayName,
                              ),
                    ],
                  ),
                  _row('Username', user?.username ?? '—'),
                  _row('Email', user?.email ?? '—'),
                  const Divider(height: 32),
                  Text('Team', style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
                  const SizedBox(height: 4),
                  if (myTeams.isEmpty)
                    const Text('No teams yet.')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: activeTeamId,
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
                          style: accaFieldTextStyle,
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
                            // Capture before the await so context isn't used
                            // across an async gap.
                            final messenger = ScaffoldMessenger.of(context);
                            final team = myTeams.firstWhere(
                              (t) => t.id == activeTeamId,
                              orElse: () => myTeams.first,
                            );
                            final code = team.inviteCode;
                            final deepLink = 'accacentral://join?code=$code';
                            final text = 'Join my Acca Central team!\n$deepLink\nTeam joining code - $code';
                            final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (_) {
                              if (mounted) {
                                messenger.showSnackBar(
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
                      // Capture before the await so context isn't used
                      // across an async gap.
                      final navigator = Navigator.of(context);
                      await widget.appState.logOut();
                      if (mounted) {
                        navigator.popUntil((route) => route.isFirst);
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                  ),
                  if (seasonSummaries.isNotEmpty) ...[
                    const Divider(height: 32),
                    const Text('Season Summaries', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    for (final summary in seasonSummaries)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(summary.season, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${_positionLabel(summary.leaguePosition)} of ${summary.totalMembers} — ${summary.totalBasePoints} pts'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => SeasonSummaryScreen(summary: summary)),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
  String _positionLabel(int pos) {
    if (pos == 1) return '1st';
    if (pos == 2) return '2nd';
    if (pos == 3) return '3rd';
    return '${pos}th';
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