import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'main.dart'; // for AccaColors
import 'models.dart';
enum TeamSetupMode { join, create }
class TeamSetupScreen extends StatefulWidget {
  final AppState appState;
  final VoidCallback onTeamReady;
  /// Pre-filled invite code from a deep link — when set the screen opens
  /// directly in Join mode with the code already entered.
  final String? initialInviteCode;
  const TeamSetupScreen({
    super.key,
    required this.appState,
    required this.onTeamReady,
    this.initialInviteCode,
  });
  @override
  State<TeamSetupScreen> createState() => _TeamSetupScreenState();
}
class _TeamSetupScreenState extends State<TeamSetupScreen> {
  TeamSetupMode mode = TeamSetupMode.join;
  final teamNameController = TextEditingController();
  final seasonController = TextEditingController(text: '2026-27');
  final inviteCodeController = TextEditingController();
  final tournamentNameController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;
  int maxChallenges = 2;
  int maxPhysioSessions = 2;
  bool setupTournament = false;
  DateTime? tournamentDrawDateTime;

  @override
  void initState() {
    super.initState();
    if (widget.initialInviteCode != null) {
      mode = TeamSetupMode.join;
      inviteCodeController.text = widget.initialInviteCode!;
      // Clear the stored code so it isn't re-applied on the next rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.appState.consumeInviteCode();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Setup'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'Get your team set up',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AccaColors.primary),
              ),
              if (widget.initialInviteCode != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Invite link detected — your team code has been filled in below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AccaColors.gold),
                ),
              ],
              const SizedBox(height: 24),
              SegmentedButton<TeamSetupMode>(
                segments: const [
                  ButtonSegment(value: TeamSetupMode.join, label: Text('Join a team')),
                  ButtonSegment(value: TeamSetupMode.create, label: Text('Create a team')),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => setState(() => mode = selection.first),
              ),
              const SizedBox(height: 24),
              if (mode == TeamSetupMode.create) ...[
                _field('Team name', teamNameController),
                const SizedBox(height: 14),
                _field('Season', seasonController),
                const SizedBox(height: 14),
                _numberDropdown('Challenges per member this season', Icons.flash_on, maxChallenges, (v) {
                  if (v != null) setState(() => maxChallenges = v);
                }),
                const SizedBox(height: 14),
                _numberDropdown('Physio sessions per member this season', Icons.medical_services, maxPhysioSessions, (v) {
                  if (v != null) setState(() => maxPhysioSessions = v);
                }),
                const SizedBox(height: 14),
                _tournamentSection(),
              ] else
                _field('Invite code', inviteCodeController, capitalize: true),
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccaColors.gold,
                  foregroundColor: AccaColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(mode == TeamSetupMode.create ? 'Create team' : 'Join team'),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _tournamentSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Set up a knockout tournament this season?', style: TextStyle(color: Colors.black, fontSize: 14)),
            value: setupTournament,
            activeThumbColor: AccaColors.gold,
            onChanged: (v) => setState(() => setupTournament = v),
          ),
          if (setupTournament) ...[
            const SizedBox(height: 8),
            TextField(
              controller: tournamentNameController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.black),
              decoration: InputDecoration(
                labelText: 'Tournament name',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.black26),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              tileColor: AccaColors.background,
              title: Text(
                tournamentDrawDateTime == null ? 'Set draw date & time' : 'Draw: ${_formatDateTime(tournamentDrawDateTime!)}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              trailing: const Icon(Icons.calendar_today, color: AccaColors.gold, size: 18),
              onTap: pickTournamentDrawDateTime,
            ),
          ],
        ],
      ),
    );
  }
  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  Future<void> pickTournamentDrawDateTime() async {
    final initial = tournamentDrawDateTime ?? DateTime.now().add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (time == null) return;
    setState(() {
      tournamentDrawDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }
  Widget _numberDropdown(String label, IconData icon, int value, ValueChanged<int?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          initialValue: value,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            prefixIcon: Icon(icon, color: AccaColors.primary),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white24),
            ),
          ),
          dropdownColor: Colors.white,
          style: const TextStyle(color: Colors.black),
          items: [for (int i = 0; i <= 5; i++) DropdownMenuItem(value: i, child: Text('$i'))],
          onChanged: onChanged,
        ),
      ],
    );
  }
  Widget _field(String label, TextEditingController controller, {bool capitalize = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          textCapitalization: capitalize ? TextCapitalization.characters : TextCapitalization.words,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white24),
            ),
          ),
        ),
      ],
    );
  }
  Future<void> submit() async {
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;
    if (mode == TeamSetupMode.create && setupTournament) {
      if (tournamentNameController.text.trim().isEmpty || tournamentDrawDateTime == null) {
        setState(() => errorMessage = 'Enter a tournament name and set a draw date/time, or turn the tournament off.');
        return;
      }
    }
    setState(() {
      errorMessage = null;
      isLoading = true;
    });
    try {
      final team = mode == TeamSetupMode.create
          ? await FirestoreService.instance.createTeam(
              name: teamNameController.text.trim(),
              season: seasonController.text.trim(),
              managerId: userId,
            )
          : await FirestoreService.instance.joinTeam(
              inviteCode: inviteCodeController.text.trim().toUpperCase(),
              userId: userId,
            );
      final member = Member(
        id: null,
        userId: userId,
        displayName: widget.appState.currentUser?.displayName ?? 'Player',
        teamId: team.id ?? '',
        joinedAt: DateTime.now(),
        role: mode == TeamSetupMode.create ? MemberRole.manager : MemberRole.squadMember,
      );
      await FirestoreService.instance.addMember(member);
      if (mode == TeamSetupMode.create && team.id != null) {
        await FirestoreService.instance.createSeasonSettings(SeasonSettings(
          teamId: team.id!,
          season: team.season,
          maxChallengesPerMember: maxChallenges,
          maxPhysioSessionsPerMember: maxPhysioSessions,
          createdAt: DateTime.now(),
        ));
        if (setupTournament && tournamentDrawDateTime != null) {
          await FirestoreService.instance.createTournament(Tournament(
            teamId: team.id!,
            season: team.season,
            name: tournamentNameController.text.trim(),
            drawDateTime: tournamentDrawDateTime!,
            createdAt: DateTime.now(),
          ));
        }
      }
      final updatedTeamIds = [...widget.appState.currentUser!.teamIds, team.id ?? ''];
      await FirestoreService.instance.updateUserTeamIds(userId: userId, teamIds: updatedTeamIds);
      final updatedUser = AppUser(
        id: widget.appState.currentUser!.id,
        username: widget.appState.currentUser!.username,
        displayName: widget.appState.currentUser!.displayName,
        email: widget.appState.currentUser!.email,
        teamIds: updatedTeamIds,
        fcmToken: widget.appState.currentUser!.fcmToken,
        createdAt: widget.appState.currentUser!.createdAt,
      );
      widget.appState.didJoinOrCreateTeam(updatedUser);
      widget.onTeamReady();
    } catch (e) {
      setState(() => errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
}