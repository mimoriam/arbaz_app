import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'dart:async';

class BrainGamesProvider extends ChangeNotifier {
  late FirestoreService _firestoreService;
  bool _isEnabled = false;
  bool _isLoading = true;
  
  /// Async queue for serializing setEnabled operations
  /// Each operation awaits the previous one before executing
  Future<void> _operationQueue = Future.value();
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
  /// Uses an async queue pattern to serialize operations, eliminating TOCTOU bugs.
  Future<bool> setEnabled(bool enabled) async {
    // Chain this operation onto the queue to ensure serialization
    // This prevents multiple calls from racing between check and execution
    final previousOperation = _operationQueue;
    final completer = Completer<bool>();
    
    // Add our operation to the queue immediately
    _operationQueue = completer.future.catchError((_) => false);
    
    // Wait for any previous operation to complete
    await previousOperation;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      completer.complete(false);
      return false;
    }

    final previousEnabled = _isEnabled;
    if (previousEnabled == enabled) {
      completer.complete(true);
      return true; // No change needed
    }

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
      completer.complete(true);
      return true;
    } catch (e) {
      // Unconditionally revert on failure
      _isEnabled = previousEnabled;
      notifyListeners();
      debugPrint('Error updating brain games state: $e');
      completer.complete(false);
      return false;
    }
  }
}
