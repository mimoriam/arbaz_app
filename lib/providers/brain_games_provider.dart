import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'dart:async'; // Added for StreamSubscription

class BrainGamesProvider extends ChangeNotifier {
  late FirestoreService _firestoreService;
  bool _isEnabled = false;
  bool _isLoading = true;
  bool _isUpdating = false;

  StreamSubscription<User?>? _authSubscription;

  BrainGamesProvider(this._firestoreService);

  set firestoreService(FirestoreService service) => _firestoreService = service;

  bool get isEnabled => _isEnabled;
  bool get isLoading => _isLoading;

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> init() async {
    // Cancel any existing subscription to be safe
    await _authSubscription?.cancel();

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        _isLoading = true;
        notifyListeners();
        await _loadState(user.uid);
      } else {
        // User logged out
        _isEnabled = false;
        _isLoading = false;
        notifyListeners();
      }
    });
    
    // Handle initial state immediately just in case stream doesn't fire right away or we need synchronous-like check
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
       // Just trigger load, the stream will also handle updates but redundantly checking here ensures 
       // we don't wait for the first stream event if it's already available.
       // However, to avoid race conditions with the stream, we can rely on the stream 
       // OR just do a check here. Using the stream is more robust for changes.
       // If we want immediate data fetch without waiting for stream event:
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
      }
    } catch (e) {
      debugPrint('Error loading brain games state: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (_isUpdating) return; // Simple concurrency guard
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final previousEnabled = _isEnabled;
    if (previousEnabled == enabled) return;

    _isUpdating = true;
    
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
    } catch (e) {
      // Unconditionally revert on failure
      _isEnabled = previousEnabled;
      notifyListeners();
      debugPrint('Error updating brain games state: $e');
    } finally {
      _isUpdating = false;
    }
  }
}
