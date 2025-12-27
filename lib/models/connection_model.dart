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

/// Connection between Senior and Family member
/// Stored in top-level connections/{id} collection
/// UIDs only - fetch profiles separately to avoid stale data
class Connection {
  final String id;
  final String seniorId;
  final String familyId;
  final String status; // 'active', 'pending', 'removed'
  final String? relationshipType; // 'son', 'daughter', 'spouse', etc.
  final DateTime createdAt;

  Connection({
    required this.id,
    required this.seniorId,
    required this.familyId,
    required this.status,
    this.relationshipType,
    required this.createdAt,
  });

  factory Connection.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    if (rawData == null || rawData is! Map<String, dynamic>) {
      throw FormatException('Invalid Connection document: ${doc.id}');
    }
    final data = rawData;
    return Connection(
      id: doc.id,
      seniorId: data['seniorId'] as String? ?? '',
      familyId: data['familyId'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      relationshipType: data['relationshipType'] as String?,
      createdAt: _parseDateTime(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'seniorId': seniorId,
      'familyId': familyId,
      'status': status,
      'relationshipType': relationshipType,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  Connection copyWith({String? status, String? relationshipType}) {
    return Connection(
      id: id,
      seniorId: seniorId,
      familyId: familyId,
      status: status ?? this.status,
      relationshipType: relationshipType ?? this.relationshipType,
      createdAt: createdAt,
    );
  }
}

/// Connection request stored in users/{uid}/requests/{id}
class ConnectionRequest {
  final String id;
  final String fromUserId;
  final String toUserId;
  final String type; // 'family_to_senior', 'senior_to_family'
  final String inviteMethod; // 'qr', 'phone', 'app'
  final DateTime createdAt;
  final String status; // 'pending', 'accepted', 'declined'

  ConnectionRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.type,
    required this.inviteMethod,
    required this.createdAt,
    required this.status,
  });

  factory ConnectionRequest.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    if (rawData == null || rawData is! Map<String, dynamic>) {
      throw FormatException('Invalid ConnectionRequest document: ${doc.id}');
    }
    final data = rawData;
    return ConnectionRequest(
      id: doc.id,
      fromUserId: data['fromUserId'] as String? ?? '',
      toUserId: data['toUserId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      inviteMethod: data['inviteMethod'] as String? ?? 'app',
      createdAt: _parseDateTime(data['createdAt']),
      status: data['status'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'type': type,
      'inviteMethod': inviteMethod,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status,
    };
  }

  ConnectionRequest copyWith({String? status}) {
    return ConnectionRequest(
      id: id,
      fromUserId: fromUserId,
      toUserId: toUserId,
      type: type,
      inviteMethod: inviteMethod,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }
}
