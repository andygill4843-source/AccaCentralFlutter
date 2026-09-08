import 'package:flutter/material.dart';
import 'app_state.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

class NotificationsScreen extends StatefulWidget {
  final String teamId;
  final String memberId;
  final AppState appState;
  const NotificationsScreen({
    super.key,
    required this.teamId,
    required this.memberId,
    required this.appState,
  });
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> notifications = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    final loaded = await FirestoreService.instance.fetchNotifications(
      teamId: widget.teamId,
      memberId: widget.memberId,
    );
    setState(() {
      notifications = loaded;
      isLoading = false;
    });
  }

  Future<void> tap(AppNotification n) async {
    if (!n.read && n.id != null) {
      await FirestoreService.instance.markNotificationRead(n.id!);
      load();
    }
    if (!mounted) return;
    _navigateTo(n.type);
  }

  void _navigateTo(NotificationType type) {
    // Pop all the way back to the root route (MainTabScaffold) so the
    // bottom bar is always visible after navigation — a single pop() only
    // removes the notifications screen itself, which leaves any sub-screen
    // that was beneath it still covering the tab bar.
    Navigator.of(context).popUntil((route) => route.isFirst);
    switch (type) {
      case NotificationType.gameweekLocked:
      case NotificationType.kudosReceived:
      case NotificationType.physioUsed:
        // Home tab (0) and Physio tab (5) respectively — Physio shows the
        // fitness report; kudos and locked legs live on the Home tab.
        widget.appState.requestTabNavigation(type == NotificationType.physioUsed ? 5 : 0);
        break;
      case NotificationType.newGameweek:
      case NotificationType.deadlineReminder:
      case NotificationType.legRejected:
      case NotificationType.nudge:
      case NotificationType.challengePlaced:
      case NotificationType.challengeResolved:
      case NotificationType.fineIssued:
      case NotificationType.fineDisputeVote:
      case NotificationType.disputeResolved:
      case NotificationType.yellowCardIssued:
      case NotificationType.tournamentDrawDateSet:
      case NotificationType.tournamentDrawLive:
      case NotificationType.tournamentDrawnAgainst:
      case NotificationType.tournamentBigCupTie:
      case NotificationType.tournamentDrawCompleted:
      case NotificationType.tournamentOpponentSubmitted:
      case NotificationType.tournamentRoundWon:
      case NotificationType.tournamentRoundLost:
        // Acca Hub tab (1) — Fines, Challenges, and Tournament are all
        // accessible from the Hub's own buttons.
        widget.appState.requestTabNavigation(1);
        break;
      case NotificationType.leaguePosition:
        // League Table tab (2).
        widget.appState.requestTabNavigation(2);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AccaColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AccaColors.background,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
              ? const Center(child: Text('Nothing yet.', style: TextStyle(color: Colors.white70)))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.separated(
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.black12),
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      return ListTile(
                        tileColor: Colors.white,
                        leading: Icon(
                          n.read ? Icons.notifications_none : Icons.notifications_active,
                          color: n.read ? Colors.black38 : AccaColors.gold,
                        ),
                        title: Text(n.title, style: TextStyle(color: Colors.black, fontWeight: n.read ? FontWeight.normal : FontWeight.bold)),
                        subtitle: Text(n.body, style: const TextStyle(color: Colors.black54)),
                        trailing: n.read ? null : const Icon(Icons.chevron_right, color: Colors.black26, size: 18),
                        onTap: () => tap(n),
                      );
                    },
                  ),
                ),
    );
  }
}