import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

/// Provider for managing vacation mode state across the app
class VacationModeProvider extends ChangeNotifier {
  bool _isVacationMode = false;
  bool _isLoading = true;
  final Completer<void> _initCompleter = Completer<void>();
  static const String _vacationModeKey = 'vacation_mode';

  bool get isVacationMode => _isVacationMode;
  bool get isLoading => _isLoading;

  VacationModeProvider() {
    _loadVacationMode();
  }

  /// Load vacation mode state from shared preferences
  Future<void> _loadVacationMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isVacationMode = prefs.getBool(_vacationModeKey) ?? false;
    } catch (e) {
      debugPrint('Error loading vacation mode: $e');
    } finally {
      _isLoading = false;
      _initCompleter.complete();
      notifyListeners();
    }
  }

  /// Set vacation mode and persist to shared preferences
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
