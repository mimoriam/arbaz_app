import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/connection_model.dart';

/// Firestore operations with subcollection structure
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ===== Collection References =====

  DocumentReference _profileRef(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('profile');

  DocumentReference _rolesRef(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('roles');

  DocumentReference _seniorStateRef(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('seniorState');

  DocumentReference _familyStateRef(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('familyState');

  CollectionReference _requestsRef(String uid) =>
      _db.collection('users').doc(uid).collection('requests');

  CollectionReference get _connectionsRef => _db.collection('connections');

  // ===== Profile Operations =====

  Future<void> createUserProfile(String uid, UserProfile profile) async {
    await _profileRef(uid).set(profile.toFirestore());
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _profileRef(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc);
  }

  /// Updates the lastLoginAt timestamp for an existing profile.
  /// Throws if the profile document does not exist (fail-fast behavior).
  /// Use createUserProfile() first if the profile doesn't exist.
  Future<void> updateLastLogin(String uid) async {
    await _profileRef(uid).update({
      'lastLoginAt': Timestamp.now(),
    });
  }

  /// Updates specific fields on an existing user profile.
  /// Throws if the profile document does not exist (fail-fast behavior).
  /// Use createUserProfile() first if the profile doesn't exist.
  Future<void> updateUserProfile(
    String uid,
    Map<String, dynamic> updates,
  ) async {
    await _profileRef(uid).update(updates);
  }

  // ===== Roles Operations =====

  Future<UserRoles?> getUserRoles(String uid) async {
    final doc = await _rolesRef(uid).get();
    if (!doc.exists) return null;
    return UserRoles.fromFirestore(doc);
  }

  Future<void> setRole(
    String uid, {
    bool? isSenior,
    bool? isFamilyMember,
  }) async {
    final updates = <String, dynamic>{};
    if (isSenior != null) updates['isSenior'] = isSenior;
    if (isFamilyMember != null) updates['isFamilyMember'] = isFamilyMember;

    // Early return if no updates
    if (updates.isEmpty) return;

    await _rolesRef(uid).set(updates, SetOptions(merge: true));
  }

  Future<void> setAsSenior(String uid) async {
    await setRole(uid, isSenior: true);
  }

  Future<void> setAsFamilyMember(String uid) async {
    await setRole(uid, isFamilyMember: true);
  }

  // ===== Volatile State Operations =====

  Future<SeniorState?> getSeniorState(String uid) async {
    final doc = await _seniorStateRef(uid).get();
    if (!doc.exists) return null;
    return SeniorState.fromFirestore(doc);
  }

  Future<void> updateSeniorState(String uid, SeniorState state) async {
    await _seniorStateRef(uid).set(state.toFirestore(), SetOptions(merge: true));
  }

  Future<FamilyState?> getFamilyState(String uid) async {
    final doc = await _familyStateRef(uid).get();
    if (!doc.exists) return null;
    return FamilyState.fromFirestore(doc);
  }

  Future<void> updateFamilyState(String uid, FamilyState state) async {
    await _familyStateRef(uid).set(state.toFirestore(), SetOptions(merge: true));
  }

  // ===== Progressive Profile =====

  /// Updates phone number on an existing profile.
  /// Throws if the profile document does not exist (fail-fast behavior).
  /// Use createUserProfile() first if the profile doesn't exist.
  Future<void> updatePhoneNumber(String uid, String phoneNumber) async {
    await _profileRef(uid).update({
      'phoneNumber': phoneNumber,
    });
  }

  /// Updates emergency contact in senior state.
  /// Uses merge semantics - will create the seniorState document if it doesn't
  /// exist (progressive profile collection). This is intentional for gradual
  /// profile building after initial registration.
  Future<void> updateEmergencyContact(
    String uid,
    EmergencyContact contact,
  ) async {
    await _seniorStateRef(uid).set(
      {'emergencyContact': contact.toMap()},
      SetOptions(merge: true),
    );
  }

  // ===== Connections (Top-level, UIDs only) =====

  Future<void> createConnection(Connection connection) async {
    await _connectionsRef.doc(connection.id).set(connection.toFirestore());
  }

  Stream<List<Connection>> getConnectionsForSenior(String seniorId) {
    return _connectionsRef
        .where('seniorId', isEqualTo: seniorId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Connection.fromFirestore(doc)).toList());
  }

  Stream<List<Connection>> getConnectionsForFamily(String familyId) {
    return _connectionsRef
        .where('familyId', isEqualTo: familyId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Connection.fromFirestore(doc)).toList());
  }

  Future<void> updateConnectionStatus(String connectionId, String status) async {
    await _connectionsRef.doc(connectionId).update({'status': status});
  }

  /// Fetch multiple profiles by UID (for displaying connection names)
  Future<Map<String, UserProfile>> getProfilesByUids(List<String> uids) async {
    if (uids.isEmpty) return {};

    final profiles = <String, UserProfile>{};

    // Firestore 'in' queries limited to 30 items
    for (var i = 0; i < uids.length; i += 30) {
      final batch = uids.skip(i).take(30).toList();
      final futures = batch.map((uid) => getUserProfile(uid));
      final results = await Future.wait(futures);

      for (var j = 0; j < batch.length; j++) {
        if (results[j] != null) {
          profiles[batch[j]] = results[j]!;
        }
      }
    }

    return profiles;
  }

  // ===== Requests (Subcollection) =====

  Future<void> createRequest(String uid, ConnectionRequest request) async {
    await _requestsRef(uid).doc(request.id).set(request.toFirestore());
  }

  Stream<List<ConnectionRequest>> getPendingRequests(String uid) {
    return _requestsRef(uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ConnectionRequest.fromFirestore(doc))
            .toList());
  }

  Future<void> updateRequestStatus(
    String uid,
    String requestId,
    String status,
  ) async {
    await _requestsRef(uid).doc(requestId).update({'status': status});
  }

  // ===== Transaction-based operations =====

  /// Create user with profile and default roles in a transaction
  Future<void> createUserWithRoles(
    String uid,
    UserProfile profile,
    UserRoles roles,
  ) async {
    await _db.runTransaction((transaction) async {
      transaction.set(_profileRef(uid), profile.toFirestore());
      transaction.set(_rolesRef(uid), roles.toFirestore());
    });
  }
}
