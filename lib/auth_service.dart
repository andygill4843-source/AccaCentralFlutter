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

    final UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          throw AuthException('An account already exists for that email address.');
        case 'invalid-email':
          throw AuthException("That doesn't look like a valid email address.");
        case 'weak-password':
          throw AuthException('Choose a stronger password.');
        default:
          throw AuthException(e.message ?? 'Could not create account.');
      }
    }

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

    try {
      await _db.runTransaction((transaction) async {
        final existing = await transaction.get(usernameRef);
        if (existing.exists) {
          throw AuthException('That username is already taken.');
        }
        transaction.set(usernameRef, {'uid': uid, 'email': email});
        transaction.set(userRef, user.toMap());
      });
    } catch (e) {
      // Roll back the Auth account — otherwise the email stays permanently
      // claimed by an account with no username and no profile doc.
      await credential.user?.delete();
      rethrow;
    }

    await _sendWelcomeEmail(email: email, displayName: displayName);
    return user;
  }

  /// Queues a welcome email via the Firebase "Trigger Email" Extension,
  /// which watches the `mail` collection and sends anything written here.
  /// Non-critical — a failure here shouldn't block account creation.
  Future<void> _sendWelcomeEmail({required String email, required String displayName}) async {
    try {
      await _db.collection('mail').add({
        'to': [email],
        'message': {
          'subject': 'Welcome to Acca Central',
          'html': '<p>Hi $displayName,</p>'
              '<p>Your Acca Central account is set up and ready to go. Head back into the app to join or start a team.</p>',
        },
      });
    } catch (_) {
      // Swallow — don't fail signup over a queued email.
    }
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

  /// Accepts either a username or an email. Deliberately never reveals
  /// whether the identifier actually matched an account — the UI shows the
  /// same "if an account exists..." message either way, so this method
  /// stays silent on a not-found identifier rather than throwing.
  Future<void> resetPassword(String identifier) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      throw AuthException('Enter your username or email.');
    }

    String? email;
    if (trimmed.contains('@')) {
      email = trimmed;
    } else {
      final usernameDoc = await _db.collection('usernames').doc(trimmed.toLowerCase()).get();
      email = usernameDoc.data()?['email'] as String?;
    }

    if (email == null) {
      return; // no match — stay silent, same as any other "sent" outcome
    }

    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email') {
        throw AuthException("That doesn't look like a valid email address.");
      }
      // e.g. user-not-found on a stale usernames doc — stay silent, not an enumeration signal.
    }
  }

  Future<AppUser> fetchCurrentUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return AppUser.fromMap(doc.id, doc.data()!);
  }

  Future<void> signOut() => _auth.signOut();

  User? get currentFirebaseUser => _auth.currentUser;
}