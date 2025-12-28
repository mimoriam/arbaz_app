import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyContactModel {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final DateTime addedAt;

  FamilyContactModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.addedAt,
  });

  factory FamilyContactModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('Document ${doc.id} does not exist or has no data');
    }
    return FamilyContactModel(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      relationship: data['relationship'] ?? '',
      addedAt: (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'relationship': relationship,
      'addedAt': Timestamp.fromDate(addedAt),
    };
  }

  FamilyContactModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? relationship,
    DateTime? addedAt,
  }) {
    return FamilyContactModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      relationship: relationship ?? this.relationship,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}
