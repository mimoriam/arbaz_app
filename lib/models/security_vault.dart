import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for pet information in the security vault
class PetInfo {
  final String name;
  final String type;
  final String? medications;
  final String? vetNamePhone;
  final String? foodInstructions;
  final String? specialNeeds;

  PetInfo({
    required this.name,
    required this.type,
    this.medications,
    this.vetNamePhone,
    this.foodInstructions,
    this.specialNeeds,
  });

  factory PetInfo.fromMap(Map<String, dynamic> map) {
    return PetInfo(
      name: map['name'] as String? ?? '',
      type: map['type'] as String? ?? '',
      medications: map['medications'] as String?,
      vetNamePhone: map['vetNamePhone'] as String?,
      foodInstructions: map['foodInstructions'] as String?,
      specialNeeds: map['specialNeeds'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'medications': medications,
      'vetNamePhone': vetNamePhone,
      'foodInstructions': foodInstructions,
      'specialNeeds': specialNeeds,
    };
  }

  /// Creates a copy with updated values
  PetInfo copyWith({
    String? name,
    String? type,
    String? medications,
    String? vetNamePhone,
    String? foodInstructions,
    String? specialNeeds,
  }) {
    return PetInfo(
      name: name ?? this.name,
      type: type ?? this.type,
      medications: medications ?? this.medications,
      vetNamePhone: vetNamePhone ?? this.vetNamePhone,
      foodInstructions: foodInstructions ?? this.foodInstructions,
      specialNeeds: specialNeeds ?? this.specialNeeds,
    );
  }
}

/// Model for the security vault containing sensitive information
class SecurityVault {
  // Home Access
  final String? homeAddress;
  final String? buildingEntryCode;
  final String? apartmentDoorCode;
  final String? spareKeyLocation;
  final String? alarmCode;

  // Pet Care - multiple pets supported
  final List<PetInfo> pets;

  // Medical Info
  final String? doctorNamePhone;
  final String? medicationsList;
  final String? allergies;
  final String? medicalConditions;

  // Other Notes
  final String? otherNotes;

  // Metadata
  final DateTime? updatedAt;

  SecurityVault({
    this.homeAddress,
    this.buildingEntryCode,
    this.apartmentDoorCode,
    this.spareKeyLocation,
    this.alarmCode,
    this.pets = const [],
    this.doctorNamePhone,
    this.medicationsList,
    this.allergies,
    this.medicalConditions,
    this.otherNotes,
    this.updatedAt,
  });

  factory SecurityVault.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    // Parse pets list
    List<PetInfo> pets = [];
    if (data['pets'] is List) {
      pets = (data['pets'] as List)
          .whereType<Map<String, dynamic>>()
          .map((p) => PetInfo.fromMap(p))
          .toList();
    }

    return SecurityVault(
      homeAddress: data['homeAddress'] as String?,
      buildingEntryCode: data['buildingEntryCode'] as String?,
      apartmentDoorCode: data['apartmentDoorCode'] as String?,
      spareKeyLocation: data['spareKeyLocation'] as String?,
      alarmCode: data['alarmCode'] as String?,
      pets: pets,
      doctorNamePhone: data['doctorNamePhone'] as String?,
      medicationsList: data['medicationsList'] as String?,
      allergies: data['allergies'] as String?,
      medicalConditions: data['medicalConditions'] as String?,
      otherNotes: data['otherNotes'] as String?,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    final lastUpdated = updatedAt;
    return {
      'homeAddress': homeAddress,
      'buildingEntryCode': buildingEntryCode,
      'apartmentDoorCode': apartmentDoorCode,
      'spareKeyLocation': spareKeyLocation,
      'alarmCode': alarmCode,
      'pets': pets.map((p) => p.toMap()).toList(),
      'doctorNamePhone': doctorNamePhone,
      'medicationsList': medicationsList,
      'allergies': allergies,
      'medicalConditions': medicalConditions,
      'otherNotes': otherNotes,
      'updatedAt': lastUpdated != null ? Timestamp.fromDate(lastUpdated) : Timestamp.now(),
    };
  }

  /// Creates a copy with updated values
  SecurityVault copyWith({
    String? homeAddress,
    String? buildingEntryCode,
    String? apartmentDoorCode,
    String? spareKeyLocation,
    String? alarmCode,
    List<PetInfo>? pets,
    String? doctorNamePhone,
    String? medicationsList,
    String? allergies,
    String? medicalConditions,
    String? otherNotes,
    DateTime? updatedAt,
  }) {
    return SecurityVault(
      homeAddress: homeAddress ?? this.homeAddress,
      buildingEntryCode: buildingEntryCode ?? this.buildingEntryCode,
      apartmentDoorCode: apartmentDoorCode ?? this.apartmentDoorCode,
      spareKeyLocation: spareKeyLocation ?? this.spareKeyLocation,
      alarmCode: alarmCode ?? this.alarmCode,
      pets: pets ?? this.pets,
      doctorNamePhone: doctorNamePhone ?? this.doctorNamePhone,
      medicationsList: medicationsList ?? this.medicationsList,
      allergies: allergies ?? this.allergies,
      medicalConditions: medicalConditions ?? this.medicalConditions,
      otherNotes: otherNotes ?? this.otherNotes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
