import 'package:arbaz_app/services/firestore_service.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class CheckInScheduleService {
  final FirestoreService _firestoreService;

  CheckInScheduleService(this._firestoreService);

  /// Normalizes time string to consistent format (uppercase, trimmed)
  String _normalizeTime(String time) {
    return time.trim().toUpperCase();
  }

  /// Gets the current check-in schedules for a user
  Future<List<String>> getSchedules(String uid) async {
    final seniorState = await _firestoreService.getSeniorState(uid);
    if (seniorState != null && seniorState.checkInSchedules.isNotEmpty) {
      // Normalize all stored schedules
      return seniorState.checkInSchedules.map(_normalizeTime).toList();
    }
    
    // Default schedule if none exists
    const defaultSchedules = ['11:00 AM'];
    try {
      // Persist the default schedule so UI and DB are consistent
      await _firestoreService.atomicAddSchedule(uid, defaultSchedules.first);
    } catch (e) {
      // Log error but still return the default for UI
      debugPrint('Error persisting default schedules: $e');
    }
    return defaultSchedules;
  }

  /// Adds a new time to the schedule using atomic Firestore operation
  Future<void> addSchedule(String uid, String time) async {
    final normalizedTime = _normalizeTime(time);
    
    // Use atomic arrayUnion to prevent race conditions
    await _firestoreService.atomicAddSchedule(uid, normalizedTime);
  }

  /// Converts "h:mm a" time string to minutes since midnight
  int? _timeToMinutes(String time) {
    try {
      final format = DateFormat('h:mm a');
      final dateTime = format.parse(time.toUpperCase());
      return dateTime.hour * 60 + dateTime.minute;
    } catch (e) {
      debugPrint('Failed to parse time "$time": $e');
      return null;
    }
  }

  /// Removes a time from the schedule using atomic Firestore operation
  Future<void> removeSchedule(String uid, String time) async {
    final normalizedTime = _normalizeTime(time);
    
    // Use atomic arrayRemove to prevent race conditions
    await _firestoreService.atomicRemoveSchedule(uid, normalizedTime);
  }

  /// Sorts schedules by time (for display purposes only).
  /// Parses each time once, then sorts by the parsed value for efficiency.
  List<String> sortSchedules(List<String> schedules) {
    // Parse all times once upfront for O(n) parsing vs O(n log n) in sort
    final parsed = schedules.map((s) => 
      MapEntry(s, _timeToMinutes(s))
    ).toList();
    
    parsed.sort((a, b) {
      // Handle null cases (unparsable times go to end)
      if (a.value == null && b.value == null) return 0;
      if (a.value == null) return 1;
      if (b.value == null) return -1;
      return a.value!.compareTo(b.value!);
    });
    
    return parsed.map((e) => e.key).toList();
  }
}
