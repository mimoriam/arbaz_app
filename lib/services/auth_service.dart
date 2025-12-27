import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Exception thrown when account linking is required
class AccountLinkingRequiredException implements Exception {
  final String email;
  final List<String> existingProviders;
  final AuthCredential pendingCredential;

  AccountLinkingRequiredException({
    required this.email,
    required this.existingProviders,
    required this.pendingCredential,
  });

  @override
  String toString() =>
      'AccountLinkingRequiredException: $email exists with providers: $existingProviders';
}

/// Firebase Auth operations - no UI state, throws exceptions
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Current authenticated user
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Register new user with email and password
  Future<UserCredential> registerWithEmail(
    String email,
    String password,
    String name,
  ) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    // Ensure user exists after sign-up
    final user = credential.user;
    if (user == null) {
      throw StateError('Expected authenticated user after sign-up');
    }

    // Update display name and reload to get fresh data
    await user.updateDisplayName(name.trim());
    await user.reload();
    
    // Note: The returned credential.user is the pre-reload instance.
    // Callers should use FirebaseAuth.instance.currentUser to get
    // the updated user with the new displayName.
    return credential;
  }

  /// Sign in with Google - handles account linking
  /// Throws [AccountLinkingRequiredException] if email exists with different provider
  Future<UserCredential?> signInWithGoogle() async {
    // Trigger Google sign in flow
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

    if (googleUser == null) {
      // User cancelled the sign-in
      return null;
    }

    // Get auth details
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    // Create credential
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    try {
      // Try to sign in
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        final email = googleUser.email;

        // Email is required for account linking
        if (email.isEmpty) {
          throw FirebaseAuthException(
            code: 'missing-email',
            message: 'Google account email is required for sign-in',
          );
        }

        // Signal to caller that account linking is required
        // The caller should prompt user to sign in with their existing provider,
        // then call linkCredential() with the pending credential.
        //
        // Note: fetchSignInMethodsForEmail was deprecated for security reasons.
        // We pass an empty list - UI should treat as "unknown provider" and offer
        // generic sign-in options (e.g., email/password).
        throw AccountLinkingRequiredException(
          email: email,
          existingProviders: const [], // Provider is unknown
          pendingCredential: credential,
        );
      }
      rethrow;
    }
  }

  /// Link a pending credential after user has signed in with existing provider
  Future<UserCredential> linkCredential(AuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError(
        'No authenticated user to link credential. Sign in with existing provider first.',
      );
    }
    return await user.linkWithCredential(credential);
  }

  /// Link current account to Google
  Future<UserCredential> linkWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError(
        'No authenticated user. Sign in before linking accounts.',
      );
    }

    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'user-cancelled',
        message: 'User cancelled Google sign-in',
      );
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return await user.linkWithCredential(credential);
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Sign out from all providers
  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }
}
