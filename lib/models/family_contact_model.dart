import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyContactModel {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final DateTime addedAt;
  /// UID of the connected user - used for live profile lookups
  /// If set, the UI should fetch the live profile instead of using 'name'
  final String? contactUid;

  FamilyContactModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.addedAt,
    this.contactUid,
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
      contactUid: data['contactUid'] as String?,
    );
  }
  Map<String, dynamic> toFirestore() {
    final data = <String, dynamic>{
      'name': name,
      'phone': phone,
      'relationship': relationship,
      'addedAt': Timestamp.fromDate(addedAt),
    };
    if (contactUid != null) {
      data['contactUid'] = contactUid;
    }
    return data;
  }

  FamilyContactModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? relationship,
    DateTime? addedAt,
    String? contactUid,
  }) {
    return FamilyContactModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      relationship: relationship ?? this.relationship,
      addedAt: addedAt ?? this.addedAt,
      contactUid: contactUid ?? this.contactUid,
    );
  }
}
