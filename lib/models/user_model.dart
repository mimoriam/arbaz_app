import 'package:cloud_firestore/cloud_firestore.dart';

/// Helper to safely parse a DateTime from Firestore
DateTime _parseDateTime(dynamic value, {DateTime? fallback}) {
  if (value is Timestamp) {
    return value.toDate();
  } else if (value is DateTime) {
    return value;
  }
  return fallback ?? DateTime.now();
}

/// Helper to safely parse latitude within [-90, 90]
double? _parseLatitude(dynamic value) {
  if (value is! num) return null;
  final lat = value.toDouble();
  if (lat < -90 || lat > 90) return null;
  return lat;
}

/// Helper to safely parse longitude within [-180, 180]
double? _parseLongitude(dynamic value) {
  if (value is! num) return null;
  final lng = value.toDouble();
  if (lng < -180 || lng > 180) return null;
  return lng;
}

/// Core user profile stored in users/{uid}/profile
class UserProfile {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? phoneNumber;
  final DateTime createdAt;
  final DateTime lastLoginAt;

  // Location Data
  final String? locationAddress;
  final double? latitude;
  final double? longitude;

  UserProfile({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.phoneNumber,
    required this.createdAt,
    required this.lastLoginAt,
    this.locationAddress,
    this.latitude,
    this.longitude,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    if (rawData == null || rawData is! Map<String, dynamic>) {
      throw FormatException('Invalid UserProfile document: ${doc.id}');
    }
    final data = rawData;

    // Email is required
    final email = data['email'];
    if (email == null || email is! String) {
      throw FormatException(
        'Missing or invalid email in UserProfile: ${doc.id}',
      );
    }

    return UserProfile(
      uid: doc.id,
      email: email,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      createdAt: _parseDateTime(data['createdAt']),
      lastLoginAt: _parseDateTime(data['lastLoginAt']),
      locationAddress: data['locationAddress'] as String?,
      latitude: _parseLatitude(data['latitude']),
      longitude: _parseLongitude(data['longitude']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'phoneNumber': phoneNumber,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
      'locationAddress': locationAddress,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  UserProfile copyWith({
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    DateTime? lastLoginAt,
    String? locationAddress,
    double? latitude,
    double? longitude,
  }) {
    return UserProfile(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      locationAddress: locationAddress ?? this.locationAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}

/// User roles stored in users/{uid}/roles
class UserRoles {
  final bool isSenior;
  final bool isFamilyMember;
  final String? activeRole; // The persisted active role: 'senior' or 'family'
  final bool hasConfirmedSeniorRole; // True if user explicitly opted into senior features

  UserRoles({
    this.isSenior = false, 
    this.isFamilyMember = false,
    this.activeRole,
    this.hasConfirmedSeniorRole = false,
  });

  /// Derived from flags - not stored, prevents invalid states
  String get currentRole {
    if (isSenior && isFamilyMember) return 'both';
    if (isSenior) return 'senior';
    if (isFamilyMember) return 'family';
    return 'unassigned';
  }

  factory UserRoles.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    if (rawData == null || rawData is! Map<String, dynamic>) {
      return UserRoles();
    }
    final data = rawData;
    return UserRoles(
      isSenior: data['isSenior'] == true,
      isFamilyMember: data['isFamilyMember'] == true,
      activeRole: data['currentRole'] as String?,
      hasConfirmedSeniorRole: data['hasConfirmedSeniorRole'] == true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'isSenior': isSenior, 
      'isFamilyMember': isFamilyMember,
      'currentRole': activeRole,
      'hasConfirmedSeniorRole': hasConfirmedSeniorRole,
    };
  }

  UserRoles copyWith({
    bool? isSenior, 
    bool? isFamilyMember,
    String? activeRole,
    bool? hasConfirmedSeniorRole,
  }) {
    return UserRoles(
      isSenior: isSenior ?? this.isSenior,
      isFamilyMember: isFamilyMember ?? this.isFamilyMember,
      activeRole: activeRole ?? this.activeRole,
      hasConfirmedSeniorRole: hasConfirmedSeniorRole ?? this.hasConfirmedSeniorRole,
    );
  }
}


/// Volatile senior state stored in users/{uid}/seniorState
class SeniorState {
  final DateTime? lastCheckIn;
  final bool vacationMode;
  final EmergencyContact? emergencyContact;
  final List<String> checkInSchedules;
  final bool brainGamesEnabled;
  final bool healthQuizEnabled;
  final bool escalationAlarmActive;
  final int currentStreak;
  final DateTime? startDate; // The date when user started using the app

  SeniorState({
    this.lastCheckIn,
    this.vacationMode = false,
    this.emergencyContact,
    this.checkInSchedules = const ['11:00 AM'],
    this.brainGamesEnabled = false,
    this.healthQuizEnabled = true,
    this.escalationAlarmActive = false,
    this.currentStreak = 0,
    this.startDate,
  });

  factory SeniorState.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    if (rawData == null || rawData is! Map<String, dynamic>) {
      return SeniorState();
    }
    final data = rawData;

    // Parse emergencyContact safely
    EmergencyContact? emergencyContact;
    final ecData = data['emergencyContact'];
    if (ecData is Map<String, dynamic>) {
      emergencyContact = EmergencyContact.fromMap(ecData);
    }

    // Parse checkInSchedules safely
    List<String> schedules = ['11:00 AM'];
    if (data['checkInSchedules'] is List) {
      final list = data['checkInSchedules'] as List;
      schedules = list
          .where((item) => item != null)
          .map((item) => item.toString())
          .toList();
    }

    return SeniorState(
      lastCheckIn: data['lastCheckIn'] is Timestamp
          ? (data['lastCheckIn'] as Timestamp).toDate()
          : null,
      vacationMode: data['vacationMode'] == true,
      emergencyContact: emergencyContact,
      checkInSchedules: schedules,
      brainGamesEnabled: data['brainGamesEnabled'] == true,
      healthQuizEnabled: data['healthQuizEnabled'] != false, // Default true
      escalationAlarmActive: data['escalationAlarmActive'] == true,
      currentStreak: (data['currentStreak'] as num?)?.toInt() ?? 0,
      startDate: data['startDate'] is Timestamp
          ? (data['startDate'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'lastCheckIn': lastCheckIn != null
          ? Timestamp.fromDate(lastCheckIn!)
          : null,
      'vacationMode': vacationMode,
      'emergencyContact': emergencyContact?.toMap(),
      'checkInSchedules': checkInSchedules,
      'brainGamesEnabled': brainGamesEnabled,
      'healthQuizEnabled': healthQuizEnabled,
      'escalationAlarmActive': escalationAlarmActive,
      'currentStreak': currentStreak,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
    };
  }

  SeniorState copyWith({
    DateTime? lastCheckIn,
    bool? vacationMode,
    EmergencyContact? emergencyContact,
    List<String>? checkInSchedules,
    bool? brainGamesEnabled,
    bool? healthQuizEnabled,
    bool? escalationAlarmActive,
    int? currentStreak,
    DateTime? startDate,
  }) {
    return SeniorState(
      lastCheckIn: lastCheckIn ?? this.lastCheckIn,
      vacationMode: vacationMode ?? this.vacationMode,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      checkInSchedules: checkInSchedules ?? this.checkInSchedules,
      brainGamesEnabled: brainGamesEnabled ?? this.brainGamesEnabled,
      healthQuizEnabled: healthQuizEnabled ?? this.healthQuizEnabled,
      escalationAlarmActive:
          escalationAlarmActive ?? this.escalationAlarmActive,
      currentStreak: currentStreak ?? this.currentStreak,
      startDate: startDate ?? this.startDate,
    );
  }
}

/// Volatile family state stored in users/{uid}/familyState
class FamilyState {
  final String? defaultRelationship;

  FamilyState({this.defaultRelationship});

  factory FamilyState.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    if (rawData == null || rawData is! Map<String, dynamic>) {
      return FamilyState();
    }
    final data = rawData;
    return FamilyState(
      defaultRelationship: data['defaultRelationship'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {'defaultRelationship': defaultRelationship};
  }
}

/// Emergency contact embedded in SeniorState
class EmergencyContact {
  final String name;
  final String phoneNumber;
  final String relationship;

  EmergencyContact({
    required this.name,
    required this.phoneNumber,
    required this.relationship,
  });

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    // Validate required fields
    final name = map['name'];
    if (name == null || name is! String || name.trim().isEmpty) {
      throw const FormatException(
        'EmergencyContact: "name" field is required and must be a non-empty string',
      );
    }

    final phoneNumber = map['phoneNumber'];
    if (phoneNumber == null ||
        phoneNumber is! String ||
        phoneNumber.trim().isEmpty) {
      throw const FormatException(
        'EmergencyContact: "phoneNumber" field is required and must be a non-empty string',
      );
    }

    final relationship = map['relationship'];
    if (relationship == null ||
        relationship is! String ||
        relationship.trim().isEmpty) {
      throw const FormatException(
        'EmergencyContact: "relationship" field is required and must be a non-empty string',
      );
    }

    return EmergencyContact(
      name: name.trim(),
      phoneNumber: phoneNumber.trim(),
      relationship: relationship.trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'relationship': relationship,
    };
  }
}
