import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for tracking senior activities
/// Stored in: users/{seniorId}/activityLogs/{logId}
///
/// Activity types:
/// - 'check_in': Senior completed a check-in
/// - 'brain_game': Senior completed a brain game
/// - 'missed_check_in': Senior missed a scheduled check-in (alert)
class ActivityLog {
  final String id;
  final String seniorId;
  final String activityType;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final bool isAlert;

  const ActivityLog({
    required this.id,
    required this.seniorId,
    required this.activityType,
    required this.timestamp,
    this.metadata,
    this.isAlert = false,
  });

  /// Create from Firestore document
  /// Throws [StateError] if required fields (seniorId, activityType, timestamp) are missing or invalid
  factory ActivityLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('ActivityLog document ${doc.id} has no data');
    }

    // Validate required fields - throw descriptive errors instead of using fallbacks
    final seniorId = data['seniorId'];
    if (seniorId is! String || seniorId.isEmpty) {
      throw StateError('ActivityLog ${doc.id}: seniorId is missing or invalid');
    }
    
    final activityType = data['activityType'];
    if (activityType is! String || activityType.isEmpty) {
      throw StateError('ActivityLog ${doc.id}: activityType is missing or invalid');
    }
    
    final timestamp = data['timestamp'];
    if (timestamp is! Timestamp) {
      throw StateError('ActivityLog ${doc.id}: timestamp is missing or not a Timestamp');
    }

    return ActivityLog(
      id: doc.id,
      seniorId: seniorId,
      activityType: activityType,
      timestamp: timestamp.toDate(),
      metadata: data['metadata'] as Map<String, dynamic>?,
      isAlert: data['isAlert'] as bool? ?? false,
    );
  }

  /// Safe version of fromFirestore that returns null instead of throwing on invalid data
  /// Use this when parsing lists where individual failures should not crash the entire operation
  static ActivityLog? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return ActivityLog.fromFirestore(doc);
    } catch (e) {
      // Return null for malformed documents, allowing callers to filter with whereType
      return null;
    }
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'seniorId': seniorId,
      'activityType': activityType,
      'timestamp': Timestamp.fromDate(timestamp),
      'metadata': metadata,
      'isAlert': isAlert,
    };
  }

  /// Create a check-in activity log
  factory ActivityLog.checkIn({
    required String seniorId,
    required DateTime timestamp,
    String? mood,
    String? sleep,
    String? energy,
    bool? brainExerciseCompleted,
  }) {
    return ActivityLog(
      id: '', // Will be assigned by Firestore
      seniorId: seniorId,
      activityType: 'check_in',
      timestamp: timestamp,
      isAlert: false,
      metadata: {
        if (mood != null) 'mood': mood,
        if (sleep != null) 'sleep': sleep,
        if (energy != null) 'energy': energy,
        if (brainExerciseCompleted != null)
          'brainExerciseCompleted': brainExerciseCompleted,
      },
    );
  }

  /// Create a brain game activity log
  factory ActivityLog.brainGame({
    required String seniorId,
    required DateTime timestamp,
    required String gameType,
    int? score,
    int? timeTakenMs,
    String? difficulty,
  }) {
    return ActivityLog(
      id: '', // Will be assigned by Firestore
      seniorId: seniorId,
      activityType: 'brain_game',
      timestamp: timestamp,
      isAlert: false,
      metadata: {
        'gameType': gameType,
        if (score != null) 'score': score,
        if (timeTakenMs != null) 'timeTakenMs': timeTakenMs,
        if (difficulty != null) 'difficulty': difficulty,
      },
    );
  }

  /// Create a missed check-in activity log (created by Cloud Function)
  factory ActivityLog.missedCheckIn({
    required String seniorId,
    required DateTime timestamp,
    required String scheduledTime,
  }) {
    return ActivityLog(
      id: '', // Will be assigned by Firestore
      seniorId: seniorId,
      activityType: 'missed_check_in',
      timestamp: timestamp,
      isAlert: true,
      metadata: {
        'scheduledTime': scheduledTime,
      },
    );
  }

  /// Get a human-readable description of the activity
  String get actionDescription {
    switch (activityType) {
      case 'check_in':
        return 'Checked in';
      case 'brain_game':
        final gameType = metadata?['gameType'] as String? ?? 'game';
        return 'Completed $gameType';
      case 'missed_check_in':
        final scheduledTime = metadata?['scheduledTime'] as String? ?? '';
        return 'Missed check-in${scheduledTime.isNotEmpty ? ' ($scheduledTime)' : ''}';
      default:
        return 'Activity';
    }
  }

  /// Copy with new values
  ActivityLog copyWith({
    String? id,
    String? seniorId,
    String? activityType,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
    bool? isAlert,
  }) {
    return ActivityLog(
      id: id ?? this.id,
      seniorId: seniorId ?? this.seniorId,
      activityType: activityType ?? this.activityType,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
      isAlert: isAlert ?? this.isAlert,
    );
  }

  @override
  String toString() {
    return 'ActivityLog(id: $id, seniorId: $seniorId, type: $activityType, '
        'timestamp: $timestamp, isAlert: $isAlert)';
  }
}
