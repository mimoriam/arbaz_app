import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/firestore_service.dart';

class HealthQuizProvider extends ChangeNotifier {
  FirestoreService _firestoreService;
  bool _isEnabled = true; // Default to true
  bool _isLoading = true;

  HealthQuizProvider(this._firestoreService);

  set firestoreService(FirestoreService service) => _firestoreService = service;

  bool get isEnabled => _isEnabled;
  bool get isLoading => _isLoading;

  Future<void> init() async {
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
        _isEnabled = seniorState.healthQuizEnabled;
      }
    } catch (e) {
      debugPrint('Error loading health quiz state: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _isUpdating = false;
  bool? _pendingEnabled; // Store pending update request

  /// Sets whether health quiz is enabled.
  /// Returns true if update was successful or queued, false if it failed.
  Future<bool> setEnabled(bool enabled) async {
    // If already updating, queue the value for later
    if (_isUpdating) {
      _pendingEnabled = enabled;
      return true; // Indicate request was queued
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final previousEnabled = _isEnabled;
    if (previousEnabled == enabled) return true; // No change needed

    _isUpdating = true;
    
    try {
      // Run update loop - continues until no pending values remain
      bool currentValue = enabled;
      bool lastSuccessfulValue = previousEnabled;
      
      while (true) {
        // Optimistic update
        _isEnabled = currentValue;
        notifyListeners();

        try {
          await _firestoreService.atomicUpdateSeniorField(
            user.uid,
            'healthQuizEnabled',
            currentValue,
          );
          lastSuccessfulValue = currentValue;
        } catch (e) {
          // Revert to last successful value on failure
          _isEnabled = lastSuccessfulValue;
          _pendingEnabled = null; // Clear pending on error
          notifyListeners();
          debugPrint('Error updating health quiz state: $e');
          return false;
        }

        // Check if there's a pending value to process
        if (_pendingEnabled == null) {
          // No pending updates, we're done
          break;
        }
        
        // Consume pending value if different from current
        final pending = _pendingEnabled!;
        _pendingEnabled = null;
        
        if (pending != currentValue) {
          currentValue = pending;
          // Continue loop to apply the pending value
        } else {
          // Pending is same as current, no need to update again
          break;
        }
      }
      
      return true;
    } finally {
      _isUpdating = false;
    }
  }
}
