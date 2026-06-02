import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();
  static String? _pendingDisplayName;
  static String? _pendingEmail;

  /// Current signed-in user, or null
  static User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Google Sign-In ─────────────────────────────────────────────────────────

  static Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await userCredential.user?.reload();
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Google sign-in error: ${e.code} — ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Google sign-in unexpected error: $e');
      rethrow;
    }
  }

  // ── Email Sign-In ──────────────────────────────────────────────────────────

  static Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.reload();
    return credential;
  }

  static Future<UserCredential> createAccountWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final trimmedEmail = email.trim();
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      _pendingDisplayName = name;
      _pendingEmail = trimmedEmail.toLowerCase();
    }
    final credential = await _auth.createUserWithEmailAndPassword(
      email: trimmedEmail,
      password: password,
    );
    if (name != null && name.isNotEmpty) {
      await credential.user?.updateDisplayName(name);
    }
    await credential.user?.sendEmailVerification();
    await credential.user?.reload();
    return credential;
  }

  static Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  static Future<void> updateDisplayName(String displayName) async {
    final user = currentUser;
    final name = displayName.trim();
    if (user == null || name.isEmpty) return;
    await user.updateDisplayName(name);
    await user.reload();
  }

  static Future<void> updatePhotoUrl(String photoUrl) async {
    final user = currentUser;
    final url = photoUrl.trim();
    if (user == null || url.isEmpty) return;
    await user.updatePhotoURL(url);
    await user.reload();
  }

  // ── Sign Out ───────────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
    _pendingDisplayName = null;
    _pendingEmail = null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String get displayName {
    final name = currentUser?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;

    final email = currentUser?.email?.trim();
    if (email != null &&
        email.isNotEmpty &&
        _pendingEmail == email.toLowerCase() &&
        _pendingDisplayName != null &&
        _pendingDisplayName!.isNotEmpty) {
      return _pendingDisplayName!;
    }

    if (email != null && email.isNotEmpty) {
      final localPart = email.split('@').first.trim();
      if (localPart.isNotEmpty) return localPart;
    }

    return 'User';
  }

  static String? get photoUrl => currentUser?.photoURL;

  static Future<String?> getIdToken() async {
    final user = currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  static Future<Map<String, String>> authHeaders() async {
    final headers = <String, String>{};
    final user = currentUser;
    final token = await getIdToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (user == null) return headers;

    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      headers['X-User-Email'] = email;
    }

    final name = displayName.trim();
    if (name.isNotEmpty) {
      headers['X-User-Name'] = name;
    }

    final photo = user.photoURL?.trim();
    if (photo != null && photo.isNotEmpty) {
      headers['X-User-Photo'] = photo;
    }

    return headers;
  }
}
