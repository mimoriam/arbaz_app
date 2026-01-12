import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/connection_model.dart';
import '../models/checkin_model.dart';
import '../models/game_result.dart';
import '../models/security_vault.dart';
import '../models/activity_log.dart';
import '../models/custom_question_model.dart';
import '../utils/constants.dart';

/// Explicit streak state for clear state transitions
enum StreakState {
  sameDay,     // 0 days since last check-in
  consecutive, // 1 day since last check-in
  broken       // 2+ days since last check-in
}

/// Calculate the streak state between two dates
StreakState calculateStreakState(DateTime last, DateTime now) {
  final lastDay = DateTime(last.year, last.month, last.day);
  final nowDay = DateTime(now.year, now.month, now.day);
  final diff = nowDay.difference(lastDay).inDays;
  
  if (diff == 0) return StreakState.sameDay;
  if (diff == 1) return StreakState.consecutive;
  return StreakState.broken;
}

/// Parse a schedule time string (e.g., "11:00 AM") into hours and minutes
({int hours, int minutes})? _parseScheduleTime(String schedule) {
  try {
    String normalized = schedule.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    // Handle "9:00AM" -> "9:00 AM"
    normalized = normalized.replaceAllMapped(
      RegExp(r'(\d)(AM|PM)$'),
      (m) => '${m[1]} ${m[2]}',
    );
    
    final parts = normalized.split(' ');
    if (parts.length != 2) return null;
    
    final timePart = parts[0];
    final period = parts[1];
    if (period != 'AM' && period != 'PM') return null;
    
    final timeParts = timePart.split(':');
    if (timeParts.length != 2) return null;
    
    int hours = int.tryParse(timeParts[0]) ?? -1;
    final minutes = int.tryParse(timeParts[1]) ?? -1;
    
    if (hours < 1 || hours > 12 || minutes < 0 || minutes > 59) return null;
    
    // Convert to 24-hour
    if (period == 'PM' && hours != 12) hours += 12;
    if (period == 'AM' && hours == 12) hours = 0;
    
    return (hours: hours, minutes: minutes);
  } catch (_) {
    return null;
  }
}

/// Calculate the next expected check-in time based on schedules
/// Returns null if vacation mode should skip (no schedules)
/// 
/// If [timezone] is provided, uses timezone-aware same-day detection.
/// Otherwise falls back to local time comparison.
/// 
/// If [completedSchedulesToday] is provided, those schedules are skipped
/// when calculating the next check-in time. This ensures that after checking
/// in for a schedule, the next displayed time is correct even if new schedules
/// are added.
DateTime? calculateNextExpectedCheckIn(
  List<String> schedules,
  DateTime now,
  DateTime? lastCheckIn, {
  String? timezone,
  List<String>? completedSchedulesToday,
}) {
  final effectiveSchedules = schedules.isNotEmpty ? schedules : ['11:00 AM'];
  final completed = completedSchedulesToday ?? [];
  
  // Filter out completed schedules for today's calculation
  // Normalize for case-insensitive comparison
  final completedNormalized = completed.map((s) => s.toUpperCase()).toSet();
  final pendingSchedules = effectiveSchedules.where((schedule) {
    return !completedNormalized.contains(schedule.toUpperCase());
  }).toList();
  
  // If all schedules are completed, find earliest schedule tomorrow
  if (pendingSchedules.isEmpty) {
    DateTime? earliest;
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    
    for (final schedule in effectiveSchedules) {
      final parsed = _parseScheduleTime(schedule);
      if (parsed == null) continue;
      
      final scheduleTime = DateTime(
        tomorrow.year, tomorrow.month, tomorrow.day,
        parsed.hours, parsed.minutes,
      );
      
      if (earliest == null || scheduleTime.isBefore(earliest)) {
        earliest = scheduleTime;
      }
    }
    return earliest;
  }
  
  // There are pending schedules - find next upcoming among pending only
  DateTime? nextToday;
  DateTime? earliestToday; // For "running late" detection
  DateTime? earliestTomorrow;
  
  for (final schedule in pendingSchedules) {
    final parsed = _parseScheduleTime(schedule);
    if (parsed == null) continue;
    
    // Today's schedule
    final todayTime = DateTime(
      now.year, now.month, now.day,
      parsed.hours, parsed.minutes,
    );
    
    // Track earliest PENDING schedule for today (even if passed - for running late detection)
    if (earliestToday == null || todayTime.isBefore(earliestToday)) {
      earliestToday = todayTime;
    }
    
    if (todayTime.isAfter(now)) {
      if (nextToday == null || todayTime.isBefore(nextToday)) {
        nextToday = todayTime;
      }
    }
    
    // Tomorrow's schedule
    final tomorrowTime = DateTime(
      now.year, now.month, now.day + 1,
      parsed.hours, parsed.minutes,
    );
    
    if (earliestTomorrow == null || tomorrowTime.isBefore(earliestTomorrow)) {
      earliestTomorrow = tomorrowTime;
    }
  }
  
  // If there's an upcoming PENDING schedule today, use it
  // Otherwise, if all today's pending schedules have passed, return earliest today for "running late" detection
  // Only fall back to tomorrow if there are no pending schedules today at all
  return nextToday ?? earliestToday ?? earliestTomorrow;
}

/// Calculate which schedule times have passed today and haven't been satisfied yet.
/// Returns list of schedule strings (e.g., ["9:00 AM", "11:00 AM"]) that should be
/// marked as completed when user checks in now.
/// 
/// Used for multi check-in support where one check-in satisfies all past-due schedules.
List<String> getPendingSchedules(
  List<String> allSchedules,
  List<String> completedSchedules,
  DateTime now,
) {
  final pending = <String>[];
  
  for (final schedule in allSchedules) {
    // Skip if already completed today
    if (completedSchedules.contains(schedule.toUpperCase()) ||
        completedSchedules.contains(schedule)) {
      continue;
    }
    
    final parsed = _parseScheduleTime(schedule);
    if (parsed == null) continue;
    
    // Calculate today's time for this schedule
    final scheduleTime = DateTime(
      now.year, now.month, now.day,
      parsed.hours, parsed.minutes,
    );
    
    // If schedule time has passed, it's pending
    if (now.isAfter(scheduleTime) || now.isAtSameMomentAs(scheduleTime)) {
      pending.add(schedule.toUpperCase());
    }
  }
  
  return pending;
}

/// Check if all schedules for today have been completed.
/// Used to determine if check-in button should be disabled.
bool areAllSchedulesCompleted(
  List<String> allSchedules,
  List<String> completedSchedules,
  DateTime now,
) {
  for (final schedule in allSchedules) {
    final scheduleUpper = schedule.toUpperCase();
    
    // Check if this schedule has been completed
    if (completedSchedules.contains(scheduleUpper) ||
        completedSchedules.contains(schedule)) {
      continue;
    }
    
    final parsed = _parseScheduleTime(schedule);
    if (parsed == null) continue;
    
    // Calculate today's time for this schedule
    final scheduleTime = DateTime(
      now.year, now.month, now.day,
      parsed.hours, parsed.minutes,
    );
    
    // If schedule time has passed and not completed, not all done
    if (now.isAfter(scheduleTime) || now.isAtSameMomentAs(scheduleTime)) {
      return false;
    }
  }
  
  // All past-due schedules are completed
  return true;
}

/// Check if there are ANY uncompleted schedules for today (including future ones).
/// Used to determine if check-in button should be enabled at all.
/// Returns true if there are pending check-ins the user can do today.
bool hasAnyPendingSchedules(
  List<String> allSchedules,
  List<String> completedSchedules,
) {
  for (final schedule in allSchedules) {
    final scheduleUpper = schedule.toUpperCase();
    
    // Check if this schedule has been completed
    if (!completedSchedules.contains(scheduleUpper) &&
        !completedSchedules.contains(schedule)) {
      // Found an uncompleted schedule
      return true;
    }
  }
  
  // All schedules are completed
  return false;
}

/// Get schedules that are overdue (time has passed but not completed).
/// Used to determine if yellow "running late" button should be shown.
List<String> getOverdueSchedules(
  List<String> allSchedules,
  List<String> completedSchedules,
  DateTime now,
) {
  final overdue = <String>[];
  
  for (final schedule in allSchedules) {
    final scheduleUpper = schedule.toUpperCase();
    
    // Skip if already completed
    if (completedSchedules.contains(scheduleUpper) ||
        completedSchedules.contains(schedule)) {
      continue;
    }
    
    final parsed = _parseScheduleTime(schedule);
    if (parsed == null) continue;
    
    // Calculate today's time for this schedule
    final scheduleTime = DateTime(
      now.year, now.month, now.day,
      parsed.hours, parsed.minutes,
    );
    
    // If schedule time has passed, it's overdue
    if (now.isAfter(scheduleTime)) {
      overdue.add(scheduleUpper);
    }
  }
  
  return overdue;
}

/// Get the next schedule to resolve when checking in.
/// - If checking in EARLY (before any schedule time): returns only the nearest upcoming schedule
/// - If checking in LATE (after one or more schedule times): returns all overdue schedules
/// 
/// This ensures that early check-ins only resolve the nearest schedule,
/// while late check-ins resolve all missed schedules at once.
List<String> getSchedulesToResolve(
  List<String> allSchedules,
  List<String> completedSchedules,
  DateTime now,
) {
  final overdue = getOverdueSchedules(allSchedules, completedSchedules, now);
  
  // If there are overdue schedules, resolve all of them
  if (overdue.isNotEmpty) {
    return overdue;
  }
  
  // No overdue schedules - find the nearest upcoming schedule
  String? nearestSchedule;
  DateTime? nearestTime;
  
  for (final schedule in allSchedules) {
    final scheduleUpper = schedule.toUpperCase();
    
    // Skip if already completed
    if (completedSchedules.contains(scheduleUpper) ||
        completedSchedules.contains(schedule)) {
      continue;
    }
    
    final parsed = _parseScheduleTime(schedule);
    if (parsed == null) continue;
    
    // Calculate today's time for this schedule
    final scheduleTime = DateTime(
      now.year, now.month, now.day,
      parsed.hours, parsed.minutes,
    );
    
    // Only consider future schedules
    if (scheduleTime.isAfter(now)) {
      if (nearestTime == null || scheduleTime.isBefore(nearestTime)) {
        nearestTime = scheduleTime;
        nearestSchedule = scheduleUpper;
      }
    }
  }
  
  // Return the nearest upcoming schedule, or empty if none found
  return nearestSchedule != null ? [nearestSchedule] : [];
}

/// Retry a Future with exponential backoff for transient failures
/// Useful for critical Firestore operations that may fail due to network issues
Future<T> retryWithBackoff<T>(
  Future<T> Function() operation, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 500),
}) async {
  Duration delay = initialDelay;
  
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await operation();
    } catch (e) {
      // Don't retry on the last attempt
      if (attempt == maxAttempts) rethrow;
      
      // For Firestore exceptions, only retry on transient errors
      final errorMessage = e.toString().toLowerCase();
      final isTransient = errorMessage.contains('unavailable') ||
          errorMessage.contains('deadline') ||
          errorMessage.contains('timeout') ||
          errorMessage.contains('network');
      
      if (!isTransient) rethrow;
      
      // Wait with exponential backoff before retrying
      await Future.delayed(delay);
      delay *= 2; // Exponential backoff
    }
  }
  throw StateError('Retry logic should not reach here');
}

/// Firestore operations with subcollection structure
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ===== Collection References =====

  DocumentReference _profileRef(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('profile');

  DocumentReference _rolesRef(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('roles');

  DocumentReference _seniorStateRef(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('seniorState');

  DocumentReference _familyStateRef(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('familyState');
      
  CollectionReference _checkInsRef(String uid) =>
      _db.collection('users').doc(uid).collection('checkIns');

  CollectionReference _requestsRef(String uid) =>
      _db.collection('users').doc(uid).collection('requests');

  CollectionReference _gameResultsRef(String uid) =>
      _db.collection('users').doc(uid).collection('gameResults');

  DocumentReference _securityVaultRef(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('securityVault');

  CollectionReference _activityLogsRef(String uid) =>
      _db.collection('users').doc(uid).collection('activityLogs');

  CollectionReference _customQuestionsRef(String uid) =>
      _db.collection('users').doc(uid).collection('customQuestions');

  CollectionReference get _connectionsRef => _db.collection('connections');

  // ===== Profile Operations =====

  Future<void> createUserProfile(String uid, UserProfile profile) async {
    await _profileRef(uid).set(profile.toFirestore());
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _profileRef(uid).get();
    if (!doc.exists) return null;
    try {
      return UserProfile.fromFirestore(doc);
    } catch (e) {
      // Use debugPrint for consistent logging (imported via constants.dart -> foundation)
      // Note: debugPrint works in pure Dart when flutter/foundation.dart is imported elsewhere
      assert(() {
        // ignore: avoid_print - debugPrint equivalent for release mode
        print('FirestoreService: Invalid profile data for user $uid: $e');
        return true;
      }());
      return null; // Return null for malformed profiles
    }
  }

  /// Stream real-time updates to a user's profile
  /// Used for profile photo sync across screens
  Stream<UserProfile?> streamUserProfile(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    
    return _profileRef(uid)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          try {
            return UserProfile.fromFirestore(doc);
          } catch (e) {
            assert(() {
              return true;
            }());
            return null;
          }
        })
        .transform(
          StreamTransformer<UserProfile?, UserProfile?>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              // Emit null to subscribers for graceful degradation
              sink.add(null);
            },
          ),
        );
  }

  /// Updates the lastLoginAt timestamp for an existing profile.
  Future<void> updateLastLogin(String uid) async {
    await _profileRef(uid).update({
      'lastLoginAt': Timestamp.now(),
    });
  }
  
  /// Updates user location in profile
  Future<void> updateUserLocation(String uid, double latitude, double longitude, String? address) async {
    final Map<String, dynamic> updates = {
      'latitude': latitude,
      'longitude': longitude,
    };
    if (address != null) {
      updates['locationAddress'] = address;
    }
    await _profileRef(uid).update(updates);
  }

  /// Updates specific fields on an existing user profile.
  Future<void> updateUserProfile(
    String uid,
    Map<String, dynamic> updates,
  ) async {
    await _profileRef(uid).update(updates);
  }

  /// Updates FCM token for push notifications
  Future<void> updateFcmToken(String uid, String token) async {
    await _profileRef(uid).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  // ===== Roles Operations =====

  Future<UserRoles?> getUserRoles(String uid) async {
    final doc = await _rolesRef(uid).get();
    if (!doc.exists) return null;
    return UserRoles.fromFirestore(doc);
  }

  Future<void> setRole(
    String uid, {
    bool? isSenior,
    bool? isFamilyMember,
  }) async {
    final updates = <String, dynamic>{};
    if (isSenior != null) updates['isSenior'] = isSenior;
    if (isFamilyMember != null) updates['isFamilyMember'] = isFamilyMember;

    if (updates.isEmpty) return;

    await _rolesRef(uid).set(updates, SetOptions(merge: true));
  }

  Future<void> setAsSenior(String uid) async {
    // When user explicitly chooses to be a senior (initial role selection),
    // they should be confirmed automatically. The confirmation dialog is
    // only for users who were never seniors switching to senior view.
    // Note: hasCompletedSeniorSetup is false until they pick their check-in time.
    await _rolesRef(uid).set({
      'isSenior': true,
      'hasConfirmedSeniorRole': true,
      'hasCompletedSeniorSetup': false, // Will be true after time selection
    }, SetOptions(merge: true));
    
    // Only set seniorCreatedAt - schedule will be set in time selection screen
    final seniorState = await getSeniorState(uid);
    if (seniorState == null || seniorState.seniorCreatedAt == null) {
      await _seniorStateRef(uid).set({
        'seniorCreatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    }
  }

  /// Completes senior setup by saving the selected check-in time.
  /// Called after senior selects their preferred time in CheckInTimeSelectionScreen.
  Future<void> completeSeniorSetup(String uid, String selectedTime) async {
    final now = DateTime.now();
    final schedules = [selectedTime];
    final nextExpected = calculateNextExpectedCheckIn(schedules, now, null);
    
    // Update schedules and next expected check-in
    await _seniorStateRef(uid).set({
      'checkInSchedules': schedules,
      if (nextExpected != null) 'nextExpectedCheckIn': Timestamp.fromDate(nextExpected),
    }, SetOptions(merge: true));
    
    // Mark setup as complete
    await _rolesRef(uid).set({
      'hasCompletedSeniorSetup': true,
    }, SetOptions(merge: true));
  }

  Future<void> setAsFamilyMember(String uid) async {
    await setRole(uid, isFamilyMember: true);
  }

  /// Updates the user's current active role in Firestore.
  /// This persists across logout/login sessions.
  Future<void> updateCurrentRole(String uid, String role) async {
    if (role != 'senior' && role != 'family') return;
    await _rolesRef(uid).set({
      'currentRole': role,
    }, SetOptions(merge: true));
  }

  /// Marks the user as having explicitly confirmed they want to be a senior.
  /// This enables their data to appear in family dashboards and charts.
  /// Called when user confirms the senior opt-in dialog.
  Future<void> confirmSeniorRole(String uid) async {
    await _rolesRef(uid).set({
      'hasConfirmedSeniorRole': true,
      'isSenior': true,
    }, SetOptions(merge: true));
  }

  /// Updates the user's Pro subscription status and plan type.
  Future<void> setProStatus(String uid, bool isPro, {String subscriptionPlan = 'free'}) async {
    await _rolesRef(uid).set({
      'isPro': isPro,
      'subscriptionPlan': subscriptionPlan,
    }, SetOptions(merge: true));
  }

  /// Streams the user's roles (including Pro status)
  Stream<UserRoles?> streamUserRoles(String uid) {
    return _rolesRef(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserRoles.fromFirestore(doc);
    });
  }


  // ===== Volatile State Operations =====

  Future<SeniorState?> getSeniorState(String uid) async {
    final doc = await _seniorStateRef(uid).get();
    if (!doc.exists) return null;
    return SeniorState.fromFirestore(doc);
  }

  Future<void> updateSeniorState(String uid, SeniorState state) async {
    await _seniorStateRef(uid).set(state.toFirestore(), SetOptions(merge: true));
  }

  Future<void> updateVacationMode(String uid, bool isEnabled) async {
    if (isEnabled) {
      // Vacation ON - clear nextExpectedCheckIn to prevent false alerts
      await _seniorStateRef(uid).set({
        'vacationMode': true,
        'nextExpectedCheckIn': FieldValue.delete(),
      }, SetOptions(merge: true));
    } else {
      // Vacation OFF - recalculate nextExpectedCheckIn
      final seniorState = await getSeniorState(uid);
      final schedules = seniorState?.checkInSchedules ?? ['11:00 AM'];
      final lastCheckIn = seniorState?.lastCheckIn;
      final nextExpected = calculateNextExpectedCheckIn(schedules, DateTime.now(), lastCheckIn);
      
      await _seniorStateRef(uid).set({
        'vacationMode': false,
        if (nextExpected != null) 'nextExpectedCheckIn': Timestamp.fromDate(nextExpected),
      }, SetOptions(merge: true));
    }
  }

  /// Triggers an SOS alert - sets sosActive to true and records timestamp
  /// This is called when senior taps the emergency SOS button
  Future<void> triggerSOS(String uid) async {
    await _seniorStateRef(uid).set({
      'sosActive': true,
      'sosTriggeredAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  /// Triggers an SOS alert with optional location data
  /// Location fields are only set if provided (graceful degradation)
  Future<void> triggerSOSWithLocation(
    String uid, {
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final Map<String, dynamic> data = {
      'sosActive': true,
      'sosTriggeredAt': Timestamp.now(),
    };
    
    // Only add location fields if provided
    if (latitude != null && longitude != null) {
      data['sosLocationLatitude'] = latitude;
      data['sosLocationLongitude'] = longitude;
      if (address != null) {
        data['sosLocationAddress'] = address;
      }
    }
    
    await _seniorStateRef(uid).set(data, SetOptions(merge: true));
  }

  /// Resolves an SOS alert - sets sosActive to false
  /// Called by family member to acknowledge the alert
  Future<void> resolveSOS(String uid) async {
    await _seniorStateRef(uid).set({
      'sosActive': false,
    }, SetOptions(merge: true));
  }

  /// Stream senior state for real-time updates (avoids polling)
  Stream<SeniorState?> streamSeniorState(String seniorUid) {
    if (seniorUid.isEmpty) return Stream.value(null);
    
    return _seniorStateRef(seniorUid)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          return SeniorState.fromFirestore(snap);
        })
        .transform(
          StreamTransformer<SeniorState?, SeniorState?>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              // Log the error (using print since debugPrint requires flutter import)
              // Emit null to subscribers for graceful degradation
              sink.add(null);
            },
          ),
        );
  }

  Future<void> mergeCheckInSchedules(String uid, List<String> schedules) async {
    await _seniorStateRef(uid).set({
      'checkInSchedules': schedules,
    }, SetOptions(merge: true));
  }

  /// Atomically adds a schedule time using a transaction to prevent race conditions
  /// Also recalculates nextExpectedCheckIn to keep Cloud Functions in sync
  Future<void> atomicAddSchedule(String uid, String time) async {
    await _db.runTransaction((transaction) async {
      final seniorStateDoc = await transaction.get(_seniorStateRef(uid));
      
      List<String> currentSchedules = AppConstants.defaultSchedules;
      DateTime? lastCheckIn;
      List<String> completedSchedulesToday = [];
      DateTime? lastScheduleResetDate;
      final now = DateTime.now();
      
      if (seniorStateDoc.exists) {
        final data = seniorStateDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          if (data['checkInSchedules'] is List) {
            currentSchedules = (data['checkInSchedules'] as List)
                .map((e) => e.toString())
                .toList();
          }
          if (data['lastCheckIn'] is Timestamp) {
            lastCheckIn = (data['lastCheckIn'] as Timestamp).toDate();
          }
          if (data['completedSchedulesToday'] is List) {
            completedSchedulesToday = (data['completedSchedulesToday'] as List)
                .map((e) => e.toString())
                .toList();
          }
          if (data['lastScheduleResetDate'] is Timestamp) {
            lastScheduleResetDate = (data['lastScheduleResetDate'] as Timestamp).toDate();
          }
          
          // Reset completed schedules if it's a new day
          final isNewDay = lastScheduleResetDate == null ||
              lastScheduleResetDate.year != now.year ||
              lastScheduleResetDate.month != now.month ||
              lastScheduleResetDate.day != now.day;
          if (isNewDay) {
            completedSchedulesToday = [];
          }
        }
      }
      
      // Add new time and calculate next expected (considering completed schedules)
      final updatedSchedules = [...currentSchedules, time];
      final nextExpected = calculateNextExpectedCheckIn(
        updatedSchedules,
        now,
        lastCheckIn,
        completedSchedulesToday: completedSchedulesToday,
      );
      
      transaction.set(_seniorStateRef(uid), {
        'checkInSchedules': FieldValue.arrayUnion([time]),
        if (nextExpected != null) 'nextExpectedCheckIn': Timestamp.fromDate(nextExpected),
      }, SetOptions(merge: true));
    });
  }


  /// Atomically removes a schedule time using a transaction to prevent race conditions
  /// Also recalculates nextExpectedCheckIn to keep Cloud Functions in sync
  Future<void> atomicRemoveSchedule(String uid, String time) async {
    await _db.runTransaction((transaction) async {
      final seniorStateDoc = await transaction.get(_seniorStateRef(uid));
      
      List<String> currentSchedules = AppConstants.defaultSchedules;
      DateTime? lastCheckIn;
      List<String> completedSchedulesToday = [];
      DateTime? lastScheduleResetDate;
      final now = DateTime.now();
      
      if (seniorStateDoc.exists) {
        final data = seniorStateDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          if (data['checkInSchedules'] is List) {
            currentSchedules = (data['checkInSchedules'] as List)
                .map((e) => e.toString())
                .toList();
          }
          if (data['lastCheckIn'] is Timestamp) {
            lastCheckIn = (data['lastCheckIn'] as Timestamp).toDate();
          }
          if (data['completedSchedulesToday'] is List) {
            completedSchedulesToday = (data['completedSchedulesToday'] as List)
                .map((e) => e.toString())
                .toList();
          }
          if (data['lastScheduleResetDate'] is Timestamp) {
            lastScheduleResetDate = (data['lastScheduleResetDate'] as Timestamp).toDate();
          }
          
          // Reset completed schedules if it's a new day
          final isNewDay = lastScheduleResetDate == null ||
              lastScheduleResetDate.year != now.year ||
              lastScheduleResetDate.month != now.month ||
              lastScheduleResetDate.day != now.day;
          if (isNewDay) {
            completedSchedulesToday = [];
          }
        }
      }
      
      // Remove time (also remove from completed if present) and calculate next expected
      final updatedSchedules = currentSchedules.where((s) => s != time).toList();
      final updatedCompleted = completedSchedulesToday
          .where((s) => s.toUpperCase() != time.toUpperCase())
          .toList();
      
      final nextExpected = calculateNextExpectedCheckIn(
        updatedSchedules,
        now,
        lastCheckIn,
        completedSchedulesToday: updatedCompleted,
      );
      
      transaction.set(_seniorStateRef(uid), {
        'checkInSchedules': FieldValue.arrayRemove([time]),
        // Also remove from completed to clean up state
        'completedSchedulesToday': updatedCompleted,
        if (nextExpected != null) 'nextExpectedCheckIn': Timestamp.fromDate(nextExpected),
      }, SetOptions(merge: true));
    });
  }


  /// Atomically updates a single field in SeniorState using merge
  /// Avoids read-modify-write race conditions
  Future<void> atomicUpdateSeniorField(String uid, String field, dynamic value) async {
    await _seniorStateRef(uid).set({
      field: value,
    }, SetOptions(merge: true));
  }

  /// Atomically increments gamesPlayedToday counter with day boundary reset.
  /// If the lastGamePlayResetDate is from a previous day, resets counter to 1.
  /// Otherwise, increments the counter by 1.
  /// Returns the new count for display purposes.
  Future<int> incrementGamesPlayedToday(String uid) async {
    final now = DateTime.now();
    int newCount = 1;
    
    await _db.runTransaction((transaction) async {
      final seniorStateDoc = await transaction.get(_seniorStateRef(uid));
      
      if (seniorStateDoc.exists) {
        final data = seniorStateDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          int currentCount = (data['gamesPlayedToday'] as num?)?.toInt() ?? 0;
          DateTime? lastResetDate;
          
          if (data['lastGamePlayResetDate'] is Timestamp) {
            lastResetDate = (data['lastGamePlayResetDate'] as Timestamp).toDate();
          }
          
          // Check if it's a new day
          final isNewDay = lastResetDate == null ||
              lastResetDate.year != now.year ||
              lastResetDate.month != now.month ||
              lastResetDate.day != now.day;
          
          if (isNewDay) {
            // Reset for new day
            newCount = 1;
          } else {
            // Increment existing count
            newCount = currentCount + 1;
          }
        }
      }
      
      transaction.set(_seniorStateRef(uid), {
        'gamesPlayedToday': newCount,
        'lastGamePlayResetDate': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    });
    
    return newCount;
  }

  /// Gets current gamesPlayedToday count, handling day boundary reset.
  /// Returns 0 if it's a new day or no data exists.
  Future<int> getGamesPlayedToday(String uid) async {
    final seniorState = await getSeniorState(uid);
    if (seniorState == null) return 0;
    
    final now = DateTime.now();
    final lastResetDate = seniorState.lastGamePlayResetDate;
    
    // Check if it's a new day
    if (lastResetDate == null ||
        lastResetDate.year != now.year ||
        lastResetDate.month != now.month ||
        lastResetDate.day != now.day) {
      return 0; // New day, count resets
    }
    
    return seniorState.gamesPlayedToday;
  }

  Future<FamilyState?> getFamilyState(String uid) async {
    final doc = await _familyStateRef(uid).get();
    if (!doc.exists) return null;
    return FamilyState.fromFirestore(doc);
  }

  Future<void> updateFamilyState(String uid, FamilyState state) async {
    await _familyStateRef(uid).set(state.toFirestore(), SetOptions(merge: true));
  }
  
  // ===== Check-in Operations =====
  
  /// Records a check-in atomically using a transaction to prevent race conditions
  /// For multi check-in support, this satisfies all past-due schedules not yet completed.
  Future<void> recordCheckIn(String uid, CheckInRecord record) async {
    final seniorStateRef = _seniorStateRef(uid);
    final profileRef = _profileRef(uid);
    
    await _db.runTransaction((transaction) async {
      // Capture timestamp once at start for consistent day-boundary logic
      final now = DateTime.now();
      
      // 1. Read senior state within transaction
      final seniorStateDoc = await transaction.get(seniorStateRef);
      
      int newStreak = 1;
      DateTime startDate = DateTime.now();
      List<String> schedules = ['11:00 AM'];
      List<String> completedSchedulesToday = [];
      DateTime? lastScheduleResetDate;
      
      if (seniorStateDoc.exists) {
        final rawData = seniorStateDoc.data();
        if (rawData != null && rawData is Map<String, dynamic>) {
          final data = rawData;
          // Get current streak (validate: must be non-negative)
          final currentStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;
          
          // Get stored start date
          if (data['startDate'] is Timestamp) {
            startDate = (data['startDate'] as Timestamp).toDate();
          }
          
          // Get schedules
          if (data['checkInSchedules'] is List) {
            schedules = (data['checkInSchedules'] as List)
                .map((e) => e.toString())
                .toList();
          }
          
          // Get completed schedules and reset date
          if (data['completedSchedulesToday'] is List) {
            completedSchedulesToday = (data['completedSchedulesToday'] as List)
                .map((e) => e.toString())
                .toList();
          }
          if (data['lastScheduleResetDate'] is Timestamp) {
            lastScheduleResetDate = (data['lastScheduleResetDate'] as Timestamp).toDate();
          }
          
          final isNewDay = lastScheduleResetDate == null ||
              lastScheduleResetDate.year != now.year ||
              lastScheduleResetDate.month != now.month ||
              lastScheduleResetDate.day != now.day;
          
          if (isNewDay) {
            completedSchedulesToday = [];
            lastScheduleResetDate = now;
          }
          
          // Get last check-in for streak calculation
          final lastCheckInTimestamp = data['lastCheckIn'] as Timestamp?;
          if (lastCheckInTimestamp != null) {
            final lastCheckIn = lastCheckInTimestamp.toDate();
            
            // Use explicit state machine for clarity
            final streakState = calculateStreakState(lastCheckIn, record.timestamp);
            
            switch (streakState) {
              case StreakState.sameDay:
                // Same day check-in, keep current streak (minimum 1)
                newStreak = currentStreak > 0 ? currentStreak : 1;
              case StreakState.consecutive:
                // Consecutive day, increment streak
                newStreak = currentStreak + 1;
              case StreakState.broken:
                // Streak broken, reset to 1 and update startDate
                newStreak = 1;
                startDate = record.timestamp;
            }
          } else if (currentStreak > 0) {
            // Edge case: has streak but no lastCheckIn timestamp
            // This shouldn't happen in normal operation - reset to safe state
            newStreak = 1;
            startDate = record.timestamp;
          }
        }
      }
      
      // 2. Calculate which schedules this check-in satisfies
      // Uses getSchedulesToResolve to handle both early and late check-ins correctly:
      // - Early check-in (before schedule time): resolves only the nearest upcoming schedule
      // - Late check-in (after schedule time): resolves all overdue schedules
      final satisfiedSchedules = getSchedulesToResolve(
        schedules,
        completedSchedulesToday,
        now,
      );
      
      // Add satisfied schedules to completed list
      final updatedCompleted = [...completedSchedulesToday, ...satisfiedSchedules];
      
      // 3. Create check-in document with scheduledFor field populated
      final checkInWithSchedule = record.copyWith(
        scheduledFor: satisfiedSchedules,
      );
      final checkInDocRef = _checkInsRef(uid).doc();
      transaction.set(checkInDocRef, checkInWithSchedule.toFirestore());
      
      // 4. Calculate next expected check-in
      final nextExpected = calculateNextExpectedCheckIn(
        schedules,
        now,
        record.timestamp,
      );
      
      // 5. Update senior state with all multi check-in tracking
      transaction.set(seniorStateRef, {
        'lastCheckIn': Timestamp.fromDate(record.timestamp),
        'currentStreak': newStreak,
        'startDate': Timestamp.fromDate(startDate),
        'completedSchedulesToday': updatedCompleted,
        'lastScheduleResetDate': Timestamp.fromDate(lastScheduleResetDate ?? now),
        'missedCheckInsToday': 0, // Reset missed counter on successful check-in
        if (nextExpected != null) 'nextExpectedCheckIn': Timestamp.fromDate(nextExpected),
      }, SetOptions(merge: true));
      
      // 6. If location info is present, update user profile location
      if (record.latitude != null && record.longitude != null) {
        final Map<String, dynamic> locationUpdates = {
          'latitude': record.latitude,
          'longitude': record.longitude,
        };
        if (record.locationAddress != null) {
          locationUpdates['locationAddress'] = record.locationAddress;
        }
        transaction.set(profileRef, locationUpdates, SetOptions(merge: true));
      }
    });
  }
  
  Future<List<CheckInRecord>> getCheckInsForMonth(String uid, int year, int month) async {
    final start = DateTime(year, month, 1);
    // Handle December case for end date
    final endYear = month == 12 ? year + 1 : year;
    final endMonth = month == 12 ? 1 : month + 1;
    final end = DateTime(endYear, endMonth, 1);
    
    final snapshot = await _checkInsRef(uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .orderBy('timestamp', descending: true)
        .get();
        
    return snapshot.docs
        .map((doc) => CheckInRecord.fromFirestore(doc))
        .toList();
  }

  /// Get check-ins for a senior for the past 7 days
  /// Uses a single indexed query (requires composite index on userId + timestamp)
  /// Returns empty list on error for graceful degradation
  Future<List<CheckInRecord>> getSeniorCheckInsForWeek(String seniorUid) async {
    if (seniorUid.isEmpty) return [];
    try {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final snapshot = await _checkInsRef(seniorUid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekAgo))
          .orderBy('timestamp', descending: true)
          .get();
      return snapshot.docs.map((d) => CheckInRecord.fromFirestore(d)).toList();
    } catch (e) {
      // debugPrint('Error fetching weekly check-ins: $e');
      return []; // Graceful degradation
    }
  }

  // ===== Game Results Operations =====

  /// Saves a game result to the user's gameResults subcollection
  Future<void> saveGameResult(String uid, GameResult result) async {
    await _gameResultsRef(uid).add(result.toFirestore());
  }

  /// Gets game results for a user, optionally limited and filtered by month
  Future<List<GameResult>> getGameResults(String uid, {int? limit, int? year, int? month}) async {
    if (uid.isEmpty) return [];
    try {
      Query query = _gameResultsRef(uid);
      
      // Add date range filter if year and month specified
      if (year != null && month != null) {
        final start = DateTime(year, month, 1);
        final endYear = month == 12 ? year + 1 : year;
        final endMonth = month == 12 ? 1 : month + 1;
        final end = DateTime(endYear, endMonth, 1);
        
        query = query
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('timestamp', isLessThan: Timestamp.fromDate(end));
      }
      
      query = query.orderBy('timestamp', descending: true);
      
      if (limit != null) {
        query = query.limit(limit);
      }
      
      final snapshot = await query.get();
      return snapshot.docs
          .map((d) => GameResult.fromFirestore(d))
          .toList();
    } catch (e) {
      return []; // Graceful degradation
    }
  }

  /// Gets game results for a senior (for family health view)
  /// Returns results for cognitive index calculation, optionally filtered by month
  Future<List<GameResult>> getGameResultsForSenior(String seniorUid, {int? year, int? month}) async {
    return getGameResults(seniorUid, year: year, month: month);
  }
  
  // ===== Progressive Profile =====

  Future<void> updatePhoneNumber(String uid, String phoneNumber) async {
    await _profileRef(uid).update({
      'phoneNumber': phoneNumber,
    });
  }

  Future<void> updateEmergencyContact(
    String uid,
    EmergencyContact contact,
  ) async {
    await _seniorStateRef(uid).set(
      {'emergencyContact': contact.toMap()},
      SetOptions(merge: true),
    );
  }

  // ===== Security Vault Operations =====

  /// Gets the security vault for a user
  Future<SecurityVault?> getSecurityVault(String uid) async {
    final doc = await _securityVaultRef(uid).get();
    if (!doc.exists) return null;
    return SecurityVault.fromFirestore(doc);
  }

  /// Saves/updates the security vault for a user
  Future<void> saveSecurityVault(String uid, SecurityVault vault) async {
    await _securityVaultRef(uid).set(vault.toFirestore());
  }

  /// Gets the security vault for a connected senior (for family members)
  Future<SecurityVault?> getSecurityVaultForSenior(String seniorUid) async {
    return getSecurityVault(seniorUid);
  }

  /// Stream security vault for real-time updates in family view
  Stream<SecurityVault?> streamSecurityVault(String seniorUid) {
    if (seniorUid.isEmpty) return Stream.value(null);
    
    return _securityVaultRef(seniorUid)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          return SecurityVault.fromFirestore(snap);
        })
        .transform(
          StreamTransformer<SecurityVault?, SecurityVault?>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              // Log the error and emit null for graceful degradation
              sink.add(null);
            },
          ),
        );
  }

  // ===== Activity Log Operations =====

  /// Log an activity for a senior
  Future<void> logActivity(String seniorId, ActivityLog activity) async {
    await _activityLogsRef(seniorId).add(activity.toFirestore());
  }

  /// Stream recent activities for a senior (for family dashboard)
  Stream<List<ActivityLog>> streamActivities(String seniorId, {int limit = 20}) {
    if (seniorId.isEmpty) return Stream.value([]);
    return _activityLogsRef(seniorId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ActivityLog.fromFirestore(d)).toList());
  }

  /// Get activities for a specific date
  Future<List<ActivityLog>> getActivitiesForDate(String seniorId, DateTime date) async {
    if (seniorId.isEmpty) return [];
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final snap = await _activityLogsRef(seniorId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('timestamp', descending: true)
        .get();
    
    return snap.docs.map((d) => ActivityLog.fromFirestore(d)).toList();
  }

  /// Stream alerts only (missed check-ins) for family dashboard
  Stream<List<ActivityLog>> streamAlerts(String seniorId, {int limit = 20}) {
    if (seniorId.isEmpty) return Stream.value([]);
    return _activityLogsRef(seniorId)
        .where('isAlert', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ActivityLog.fromFirestore(d)).toList());
  }

  /// Get activities for multiple seniors (for family dashboard overview)
  /// Uses Future.wait for parallel fetches instead of sequential N+1 queries
  Future<List<ActivityLog>> getActivitiesForSeniors(
    List<String> seniorIds, {
    int limitPerSenior = 10,
  }) async {
    if (seniorIds.isEmpty) return [];
    
    // Parallel fetch with error handling - failed fetches return empty list
    final futures = seniorIds.map((seniorId) async {
      try {
        final snap = await _activityLogsRef(seniorId)
            .orderBy('timestamp', descending: true)
            .limit(limitPerSenior)
            .get();
        return snap.docs
            .map((d) => ActivityLog.tryFromFirestore(d))
            .whereType<ActivityLog>()
            .toList();
      } catch (e) {
        return <ActivityLog>[]; // Graceful degradation for individual senior
      }
    });
    
    final results = await Future.wait(futures);
    
    // Flatten and sort combined results by timestamp
    final allActivities = results.expand((list) => list).toList();
    allActivities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return allActivities;
  }

  /// Get alerts for multiple seniors (for family dashboard alerts tab)
  /// Uses Future.wait for parallel fetches instead of sequential N+1 queries
  Future<List<ActivityLog>> getAlertsForSeniors(
    List<String> seniorIds, {
    int limitPerSenior = 10,
  }) async {
    if (seniorIds.isEmpty) return [];
    
    // Parallel fetch with error handling - failed fetches return empty list
    final futures = seniorIds.map((seniorId) async {
      try {
        final snap = await _activityLogsRef(seniorId)
            .where('isAlert', isEqualTo: true)
            .orderBy('timestamp', descending: true)
            .limit(limitPerSenior)
            .get();
        return snap.docs
            .map((d) => ActivityLog.tryFromFirestore(d))
            .whereType<ActivityLog>()
            .toList();
      } catch (e) {
        return <ActivityLog>[]; // Graceful degradation for individual senior
      }
    });
    
    final results = await Future.wait(futures);
    
    // Flatten and sort combined results by timestamp
    final allAlerts = results.expand((list) => list).toList();
    allAlerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return allAlerts;
  }

  // ===== Connections (Top-level, UIDs only) =====

  Future<void> createConnection(Connection connection) async {
    await _connectionsRef.doc(connection.id).set(connection.toFirestore());
  }

  Stream<List<Connection>> getConnectionsForSenior(String seniorId) {
    return _connectionsRef
        .where('seniorId', isEqualTo: seniorId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Connection.fromFirestore(doc)).toList());
  }

  Stream<List<Connection>> getConnectionsForFamily(String familyId) {
    return _connectionsRef
        .where('familyId', isEqualTo: familyId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Connection.fromFirestore(doc)).toList());
  }

  Future<void> updateConnectionStatus(String connectionId, String status) async {
    await _connectionsRef.doc(connectionId).update({'status': status});
  }

  /// Fetch multiple profiles by UID (for displaying connection names)
  /// Uses whereIn for batch fetching instead of individual document reads
  Future<Map<String, UserProfile>> getProfilesByUids(List<String> uids) async {
    if (uids.isEmpty) return {};

    final profiles = <String, UserProfile>{};

    // Firestore 'whereIn' queries limited to 30 items
    for (var i = 0; i < uids.length; i += AppConstants.firestoreWhereInLimit) {
      final batch = uids.skip(i).take(AppConstants.firestoreWhereInLimit).toList();
      
      try {
        // Single query to fetch all profiles in batch
        final snapshot = await _db.collection('users')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        
        // For each user document, fetch the profile subcollection
        for (final userDoc in snapshot.docs) {
          try {
            final profileDoc = await _profileRef(userDoc.id).get();
            if (profileDoc.exists) {
              profiles[userDoc.id] = UserProfile.fromFirestore(profileDoc);
            }
          } catch (e) {
            // Skip profiles that fail to parse
          }
        }
      } catch (e) {
        // Fallback to individual fetches if batch query fails
        final futures = batch.map((uid) => getUserProfile(uid));
        final results = await Future.wait(futures);
        for (var j = 0; j < batch.length; j++) {
          if (results[j] != null) {
            profiles[batch[j]] = results[j]!;
          }
        }
      }
    }

    return profiles;
  }

  // ===== Requests (Subcollection) =====

  Future<void> createRequest(String uid, ConnectionRequest request) async {
    await _requestsRef(uid).doc(request.id).set(request.toFirestore());
  }

  Stream<List<ConnectionRequest>> getPendingRequests(String uid) {
    return _requestsRef(uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ConnectionRequest.fromFirestore(doc))
            .toList());
  }

  Future<void> updateRequestStatus(
    String uid,
    String requestId,
    String status,
  ) async {
    await _requestsRef(uid).doc(requestId).update({'status': status});
  }

  // ===== Transaction-based operations =====

  Future<void> createUserWithRoles(
    String uid,
    UserProfile profile,
    UserRoles roles,
  ) async {
    await _db.runTransaction((transaction) async {
      transaction.set(_profileRef(uid), profile.toFirestore());
      transaction.set(_rolesRef(uid), roles.toFirestore());
    });
  }

  // ===== Deletion Operations =====

  Future<void> deleteFamilyConnection(String currentUid, String contactUid) async {
    // 1. Define possible connection IDs
    final possibleId1 = '${currentUid}_$contactUid';
    final possibleId2 = '${contactUid}_$currentUid';

    // 2. Run transaction for both read and delete operations
    // IMPORTANT: Firestore requires ALL reads before ANY writes
    await _db.runTransaction((transaction) async {
      // --- PHASE 1: ALL READS ---
      final docRef1 = _connectionsRef.doc(possibleId1);
      final docRef2 = _connectionsRef.doc(possibleId2);
      
      final currentUserContactRef = _db
          .collection('users')
          .doc(currentUid)
          .collection('familyContacts')
          .doc(contactUid);
      final otherUserContactRef = _db
          .collection('users')
          .doc(contactUid)
          .collection('familyContacts')
          .doc(currentUid);

      // Perform all reads upfront
      final docSnapshot1 = await transaction.get(docRef1);
      final docSnapshot2 = await transaction.get(docRef2);
      final currentContactDoc = await transaction.get(currentUserContactRef);
      final otherContactDoc = await transaction.get(otherUserContactRef);

      // --- PHASE 2: ALL WRITES ---
      // Delete connection document if found
      if (docSnapshot1.exists) {
        transaction.delete(docRef1);
      } else if (docSnapshot2.exists) {
        transaction.delete(docRef2);
      }

      // Delete contact entries if they exist
      if (currentContactDoc.exists) {
        transaction.delete(currentUserContactRef);
      }
      if (otherContactDoc.exists) {
        transaction.delete(otherUserContactRef);
      }
    });
  }

  // ===== Atomic Connection Creation =====

  /// Creates a family connection atomically using WriteBatch.
  /// This ensures all operations succeed or fail together:
  /// 1. Create the connection document
  /// 2. Add contact to current user's familyContacts
  /// 3. Add contact to invited user's familyContacts (bidirectional)
  /// 
  /// Uses contactUid for live profile lookups instead of denormalized names.
  /// Creates a family connection atomically using a transaction for idempotency.
  /// This ensures:
  /// 1. If connection already exists, the operation is skipped (idempotent)
  /// 2. All operations succeed or fail together
  /// 3. Network failures after commit are handled gracefully
  Future<void> createFamilyConnectionAtomic({
    required String currentUserId,
    required String invitedUserId,
    required String currentUserName,
    required String invitedUserName,
    required String currentUserPhone,
    required String invitedUserPhone,
    required String invitedUserRole, // 'Senior' or 'Family'
  }) async {
    // Determine senior vs family based on role
    final String seniorId;
    final String familyId;
    if (invitedUserRole == 'Senior') {
      seniorId = invitedUserId;
      familyId = currentUserId;
    } else {
      seniorId = currentUserId;
      familyId = invitedUserId;
    }
    
    final connectionId = '${seniorId}_$familyId';
    
    // Use a transaction for idempotency check + atomic writes
    await _db.runTransaction((transaction) async {
      // Idempotency check: if connection already exists, skip
      final existingConnection = await transaction.get(_connectionsRef.doc(connectionId));
      if (existingConnection.exists) {
        return; // Already connected, nothing to do
      }
      // 1. Create connection document
      final seniorName = invitedUserRole == 'Senior' ? invitedUserName : currentUserName;
      transaction.set(_connectionsRef.doc(connectionId), {
        'id': connectionId,
        'seniorId': seniorId,
        'familyId': familyId,
        'seniorName': seniorName, // Store name for dashboard fallback
        'status': 'active',
        'createdAt': Timestamp.now(),
      });

      // 2. Add invited user to current user's contacts
      final currentUserContactRef = _db
          .collection('users')
          .doc(currentUserId)
          .collection('familyContacts')
          .doc(invitedUserId);
      transaction.set(currentUserContactRef, {
        'name': invitedUserName,
        'phone': invitedUserPhone,
        'relationship': invitedUserRole,
        'addedAt': Timestamp.now(),
        'contactUid': invitedUserId,
      });

      // 3. Add current user to invited user's contacts (bidirectional)
      final invitedUserContactRef = _db
          .collection('users')
          .doc(invitedUserId)
          .collection('familyContacts')
          .doc(currentUserId);
      transaction.set(invitedUserContactRef, {
        'name': currentUserName,
        'phone': currentUserPhone,
        'relationship': invitedUserRole == 'Senior' ? 'Family' : 'Senior',
        'addedAt': Timestamp.now(),
        'contactUid': currentUserId,
      });
    });
  }

  // ===== Custom Questions Operations =====

  /// Maximum number of custom questions allowed per user
  static const int maxCustomQuestions = 5;

  /// Saves a new custom question
  Future<String> saveCustomQuestion(String uid, CustomQuestion question) async {
    // Check limit before adding
    final existing = await getCustomQuestions(uid);
    if (existing.length >= maxCustomQuestions) {
      throw Exception('Maximum of $maxCustomQuestions custom questions allowed');
    }
    
    final docRef = await _customQuestionsRef(uid).add(question.toFirestore());
    return docRef.id;
  }

  /// Gets all custom questions for a user (regardless of enabled state)
  Future<List<CustomQuestion>> getCustomQuestions(String uid) async {
    if (uid.isEmpty) return [];
    try {
      final snapshot = await _customQuestionsRef(uid).get();
      final result = snapshot.docs
          .map((doc) => CustomQuestion.fromFirestore(doc))
          .toList();
      // Sort client-side to avoid index requirement
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return result;
    } catch (e) {
      return []; // Graceful degradation
    }
  }

  /// Gets only enabled custom questions for use in check-in flow
  Future<List<CustomQuestion>> getEnabledCustomQuestions(String uid) async {
    if (uid.isEmpty) return [];
    try {
      // Fetch all and filter client-side to avoid composite index requirement
      final snapshot = await _customQuestionsRef(uid).get();
      final result = snapshot.docs
          .map((doc) => CustomQuestion.fromFirestore(doc))
          .where((q) => q.isEnabled)
          .toList();
      // Sort client-side
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return result;
    } catch (e) {
      return []; // Graceful degradation
    }
  }

  /// Streams custom questions for real-time updates
  Stream<List<CustomQuestion>> streamCustomQuestions(String uid) {
    if (uid.isEmpty) return Stream.value([]);
    
    return _customQuestionsRef(uid)
        .snapshots()
        .map((snapshot) {
          final questions = snapshot.docs
              .map((doc) => CustomQuestion.fromFirestore(doc))
              .toList();
          // Sort client-side to avoid index requirement
          questions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return questions;
        })
        .handleError((_) => <CustomQuestion>[]);
  }

  /// Updates an existing custom question
  Future<void> updateCustomQuestion(String uid, CustomQuestion question) async {
    await _customQuestionsRef(uid).doc(question.id).update({
      ...question.toFirestore(),
      'updatedAt': Timestamp.now(),
    });
  }

  /// Deletes a custom question
  Future<void> deleteCustomQuestion(String uid, String questionId) async {
    await _customQuestionsRef(uid).doc(questionId).delete();
  }

  /// Toggles the enabled state of a custom question
  Future<void> toggleCustomQuestion(String uid, String questionId, bool enabled) async {
    await _customQuestionsRef(uid).doc(questionId).update({
      'isEnabled': enabled,
      'updatedAt': Timestamp.now(),
    });
  }
}

