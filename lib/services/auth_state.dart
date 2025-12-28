import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

/// Discriminated result type for auth operations
sealed class AuthResult<T> {
  const AuthResult();
}

class AuthSuccess<T> extends AuthResult<T> {
  final T data;
  const AuthSuccess(this.data);
}

class AuthFailure<T> extends AuthResult<T> {
  final String error;
  const AuthFailure(this.error);
}

/// Extension for convenient result handling
extension AuthResultExt<T> on AuthResult<T> {
  bool get isSuccess => this is AuthSuccess<T>;
  bool get isFailure => this is AuthFailure<T>;

  T? get dataOrNull => switch (this) {
        AuthSuccess<T>(:final data) => data,
        AuthFailure<T>() => null,
      };

  String? get errorOrNull => switch (this) {
        AuthSuccess<T>() => null,
        AuthFailure<T>(:final error) => error,
      };
}

/// UI-facing auth state with loading, errors, and rate limiting
class AuthState extends ChangeNotifier {
  final AuthService _authService;

  AuthState(this._authService);

  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _rateLimitedUntil;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isRateLimited =>
      _rateLimitedUntil != null && DateTime.now().isBefore(_rateLimitedUntil!);

  Duration? get rateLimitRemaining {
    if (_rateLimitedUntil == null) return null;
    final remaining = _rateLimitedUntil!.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  User? get currentUser => _authService.currentUser;
  Stream<User?> get authStateChanges => _authService.authStateChanges;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Execute auth operation with loading state and error handling.
  /// Returns [AuthResult] to distinguish success from failure.
  /// Only catches expected exceptions - programming errors are not caught.
  Future<AuthResult<T>> execute<T>(Future<T> Function() operation) async {
    if (isRateLimited) {
      _errorMessage = 'Too many attempts. Please wait and try again.';
      notifyListeners();
      return AuthFailure(_errorMessage!);
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await operation();
      return AuthSuccess(result);
    } on FirebaseAuthException catch (e) {
      _errorMessage = _mapError(e.code);
      debugPrint('Auth error: ${e.code} - ${e.message}');
      return AuthFailure(_errorMessage!);
    } on SocketException catch (e) {
      _errorMessage = 'Network error. Please check your connection.';
      debugPrint('Network error: $e');
      return AuthFailure(_errorMessage!);
    } on TimeoutException catch (e) {
      _errorMessage = 'Request timed out. Please try again.';
      debugPrint('Timeout error: $e');
      return AuthFailure(_errorMessage!);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    // Note: Programming errors (StateError, TypeError, etc.) are NOT caught
    // They will crash the app, making bugs visible in development
  }

  /// Map Firebase error codes to user-friendly messages
  String _mapError(String code) {
    return switch (code) {
      'invalid-email' => 'Please enter a valid email address.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'Invalid email or password.',
      'email-already-in-use' => 'This email is already registered.',
      'weak-password' => 'Password is too weak. Use 8+ characters.',
      'operation-not-allowed' => 'This sign-in method is not enabled.',
      'too-many-requests' => _setRateLimit(),
      'network-request-failed' =>
        'Network error. Please check your connection.',
      'user-cancelled' => '', // Silent for user cancellation
      _ => 'Something went wrong. Please try again.',
    };
  }

  String _setRateLimit() {
    _rateLimitedUntil = DateTime.now().add(const Duration(seconds: 60));
    return 'Too many attempts. Please wait and try again.';
  }

  // Convenience methods that wrap AuthService calls

  Future<AuthResult<UserCredential>> signInWithEmail(
    String email,
    String password,
  ) {
    return execute(() => _authService.signInWithEmail(email, password));
  }

  Future<AuthResult<UserCredential>> registerWithEmail(
    String email,
    String password,
    String name,
  ) {
    return execute(
      () => _authService.registerWithEmail(email, password, name),
    );
  }

  Future<AuthResult<UserCredential?>> signInWithGoogle() {
    return execute(() => _authService.signInWithGoogle());
  }

  Future<bool> sendPasswordResetEmail(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.sendPasswordResetEmail(email);
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _mapError(e.code);
      debugPrint('Auth error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      _errorMessage = 'Something went wrong. Please try again.';
      debugPrint('Unknown auth error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<AuthResult<void>> signOut() {
    return execute(() => _authService.signOut());
  }
}
