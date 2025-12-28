import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/firestore_service.dart';

class EscalationAlarmProvider extends ChangeNotifier {
  late FirestoreService _firestoreService;
  bool _isActive = false; // Default to false
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _initialized = false; // Guard to prevent duplicate loads
  StreamSubscription<User?>? _authSubscription;

  EscalationAlarmProvider(this._firestoreService);

  set firestoreService(FirestoreService service) => _firestoreService = service;

  bool get isActive => _isActive;
  bool get isLoading => _isLoading;

  /// Initialize and subscribe to auth state changes
  Future<void> init() async {
    // Prevent multiple initializations
    if (_initialized) return;
    _initialized = true;
    
    // Load immediately for current user
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _loadState(user.uid);
    } else {
      _isLoading = false;
      notifyListeners();
    }
    
    // Subscribe to auth changes - skip(1) to avoid duplicate load since we already loaded above
    _authSubscription = FirebaseAuth.instance.authStateChanges().skip(1).listen(
      (user) async {
        if (user != null) {
          _isLoading = true;
          notifyListeners();
          await _loadState(user.uid);
        } else {
          // User signed out - reset state
          _isActive = false;
          _isLoading = false;
          notifyListeners();
        }
      },
      onError: (error) {
        debugPrint('EscalationAlarmProvider auth stream error: $error');
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadState(String uid) async {
    try {
      final seniorState = await _firestoreService.getSeniorState(uid);
      if (seniorState != null) {
        _isActive = seniorState.escalationAlarmActive;
      }
    } catch (e) {
      debugPrint('Error loading escalation alarm state: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setActive(bool active) async {
    if (_isUpdating) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final previousActive = _isActive;
    if (previousActive == active) return;

    _isUpdating = true;
    
    // Optimistic update
    _isActive = active;
    notifyListeners();

    try {
      // Use atomic merge update instead of read-modify-write
      await _firestoreService.atomicUpdateSeniorField(
        user.uid,
        'escalationAlarmActive',
        active,
      );
    } catch (e) {
      // Unconditionally revert on failure
      _isActive = previousActive;
      notifyListeners();
      debugPrint('Error updating escalation alarm state: $e');
    } finally {
      _isUpdating = false;
    }
  }
}
