import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool isValidUsername(String username) {
    final pattern = RegExp(r'^[a-z0-9_]{3,20}$');
    return pattern.hasMatch(username);
  }

  Future<AppUser> signUp({
    required String username,
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalized = username.toLowerCase();
    if (!isValidUsername(normalized)) {
      throw AuthException('Usernames must be 3-20 characters, letters/numbers/underscore only.');
    }

    final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final uid = credential.user!.uid;

    final usernameRef = _db.collection('usernames').doc(normalized);
    final userRef = _db.collection('users').doc(uid);

    final user = AppUser(
      id: uid,
      username: normalized,
      displayName: displayName,
      email: email,
      teamIds: [],
      fcmToken: null,
      createdAt: DateTime.now(),
    );

    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(usernameRef);
      if (existing.exists) {
        throw AuthException('That username is already taken.');
      }
      transaction.set(usernameRef, {'uid': uid, 'email': email});
      transaction.set(userRef, user.toMap());
    });

    return user;
  }

  Future<AppUser> logIn({required String username, required String password}) async {
    final normalized = username.toLowerCase();
    final usernameDoc = await _db.collection('usernames').doc(normalized).get();
    if (!usernameDoc.exists) {
      throw AuthException('No account found with that username.');
    }
    final data = usernameDoc.data()!;
    final uid = data['uid'] as String;
    final email = data['email'] as String;

    await _auth.signInWithEmailAndPassword(email: email, password: password);

    final userDoc = await _db.collection('users').doc(uid).get();
    return AppUser.fromMap(userDoc.id, userDoc.data()!);
  }

  Future<AppUser> fetchCurrentUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return AppUser.fromMap(doc.id, doc.data()!);
  }

  Future<void> signOut() => _auth.signOut();

  User? get currentFirebaseUser => _auth.currentUser;
}