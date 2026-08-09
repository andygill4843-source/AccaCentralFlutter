import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'main.dart'; // for AccaColors
import 'models.dart';

enum TeamSetupMode { join, create }

class TeamSetupScreen extends StatefulWidget {
  final AppState appState;
  final VoidCallback onTeamReady;

  const TeamSetupScreen({super.key, required this.appState, required this.onTeamReady});

  @override
  State<TeamSetupScreen> createState() => _TeamSetupScreenState();
}

class _TeamSetupScreenState extends State<TeamSetupScreen> {
  TeamSetupMode mode = TeamSetupMode.join;

  final teamNameController = TextEditingController();
  final seasonController = TextEditingController(text: '2026-27');
  final inviteCodeController = TextEditingController();

  bool isLoading = false;
  String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AccaColors.background,
      body: SafeArea(
        child: Padding(
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

  Widget _field(String label, TextEditingController controller, {bool capitalize = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: AccaColors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          textCapitalization: capitalize ? TextCapitalization.characters : TextCapitalization.words,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> submit() async {
    final userId = widget.appState.currentUser?.id;
    if (userId == null) return;

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
      );
      await FirestoreService.instance.addMember(member);

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