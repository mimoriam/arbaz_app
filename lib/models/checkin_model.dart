import 'package:cloud_firestore/cloud_firestore.dart';

class CheckInRecord {
  final String id;
  final String userId;
  final DateTime timestamp;
  
  // Health & Mood
  final String? mood;
  final String? sleep;
  final String? energy;
  final String? medication;
  final bool brainExerciseCompleted;

  // Location Data
  final double? latitude;
  final double? longitude;
  final String? locationAddress;

  // Schedule tracking for success rate calculation
  /// Number of check-ins scheduled for the day when this check-in was recorded.
  /// Used for calculating accurate success rate (check-ins / scheduled).
  /// Defaults to 1 for backward compatibility.
  final int scheduledCount;

  CheckInRecord({
    required this.id,
    required this.userId,
    required this.timestamp,
    this.mood,
    this.sleep,
    this.energy,
    this.medication,
    this.brainExerciseCompleted = false,
    this.latitude,
    this.longitude,
    this.locationAddress,
    this.scheduledCount = 1,
  });

  factory CheckInRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('Document ${doc.id} has no data');
    }
    
    final userId = data['userId'] as String?;
    if (userId == null || userId.isEmpty) {
      throw StateError('Document ${doc.id} is missing required userId');
    }
    
    final timestampData = data['timestamp'] as Timestamp?;
    if (timestampData == null) {
      throw StateError('Document ${doc.id} is missing required timestamp');
    }
    
    return CheckInRecord(
      id: doc.id,
      userId: userId,
      timestamp: timestampData.toDate(),
      mood: data['mood'],
      sleep: data['sleep'],
      energy: data['energy'],
      medication: data['medication'],
      brainExerciseCompleted: data['brainExerciseCompleted'] ?? false,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      locationAddress: data['locationAddress'],
      scheduledCount: (data['scheduledCount'] as int?) ?? 1,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'timestamp': Timestamp.fromDate(timestamp),
      'mood': mood,
      'sleep': sleep,
      'energy': energy,
      'medication': medication,
      'brainExerciseCompleted': brainExerciseCompleted,
      'latitude': latitude,
      'longitude': longitude,
      'locationAddress': locationAddress,
      'scheduledCount': scheduledCount,
    };
  }

  /// Creates a copy with updated values
  CheckInRecord copyWith({
    String? id,
    String? userId,
    DateTime? timestamp,
    String? mood,
    String? sleep,
    String? energy,
    String? medication,
    bool? brainExerciseCompleted,
    double? latitude,
    double? longitude,
    String? locationAddress,
    int? scheduledCount,
  }) {
    return CheckInRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      timestamp: timestamp ?? this.timestamp,
      mood: mood ?? this.mood,
      sleep: sleep ?? this.sleep,
      energy: energy ?? this.energy,
      medication: medication ?? this.medication,
      brainExerciseCompleted: brainExerciseCompleted ?? this.brainExerciseCompleted,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAddress: locationAddress ?? this.locationAddress,
      scheduledCount: scheduledCount ?? this.scheduledCount,
    );
  }
}
