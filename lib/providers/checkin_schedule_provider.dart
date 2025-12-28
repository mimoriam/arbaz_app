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
  
  /// Map of in-flight load requests keyed by user ID for request deduplication
  /// If a load is already in progress for a user, callers wait for the same future
  final Map<String, Completer<void>> _loadRequests = {};
  
  /// Track listener count for proper subscription management
  /// Only subscribe to auth changes when there are active listeners
  int _listenerCount = 0;

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
  
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _listenerCount++;
    // Start listening when first listener attaches
    if (_listenerCount == 1) {
      _startAuthListening();
    }
  }
  
  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _listenerCount--;
    // Stop listening when last listener detaches
    if (_listenerCount == 0) {
      _stopAuthListening();
    }
  }
  
  void _startAuthListening() {
    if (_authSubscription != null) return; // Already listening
    
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) async {
        if (user == null) {
          // User signed out - reset state immediately
          _loadRequests.clear();
          _schedules = [];
          _loadedUserId = null;
          _isLoading = false;
          notifyListeners();
        } else if (_loadedUserId != user.uid) {
          // Different user signed in - trigger load
          await _loadSchedules(user.uid);
        }
      },
      onError: (error) {
        debugPrint('CheckInScheduleProvider auth stream error: $error');
      },
    );
    
    // Load initial state
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _loadedUserId != user.uid) {
      _schedules = [];
      _loadSchedules(user.uid);
    } else if (user == null) {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  void _stopAuthListening() {
    _authSubscription?.cancel();
    _authSubscription = null;
  }

  Future<void> init() async {
    final user = FirebaseAuth.instance.currentUser;
    final currentUid = user?.uid;
    
    // Return early if already initialized for the same user and no request in flight
    if (_loadedUserId != null && _loadedUserId == currentUid && !_loadRequests.containsKey(currentUid)) {
      return;
    }
    
    // Subscribe to auth changes if not already subscribed
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen(
      (user) async {
        if (user == null) {
          // User signed out - reset state immediately
          _loadRequests.clear();
          _schedules = [];
          _loadedUserId = null;
          _isLoading = false;
          notifyListeners();
        } else if (_loadedUserId != user.uid) {
          // Different user signed in - trigger load
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
    _loadRequests.clear();
    super.dispose();
  }

  /// Loads schedules for a user with request deduplication.
  /// If a load is already in progress for this user, callers wait for
  /// the same future instead of starting a new request.
  Future<void> _loadSchedules(String uid) async {
    // If already loading this user, return the existing request
    if (_loadRequests.containsKey(uid)) {
      return _loadRequests[uid]!.future;
    }
    
    // Create a new request completer for this user
    final completer = Completer<void>();
    _loadRequests[uid] = completer;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final schedules = await _scheduleService.getSchedules(uid);
      
      // Only apply if this user is still the target
      // (check if request wasn't superseded by logout/different user)
      if (_loadRequests.containsKey(uid)) {
        _schedules = schedules;
        _loadedUserId = uid;
      }
    } catch (e) {
      if (_loadRequests.containsKey(uid)) {
        _error = e.toString();
      }
      debugPrint('Error loading schedules: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      
      // Remove this request and complete it
      _loadRequests.remove(uid);
      completer.complete();
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
