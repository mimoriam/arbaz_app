import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arbaz_app/services/checkin_schedule_service.dart';

class CheckInScheduleProvider extends ChangeNotifier {
  CheckInScheduleService _scheduleService;
  List<String> _schedules = [];
  bool _isLoading = true;
  String? _error;
  
  /// Track which user's schedules are currently loaded
  String? _loadedUserId;
  StreamSubscription<User?>? _authSubscription;
  
  /// Lock to serialize load operations
  Completer<void>? _loadLock;
  /// The latest user ID that was requested to be loaded
  String? _pendingLoadUserId;

  CheckInScheduleProvider(this._scheduleService);

  set scheduleService(CheckInScheduleService service) =>
      _scheduleService = service;

  List<String> get schedules => UnmodifiableListView(_schedules);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasError => _error != null;

  Future<void> retry() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _loadSchedules(user.uid);
    }
  }

  Future<void> init() async {
    final user = FirebaseAuth.instance.currentUser;
    final currentUid = user?.uid;
    
    // Return early if already initialized for the same user and not loading
    if (_loadedUserId != null && _loadedUserId == currentUid && _loadLock == null) {
      return;
    }
    
    // Subscribe to auth changes if not already subscribed
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen(
      (user) async {
        if (user == null) {
          // User signed out - reset state immediately
          _pendingLoadUserId = null;
          _schedules = [];
          _loadedUserId = null;
          _isLoading = false;
          notifyListeners();
        } else if (_loadedUserId != user.uid) {
          // Different user signed in - trigger load
          // Store as pending and trigger load (will be serialized by lock)
          await _loadSchedules(user.uid);
        }
      },
      onError: (error) {
        debugPrint('CheckInScheduleProvider auth stream error: $error');
      },
    );
    
    if (user != null) {
      // Clear existing schedules for new user
      _schedules = [];
      await _loadSchedules(user.uid);
    } else {
      _isLoading = false;
      _loadedUserId = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSchedules(String uid) async {
    // Record this as the latest requested user
    _pendingLoadUserId = uid;
    
    // Wait for any in-progress load to complete
    if (_loadLock != null) {
      await _loadLock!.future;
      // After waiting, check if we're still the latest request
      if (_pendingLoadUserId != uid) {
        return; // A newer request came in, abandon this one
      }
    }
    
    // Acquire lock
    _loadLock = Completer<void>();
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final schedules = await _scheduleService.getSchedules(uid);
      
      // Verify we're still loading for the same user before applying
      if (_pendingLoadUserId == uid) {
        _schedules = schedules;
        _loadedUserId = uid;
      }
    } catch (e) {
      if (_pendingLoadUserId == uid) {
        _error = e.toString();
      }
      debugPrint('Error loading schedules: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      
      // Release lock
      _loadLock?.complete();
      _loadLock = null;
      
      // Check if there's a newer pending request
      if (_pendingLoadUserId != null && _pendingLoadUserId != uid) {
        // A different user was requested while we were loading
        await _loadSchedules(_pendingLoadUserId!);
      }
    }
  }

  Future<void> addSchedule(String time) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_schedules.contains(time)) {
      // Optimistic update
      _schedules.add(time);
      _schedules.sort();
      notifyListeners();

      try {
        await _scheduleService.addSchedule(user.uid, time);
      } catch (e) {
        _error = e.toString();
        // Revert (reload from server to be safe)
        await _loadSchedules(user.uid);
        debugPrint('Error adding schedule: $e');
      }
    }
  }

  Future<void> removeSchedule(String time) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_schedules.contains(time)) {
      // Optimistic update
      _schedules.remove(time);
      notifyListeners();

      try {
        await _scheduleService.removeSchedule(user.uid, time);
      } catch (e) {
        _error = e.toString();
        // Revert
        await _loadSchedules(user.uid);
        debugPrint('Error removing schedule: $e');
      }
    }
  }
}
