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
    };
  }
}
