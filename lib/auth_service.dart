import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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

  bool _googleSignInInitialized = false;

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize();
    _googleSignInInitialized = true;
  }

  /// Returns the existing AppUser if this Google account has signed in
  /// before; if user is null, this is a first-time sign-in and the caller
  /// must collect a username via completeOAuthSignUp() before proceeding.
  Future<({AppUser? user, String? suggestedDisplayName})> signInWithGoogle() async {
    await _ensureGoogleSignInInitialized();
    final GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate();
    } catch (e) {
      throw AuthException('Google sign-in was cancelled or failed.');
    }
    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw AuthException('Could not get a Google credential — please try again.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final userCredential = await _auth.signInWithCredential(credential);
    final uid = userCredential.user!.uid;
    final userDoc = await _db.collection('users').doc(uid).get();
    if (userDoc.exists) {
      return (user: AppUser.fromMap(userDoc.id, userDoc.data()!), suggestedDisplayName: null);
    }
    return (user: null, suggestedDisplayName: googleUser.displayName);
  }

  /// Same contract as signInWithGoogle(). Apple only ever provides a name on
  /// the very first authorization ever — never assume it'll be there again.
  Future<({AppUser? user, String? suggestedDisplayName})> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);
    final AuthorizationCredentialAppleID appleCredential;
    try {
      appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: nonce,
      );
    } catch (e) {
      throw AuthException('Apple sign-in was cancelled or failed.');
    }
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );
    final userCredential = await _auth.signInWithCredential(oauthCredential);
    final uid = userCredential.user!.uid;
    final userDoc = await _db.collection('users').doc(uid).get();
    if (userDoc.exists) {
      return (user: AppUser.fromMap(userDoc.id, userDoc.data()!), suggestedDisplayName: null);
    }
    final nameParts = [appleCredential.givenName, appleCredential.familyName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    return (user: null, suggestedDisplayName: nameParts.isEmpty ? null : nameParts);
  }

  /// Called from ChooseUsernameScreen once a Google/Apple sign-in has
  /// already authenticated with Firebase but has no users/{uid} doc yet.
  /// Unlike signUp(), never rolls back the Firebase Auth account on
  /// failure — it's the user's real Google/Apple identity, not something
  /// this app minted; on a taken username they just retry with another.
  Future<AppUser> completeOAuthSignUp({required String username, required String displayName}) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      throw AuthException('Not signed in — please try signing in again.');
    }
    final normalized = username.toLowerCase();
    if (!isValidUsername(normalized)) {
      throw AuthException('Usernames must be 3-20 characters, letters/numbers/underscore only.');
    }
    final uid = firebaseUser.uid;
    final email = firebaseUser.email ?? '';
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

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
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