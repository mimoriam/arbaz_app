import 'package:arbaz_app/models/checkin_model.dart';

class WellnessDataPoint {
  final DateTime date;
  final double? mood;      // 1-5 scale or normalized 0-1 (The prompt mentions 1-5 in comments but 0-1 in logic description. I'll stick to what is practical. If the inputs are "Happy", "Neutral", etc. I will convert them.)
  final double? sleep;     // 1-5
  final double? energy;    // 1-5
  final bool medicationTaken;


  WellnessDataPoint({
    required this.date,
    this.mood,
    this.sleep,
    this.energy,
    required this.medicationTaken,
  });

  factory WellnessDataPoint.fromCheckIn(CheckInRecord record) {
    return WellnessDataPoint(
      date: record.timestamp,
      mood: _normalizeMood(record.mood),
      sleep: _normalizeSleep(record.sleep),
      energy: _normalizeEnergy(record.energy),
      medicationTaken: _normalizeMedicationTaken(record.medication),
    );
  }

  static bool _normalizeMedicationTaken(String? medication) {
    if (medication == null) return false;
    final normalized = medication.trim().toLowerCase();
    // Check for common truthy values
    return normalized == 'yes' || normalized == 'true' || normalized == '1';
  }

  static double? _normalizeMood(String? mood) {
    if (mood == null) return null;
    switch (mood.toLowerCase()) {
      case 'happy': return 1.0;
      case 'neutral': return 0.7;
      case 'down': return 0.4;
      case 'very_sad': return 0.1;
      // Legacy values for backward compatibility
      case 'sad': return 0.4;
      default: return 0.5;
    }
  }

  static double? _normalizeSleep(String? sleep) {
    if (sleep == null) return null;
    switch (sleep.toLowerCase()) {
      case 'great': return 1.0;
      case 'good': return 0.8;
      case 'okay': return 0.5;
      case 'poorly': return 0.2;
      // Legacy values for backward compatibility
      case 'average': return 0.5;
      case 'poor': return 0.2;
      default: return 0.5;
    }
  }

  static double? _normalizeEnergy(String? energy) {
    if (energy == null) return null;
    switch (energy.toLowerCase()) {
      case 'great': return 1.0;
      case 'good': return 0.8;
      case 'high': return 1.0; // Legacy
      case 'medium': return 0.6; // Legacy
      case 'low': return 0.4;
      case 'very_tired': return 0.1;
      default: return 0.5;
    }
  }

  // Logic from prompt:
  // wellnessIndex = (mood + sleep + energy) / 3
  // Each value normalized to 0-1 scale.

  double get wellnessIndex {
    int count = 0;
    double sum = 0.0;
    
    if (mood != null) { sum += mood!; count++; }
    if (sleep != null) { sum += sleep!; count++; }
    if (energy != null) { sum += energy!; count++; }
    
    if (count == 0) return 0.0;
    return sum / count;
  }
}

enum SeniorCheckInStatus {
  safe,
  pending,
  alert
}

class SeniorStatusData {
  final SeniorCheckInStatus status;
  final String seniorName;
  final DateTime? lastCheckIn;
  final String? timeString; // Formatted time string, e.g. "22:13"
  final bool vacationMode;
  final bool sosActive; // True when SOS alert is active

  SeniorStatusData({
    required this.status,
    required this.seniorName,
    this.lastCheckIn,
    this.timeString,
    this.vacationMode = false,
    this.sosActive = false,
  });
}

/// Basic info about a connected senior for dropdown selection
class SeniorInfo {
  final String id;
  final String name;

  SeniorInfo({required this.id, required this.name});
}
