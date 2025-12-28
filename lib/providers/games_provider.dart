import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/firestore_service.dart';
import 'package:arbaz_app/models/user_model.dart';

/// Unified Games Provider that replaces both Brain Games and Health Quiz toggles
/// When enabled, shows an optional game dialog after check-in completion
class GamesProvider extends ChangeNotifier {
  FirestoreService _firestoreService;
  bool _isEnabled = true; // Default to true for new users
  bool _isLoading = true;
  bool _isUpdating = false;

  GamesProvider(this._firestoreService);

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
        // Games is enabled if either brain games or health quiz was enabled
        _isEnabled = seniorState.brainGamesEnabled || seniorState.healthQuizEnabled;
      }
    } catch (e) {
      debugPrint('Error loading games state: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (_isUpdating) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final previousEnabled = _isEnabled;
    if (previousEnabled == enabled) return;

    _isUpdating = true;
    
    // Optimistic update
    _isEnabled = enabled;
    notifyListeners();

    try {
      final seniorState = await _firestoreService.getSeniorState(user.uid);
      if (seniorState != null) {
        // Update both brain games and health quiz together (they're unified now)
        await _firestoreService.updateSeniorState(
          user.uid,
          seniorState.copyWith(
            brainGamesEnabled: enabled,
            healthQuizEnabled: enabled,
          ),
        );
      } else {
        await _firestoreService.updateSeniorState(
          user.uid,
          SeniorState(brainGamesEnabled: enabled, healthQuizEnabled: enabled),
        );
      }
    } catch (e) {
      // Unconditionally revert on failure
      _isEnabled = previousEnabled;
      notifyListeners();
      debugPrint('Error updating games state: $e');
    } finally {
      _isUpdating = false;
    }
  }
}
