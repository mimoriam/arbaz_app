import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/firestore_service.dart';


/// Provider for managing vacation mode state across the app
class VacationModeProvider extends ChangeNotifier {
  bool _isVacationMode = false;
  bool _isLoading = true;
  final Completer<void> _initCompleter = Completer<void>();
  static const String _vacationModeKey = 'vacation_mode';
  
  final FirestoreService _firestoreService;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool get isVacationMode => _isVacationMode;
  bool get isLoading => _isLoading;

  VacationModeProvider(this._firestoreService) {
    _loadVacationMode();
  }

  /// Load vacation mode state from shared preferences
  Future<void> _loadVacationMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isVacationMode = prefs.getBool(_vacationModeKey) ?? false;
      
      // Also sync with Firestore if logged in
      final user = _auth.currentUser;
      if (user != null) {
        final seniorState = await _firestoreService.getSeniorState(user.uid);
        if (seniorState != null && seniorState.vacationMode != _isVacationMode) {
           // Cloud is source of truth
           _isVacationMode = seniorState.vacationMode;
           await prefs.setBool(_vacationModeKey, _isVacationMode);
        }
      }
    } catch (e) {
      debugPrint('Error loading vacation mode: $e');
    } finally {
      _isLoading = false;
      _initCompleter.complete();
      notifyListeners();
    }
  }

  /// Set vacation mode and persist to shared preferences AND Firestore
  /// Returns true if successful, false otherwise.
  Future<bool> setVacationMode(bool value) async {
    // Ensure initialization is complete before modification
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_vacationModeKey, value);
      _isVacationMode = value;
      notifyListeners();
      
      // Update Firestore
      final user = _auth.currentUser;
      if (user != null) {
         await _firestoreService.updateVacationMode(user.uid, value);
      }
      
      return true;
    } catch (e) {
      debugPrint('Error setting vacation mode: $e');
      return false;
    }
  }

  /// Toggle vacation mode
  Future<void> toggleVacationMode() async {
    await setVacationMode(!_isVacationMode);
  }
}
