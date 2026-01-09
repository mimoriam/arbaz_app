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

  // Timezone for consistent time handling (e.g., 'Asia/Karachi')
  final String? timezone;

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
    this.timezone,
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
      timezone: data['timezone'] as String?,
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
      'timezone': timezone,
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
    String? timezone,
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
      timezone: timezone ?? this.timezone,
    );
  }
}

/// User roles stored in users/{uid}/roles
class UserRoles {
  final bool isSenior;
  final bool isFamilyMember;
  final bool isPro; // Pro subscription status
  final String? activeRole; // The persisted active role: 'senior' or 'family'
  final bool hasConfirmedSeniorRole; // True if user explicitly opted into senior features
  final String subscriptionPlan; // 'free', 'plus', or 'premium'

  UserRoles({
    this.isSenior = false, 
    this.isFamilyMember = false,
    this.isPro = false,
    this.activeRole,
    this.hasConfirmedSeniorRole = false,
    this.subscriptionPlan = 'free',
  });

  /// Derived from flags - not stored, prevents invalid states
  String get currentRole {
    if (isSenior && isFamilyMember) return 'both';
    if (isSenior) return 'senior';
    if (isFamilyMember) return 'family';
    return 'unassigned';
  }

  /// Get display name for subscription plan
  String get subscriptionPlanDisplayName {
    switch (subscriptionPlan) {
      case 'plus':
        return 'Plus Monthly';
      case 'premium':
        return 'Premium Monthly';
      default:
        return 'Free Plan';
    }
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
      isPro: data['isPro'] == true,
      activeRole: data['currentRole'] as String?,
      hasConfirmedSeniorRole: data['hasConfirmedSeniorRole'] == true,
      subscriptionPlan: (data['subscriptionPlan'] as String?) ?? 'free',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'isSenior': isSenior, 
      'isFamilyMember': isFamilyMember,
      'isPro': isPro,
      'currentRole': activeRole,
      'hasConfirmedSeniorRole': hasConfirmedSeniorRole,
      'subscriptionPlan': subscriptionPlan,
    };
  }

  UserRoles copyWith({
    bool? isSenior, 
    bool? isFamilyMember,
    bool? isPro,
    String? activeRole,
    bool? hasConfirmedSeniorRole,
    String? subscriptionPlan,
  }) {
    return UserRoles(
      isSenior: isSenior ?? this.isSenior,
      isFamilyMember: isFamilyMember ?? this.isFamilyMember,
      isPro: isPro ?? this.isPro,
      activeRole: activeRole ?? this.activeRole,
      hasConfirmedSeniorRole: hasConfirmedSeniorRole ?? this.hasConfirmedSeniorRole,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
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
  final DateTime? seniorCreatedAt; // When user first became a senior (for day 1 logic)
  final int missedCheckInsToday; // Count of missed check-ins today (reset daily)
  final DateTime? lastMissedCheckIn; // Timestamp of most recent missed check-in
  final DateTime? nextExpectedCheckIn; // For scalable Cloud Function queries
  
  // Multi check-in tracking
  /// List of schedule times completed today, e.g., ["9:00 AM", "11:00 AM"]
  final List<String> completedSchedulesToday;
  /// Date when completedSchedulesToday was last reset (for day boundary detection)
  final DateTime? lastScheduleResetDate;
  
  // Cloud Tasks fields
  final String? activeTaskId; // Cloud Tasks task name for pending check-in
  final int consecutiveMissedDays; // Counter for escalation (reset on check-in)
  final DateTime? lastEscalationNotificationAt; // Rate-limit escalation alerts
  
  // SOS Alert tracking
  final bool sosActive; // True when SOS alert is active
  final DateTime? sosTriggeredAt; // When SOS was triggered (for cooldown)
  final double? sosLocationLatitude; // Latitude when SOS was triggered
  final double? sosLocationLongitude; // Longitude when SOS was triggered
  final String? sosLocationAddress; // Geocoded address when SOS was triggered
  
  // Subscription limit tracking
  final int gamesPlayedToday; // Counter for daily game plays (Free plan limit)
  final DateTime? lastGamePlayResetDate; // For day boundary detection

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
    this.seniorCreatedAt,
    this.missedCheckInsToday = 0,
    this.lastMissedCheckIn,
    this.nextExpectedCheckIn,
    this.completedSchedulesToday = const [],
    this.lastScheduleResetDate,
    this.activeTaskId,
    this.consecutiveMissedDays = 0,
    this.lastEscalationNotificationAt,
    this.sosActive = false,
    this.sosTriggeredAt,
    this.sosLocationLatitude,
    this.sosLocationLongitude,
    this.sosLocationAddress,
    this.gamesPlayedToday = 0,
    this.lastGamePlayResetDate,
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

    // Parse completedSchedulesToday safely
    List<String> completedSchedules = [];
    if (data['completedSchedulesToday'] is List) {
      final list = data['completedSchedulesToday'] as List;
      completedSchedules = list
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
      seniorCreatedAt: data['seniorCreatedAt'] is Timestamp
          ? (data['seniorCreatedAt'] as Timestamp).toDate()
          : null,
      missedCheckInsToday: (data['missedCheckInsToday'] as num?)?.toInt() ?? 0,
      lastMissedCheckIn: data['lastMissedCheckIn'] is Timestamp
          ? (data['lastMissedCheckIn'] as Timestamp).toDate()
          : null,
      nextExpectedCheckIn: data['nextExpectedCheckIn'] is Timestamp
          ? (data['nextExpectedCheckIn'] as Timestamp).toDate()
          : null,
      completedSchedulesToday: completedSchedules,
      lastScheduleResetDate: data['lastScheduleResetDate'] is Timestamp
          ? (data['lastScheduleResetDate'] as Timestamp).toDate()
          : null,
      activeTaskId: data['activeTaskId'] as String?,
      consecutiveMissedDays: (data['consecutiveMissedDays'] as num?)?.toInt() ?? 0,
      lastEscalationNotificationAt: data['lastEscalationNotificationAt'] is Timestamp
          ? (data['lastEscalationNotificationAt'] as Timestamp).toDate()
          : null,
      sosActive: data['sosActive'] == true,
      sosTriggeredAt: data['sosTriggeredAt'] is Timestamp
          ? (data['sosTriggeredAt'] as Timestamp).toDate()
          : null,
      sosLocationLatitude: (data['sosLocationLatitude'] as num?)?.toDouble(),
      sosLocationLongitude: (data['sosLocationLongitude'] as num?)?.toDouble(),
      sosLocationAddress: data['sosLocationAddress'] as String?,
      gamesPlayedToday: (data['gamesPlayedToday'] as num?)?.toInt() ?? 0,
      lastGamePlayResetDate: data['lastGamePlayResetDate'] is Timestamp
          ? (data['lastGamePlayResetDate'] as Timestamp).toDate()
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
      'seniorCreatedAt': seniorCreatedAt != null ? Timestamp.fromDate(seniorCreatedAt!) : null,
      'missedCheckInsToday': missedCheckInsToday,
      'lastMissedCheckIn': lastMissedCheckIn != null ? Timestamp.fromDate(lastMissedCheckIn!) : null,
      'nextExpectedCheckIn': nextExpectedCheckIn != null ? Timestamp.fromDate(nextExpectedCheckIn!) : null,
      'completedSchedulesToday': completedSchedulesToday,
      'lastScheduleResetDate': lastScheduleResetDate != null ? Timestamp.fromDate(lastScheduleResetDate!) : null,
      'activeTaskId': activeTaskId,
      'consecutiveMissedDays': consecutiveMissedDays,
      'lastEscalationNotificationAt': lastEscalationNotificationAt != null ? Timestamp.fromDate(lastEscalationNotificationAt!) : null,
      'sosActive': sosActive,
      'sosTriggeredAt': sosTriggeredAt != null ? Timestamp.fromDate(sosTriggeredAt!) : null,
      'sosLocationLatitude': sosLocationLatitude,
      'sosLocationLongitude': sosLocationLongitude,
      'sosLocationAddress': sosLocationAddress,
      'gamesPlayedToday': gamesPlayedToday,
      'lastGamePlayResetDate': lastGamePlayResetDate != null ? Timestamp.fromDate(lastGamePlayResetDate!) : null,
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
    DateTime? seniorCreatedAt,
    int? missedCheckInsToday,
    DateTime? lastMissedCheckIn,
    DateTime? nextExpectedCheckIn,
    List<String>? completedSchedulesToday,
    DateTime? lastScheduleResetDate,
    String? activeTaskId,
    int? consecutiveMissedDays,
    DateTime? lastEscalationNotificationAt,
    bool? sosActive,
    DateTime? sosTriggeredAt,
    double? sosLocationLatitude,
    double? sosLocationLongitude,
    String? sosLocationAddress,
    int? gamesPlayedToday,
    DateTime? lastGamePlayResetDate,
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
      seniorCreatedAt: seniorCreatedAt ?? this.seniorCreatedAt,
      missedCheckInsToday: missedCheckInsToday ?? this.missedCheckInsToday,
      lastMissedCheckIn: lastMissedCheckIn ?? this.lastMissedCheckIn,
      nextExpectedCheckIn: nextExpectedCheckIn ?? this.nextExpectedCheckIn,
      completedSchedulesToday: completedSchedulesToday ?? this.completedSchedulesToday,
      lastScheduleResetDate: lastScheduleResetDate ?? this.lastScheduleResetDate,
      activeTaskId: activeTaskId ?? this.activeTaskId,
      consecutiveMissedDays: consecutiveMissedDays ?? this.consecutiveMissedDays,
      lastEscalationNotificationAt: lastEscalationNotificationAt ?? this.lastEscalationNotificationAt,
      sosActive: sosActive ?? this.sosActive,
      sosTriggeredAt: sosTriggeredAt ?? this.sosTriggeredAt,
      sosLocationLatitude: sosLocationLatitude ?? this.sosLocationLatitude,
      sosLocationLongitude: sosLocationLongitude ?? this.sosLocationLongitude,
      sosLocationAddress: sosLocationAddress ?? this.sosLocationAddress,
      gamesPlayedToday: gamesPlayedToday ?? this.gamesPlayedToday,
      lastGamePlayResetDate: lastGamePlayResetDate ?? this.lastGamePlayResetDate,
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
