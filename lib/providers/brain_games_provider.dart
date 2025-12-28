import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'dart:async';

class BrainGamesProvider extends ChangeNotifier {
  late FirestoreService _firestoreService;
  bool _isEnabled = false;
  bool _isLoading = true;
  
  /// Mutex-like lock for setEnabled operations
  Completer<void>? _updateLock;
  /// Track which user's state is loaded
  String? _loadedUserId;

  StreamSubscription<User?>? _authSubscription;

  BrainGamesProvider(this._firestoreService);

  set firestoreService(FirestoreService service) => _firestoreService = service;

  bool get isEnabled => _isEnabled;
  bool get isLoading => _isLoading;

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    super.dispose();
  }

  Future<void> init() async {
    // Cancel any existing subscription to prevent memory leaks
    await _authSubscription?.cancel();
    _authSubscription = null;

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        // Only reload if different user
        if (_loadedUserId != user.uid) {
          _isLoading = true;
          notifyListeners();
          await _loadState(user.uid);
        }
      } else {
        // User logged out - reset state
        _isEnabled = false;
        _isLoading = false;
        _loadedUserId = null;
        notifyListeners();
      }
    });
    
    // Handle initial state
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _loadState(user.uid);
    } else {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadState(String uid) async {
    try {
      final seniorState = await _firestoreService.getSeniorState(uid);
      if (seniorState != null) {
        _isEnabled = seniorState.brainGamesEnabled;
      } else {
        // Default to true for new users
        _isEnabled = true;
      }
      _loadedUserId = uid;
    } catch (e) {
      debugPrint('Error loading brain games state: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets the enabled state with proper concurrency protection.
  /// Uses a mutex-like pattern to prevent concurrent updates from corrupting state.
  Future<bool> setEnabled(bool enabled) async {
    // Wait for any in-progress update to complete
    if (_updateLock != null) {
      await _updateLock!.future;
    }
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final previousEnabled = _isEnabled;
    if (previousEnabled == enabled) return true; // No change needed

    // Acquire lock
    _updateLock = Completer<void>();

    // Optimistic update
    _isEnabled = enabled;
    notifyListeners();

    try {
      // Use atomic merge update instead of read-modify-write
      await _firestoreService.atomicUpdateSeniorField(
        user.uid,
        'brainGamesEnabled',
        enabled,
      );
      return true;
    } catch (e) {
      // Unconditionally revert on failure
      _isEnabled = previousEnabled;
      notifyListeners();
      debugPrint('Error updating brain games state: $e');
      return false;
    } finally {
      // Release lock
      _updateLock?.complete();
      _updateLock = null;
    }
  }
}
