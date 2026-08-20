import 'package:firebase_messaging/firebase_messaging.dart';
import 'firestore_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  Future<void> initAndSaveToken(String userId) async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token != null) {
      await FirestoreService.instance.saveFcmToken(userId: userId, token: token);
    }
    messaging.onTokenRefresh.listen((newToken) {
      FirestoreService.instance.saveFcmToken(userId: userId, token: newToken);
    });
  }
}