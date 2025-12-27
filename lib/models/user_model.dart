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

/// Core user profile stored in users/{uid}/profile
class UserProfile {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? phoneNumber;
  final DateTime createdAt;
  final DateTime lastLoginAt;

  UserProfile({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.phoneNumber,
    required this.createdAt,
    required this.lastLoginAt,
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
      throw FormatException('Missing or invalid email in UserProfile: ${doc.id}');
    }

    return UserProfile(
      uid: doc.id,
      email: email,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      createdAt: _parseDateTime(data['createdAt']),
      lastLoginAt: _parseDateTime(data['lastLoginAt']),
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
    };
  }

  UserProfile copyWith({
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    DateTime? lastLoginAt,
  }) {
    return UserProfile(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}

/// User roles stored in users/{uid}/roles
class UserRoles {
  final bool isSenior;
  final bool isFamilyMember;

  UserRoles({
    this.isSenior = false,
    this.isFamilyMember = false,
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
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'isSenior': isSenior,
      'isFamilyMember': isFamilyMember,
    };
  }

  UserRoles copyWith({bool? isSenior, bool? isFamilyMember}) {
    return UserRoles(
      isSenior: isSenior ?? this.isSenior,
      isFamilyMember: isFamilyMember ?? this.isFamilyMember,
    );
  }
}

/// Volatile senior state stored in users/{uid}/seniorState
class SeniorState {
  final DateTime? lastCheckIn;
  final bool vacationMode;
  final EmergencyContact? emergencyContact;

  SeniorState({
    this.lastCheckIn,
    this.vacationMode = false,
    this.emergencyContact,
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

    return SeniorState(
      lastCheckIn: data['lastCheckIn'] is Timestamp
          ? (data['lastCheckIn'] as Timestamp).toDate()
          : null,
      vacationMode: data['vacationMode'] == true,
      emergencyContact: emergencyContact,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'lastCheckIn':
          lastCheckIn != null ? Timestamp.fromDate(lastCheckIn!) : null,
      'vacationMode': vacationMode,
      'emergencyContact': emergencyContact?.toMap(),
    };
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
    return {
      'defaultRelationship': defaultRelationship,
    };
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
    if (phoneNumber == null || phoneNumber is! String || phoneNumber.trim().isEmpty) {
      throw const FormatException(
        'EmergencyContact: "phoneNumber" field is required and must be a non-empty string',
      );
    }

    final relationship = map['relationship'];
    if (relationship == null || relationship is! String || relationship.trim().isEmpty) {
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
