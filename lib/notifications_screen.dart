import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'main.dart'; // for AccaColors

class NotificationsScreen extends StatefulWidget {
  final String teamId;
  final String memberId;

  const NotificationsScreen({super.key, required this.teamId, required this.memberId});

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
    final loaded = await FirestoreService.instance.fetchNotifications(teamId: widget.teamId, memberId: widget.memberId);
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
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      return ListTile(
                        tileColor: Colors.white,
                        leading: Icon(n.read ? Icons.notifications_none : Icons.notifications_active, color: n.read ? Colors.black38 : AccaColors.gold),
                        title: Text(n.title, style: TextStyle(color: Colors.black, fontWeight: n.read ? FontWeight.normal : FontWeight.bold)),
                        subtitle: Text(n.body, style: const TextStyle(color: Colors.black54)),
                        onTap: () => tap(n),
                      );
                    },
                  ),
                ),
    );
  }
}