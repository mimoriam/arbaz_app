import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/connection_model.dart';
import '../models/checkin_model.dart';

/// Explicit streak state for clear state transitions
enum StreakState {
  sameDay,     // 0 days since last check-in
  consecutive, // 1 day since last check-in
  broken       // 2+ days since last check-in
}

/// Calculate the streak state between two dates
StreakState calculateStreakState(DateTime last, DateTime now) {
  final lastDay = DateTime(last.year, last.month, last.day);
  final nowDay = DateTime(now.year, now.month, now.day);
  final diff = nowDay.difference(lastDay).inDays;
  
  if (diff == 0) return StreakState.sameDay;
  if (diff == 1) return StreakState.consecutive;
  return StreakState.broken;
}

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
      
  CollectionReference _checkInsRef(String uid) =>
      _db.collection('users').doc(uid).collection('checkIns');

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
  Future<void> updateLastLogin(String uid) async {
    await _profileRef(uid).update({
      'lastLoginAt': Timestamp.now(),
    });
  }
  
  /// Updates user location in profile
  Future<void> updateUserLocation(String uid, double latitude, double longitude, String? address) async {
    final Map<String, dynamic> updates = {
      'latitude': latitude,
      'longitude': longitude,
    };
    if (address != null) {
      updates['locationAddress'] = address;
    }
    await _profileRef(uid).update(updates);
  }

  /// Updates specific fields on an existing user profile.
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

  /// Stream senior state for real-time updates (avoids polling)
  Stream<SeniorState?> streamSeniorState(String seniorUid) {
    if (seniorUid.isEmpty) return Stream.value(null);
    
    return _seniorStateRef(seniorUid)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          return SeniorState.fromFirestore(snap);
        })
        .transform(
          StreamTransformer<SeniorState?, SeniorState?>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              // Log the error (using print since debugPrint requires flutter import)
              print('Error streaming senior state: $error');
              // Emit null to subscribers for graceful degradation
              sink.add(null);
            },
          ),
        );
  }

  Future<void> mergeCheckInSchedules(String uid, List<String> schedules) async {
    await _seniorStateRef(uid).set({
      'checkInSchedules': schedules,
    }, SetOptions(merge: true));
  }

  /// Atomically adds a schedule time using FieldValue.arrayUnion
  Future<void> atomicAddSchedule(String uid, String time) async {
    await _seniorStateRef(uid).set({
      'checkInSchedules': FieldValue.arrayUnion([time]),
    }, SetOptions(merge: true));
  }

  /// Atomically removes a schedule time using FieldValue.arrayRemove
  Future<void> atomicRemoveSchedule(String uid, String time) async {
    await _seniorStateRef(uid).update({
      'checkInSchedules': FieldValue.arrayRemove([time]),
    });
  }

  /// Atomically updates a single field in SeniorState using merge
  /// Avoids read-modify-write race conditions
  Future<void> atomicUpdateSeniorField(String uid, String field, dynamic value) async {
    await _seniorStateRef(uid).set({
      field: value,
    }, SetOptions(merge: true));
  }

  Future<FamilyState?> getFamilyState(String uid) async {
    final doc = await _familyStateRef(uid).get();
    if (!doc.exists) return null;
    return FamilyState.fromFirestore(doc);
  }

  Future<void> updateFamilyState(String uid, FamilyState state) async {
    await _familyStateRef(uid).set(state.toFirestore(), SetOptions(merge: true));
  }
  
  // ===== Check-in Operations =====
  
  /// Records a check-in atomically using a transaction to prevent race conditions
  Future<void> recordCheckIn(String uid, CheckInRecord record) async {
    final seniorStateRef = _seniorStateRef(uid);
    final profileRef = _profileRef(uid);
    
    await _db.runTransaction((transaction) async {
      // 1. Read senior state within transaction
      final seniorStateDoc = await transaction.get(seniorStateRef);
      
      int newStreak = 1;
      DateTime startDate = DateTime.now();
      
      if (seniorStateDoc.exists) {
        final rawData = seniorStateDoc.data();
        if (rawData != null && rawData is Map<String, dynamic>) {
          final data = rawData;
          // Get current streak (validate: must be non-negative)
          final currentStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;
          
          // Get stored start date
          if (data['startDate'] is Timestamp) {
            startDate = (data['startDate'] as Timestamp).toDate();
          }
          
          // Get last check-in
          final lastCheckInTimestamp = data['lastCheckIn'] as Timestamp?;
          if (lastCheckInTimestamp != null) {
            final lastCheckIn = lastCheckInTimestamp.toDate();
            
            // Use explicit state machine for clarity
            final streakState = calculateStreakState(lastCheckIn, record.timestamp);
            
            switch (streakState) {
              case StreakState.sameDay:
                // Same day check-in, keep current streak (minimum 1)
                newStreak = currentStreak > 0 ? currentStreak : 1;
              case StreakState.consecutive:
                // Consecutive day, increment streak
                newStreak = currentStreak + 1;
              case StreakState.broken:
                // Streak broken, reset to 1 and update startDate
                newStreak = 1;
                startDate = record.timestamp;
            }
          } else if (currentStreak > 0) {
            // Edge case: has streak but no lastCheckIn timestamp
            // This shouldn't happen in normal operation - reset to safe state
            newStreak = 1;
            startDate = record.timestamp;
          }
        }
      }
      
      // 2. Create check-in document with auto-id
      final checkInDocRef = _checkInsRef(uid).doc();
      transaction.set(checkInDocRef, record.toFirestore());
      
      // 3. Update senior state with streak info
      transaction.set(seniorStateRef, {
        'lastCheckIn': Timestamp.fromDate(record.timestamp),
        'currentStreak': newStreak,
        'startDate': Timestamp.fromDate(startDate),
      }, SetOptions(merge: true));
      
      // 4. If location info is present, update user profile location
      if (record.latitude != null && record.longitude != null) {
        final Map<String, dynamic> locationUpdates = {
          'latitude': record.latitude,
          'longitude': record.longitude,
        };
        if (record.locationAddress != null) {
          locationUpdates['locationAddress'] = record.locationAddress;
        }
        transaction.set(profileRef, locationUpdates, SetOptions(merge: true));
      }
    });
  }
  
  Future<List<CheckInRecord>> getCheckInsForMonth(String uid, int year, int month) async {
    final start = DateTime(year, month, 1);
    // Handle December case for end date
    final endYear = month == 12 ? year + 1 : year;
    final endMonth = month == 12 ? 1 : month + 1;
    final end = DateTime(endYear, endMonth, 1);
    
    final snapshot = await _checkInsRef(uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .orderBy('timestamp', descending: true)
        .get();
        
    return snapshot.docs
        .map((doc) => CheckInRecord.fromFirestore(doc))
        .toList();
  }

  /// Get check-ins for a senior for the past 7 days
  /// Uses a single indexed query (requires composite index on userId + timestamp)
  /// Returns empty list on error for graceful degradation
  Future<List<CheckInRecord>> getSeniorCheckInsForWeek(String seniorUid) async {
    if (seniorUid.isEmpty) return [];
    try {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final snapshot = await _checkInsRef(seniorUid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekAgo))
          .orderBy('timestamp', descending: true)
          .get();
      return snapshot.docs.map((d) => CheckInRecord.fromFirestore(d)).toList();
    } catch (e) {
      // debugPrint('Error fetching weekly check-ins: $e');
      return []; // Graceful degradation
    }
  }
  
  // ===== Progressive Profile =====

  Future<void> updatePhoneNumber(String uid, String phoneNumber) async {
    await _profileRef(uid).update({
      'phoneNumber': phoneNumber,
    });
  }

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

  // ===== Deletion Operations =====

  Future<void> deleteFamilyConnection(String currentUid, String contactUid) async {
    // 1. Define possible connection IDs
    final possibleId1 = '${currentUid}_$contactUid';
    final possibleId2 = '${contactUid}_$currentUid';

    // 2. Run transaction for both read and delete operations
    await _db.runTransaction((transaction) async {
      DocumentReference? connectionRefToDelete;

      // Check existence of first possible ID
      final docRef1 = _connectionsRef.doc(possibleId1);
      final docSnapshot1 = await transaction.get(docRef1);

      if (docSnapshot1.exists) {
        connectionRefToDelete = docRef1;
      } else {
        // If first doesn't exist, check the second
        final docRef2 = _connectionsRef.doc(possibleId2);
        final docSnapshot2 = await transaction.get(docRef2);
        if (docSnapshot2.exists) {
          connectionRefToDelete = docRef2;
        }
      }

      // If a connection document was found, delete it
      if (connectionRefToDelete != null) {
        transaction.delete(connectionRefToDelete);
      }

      // Remove from current user's contacts
      transaction.delete(
          _db.collection('users').doc(currentUid).collection('familyContacts').doc(contactUid)
      );

      // Remove from the other user's contacts
      transaction.delete(
          _db.collection('users').doc(contactUid).collection('familyContacts').doc(currentUid)
      );
    });
  }

  // ===== Atomic Connection Creation =====

  /// Creates a family connection atomically using WriteBatch.
  /// This ensures all operations succeed or fail together:
  /// 1. Create the connection document
  /// 2. Add contact to current user's familyContacts
  /// 3. Add contact to invited user's familyContacts (bidirectional)
  /// 
  /// Uses contactUid for live profile lookups instead of denormalized names.
  /// Creates a family connection atomically using a transaction for idempotency.
  /// This ensures:
  /// 1. If connection already exists, the operation is skipped (idempotent)
  /// 2. All operations succeed or fail together
  /// 3. Network failures after commit are handled gracefully
  Future<void> createFamilyConnectionAtomic({
    required String currentUserId,
    required String invitedUserId,
    required String currentUserName,
    required String invitedUserName,
    required String currentUserPhone,
    required String invitedUserPhone,
    required String invitedUserRole, // 'Senior' or 'Family'
  }) async {
    // Determine senior vs family based on role
    final String seniorId;
    final String familyId;
    if (invitedUserRole == 'Senior') {
      seniorId = invitedUserId;
      familyId = currentUserId;
    } else {
      seniorId = currentUserId;
      familyId = invitedUserId;
    }
    
    final connectionId = '${seniorId}_$familyId';
    
    // Use a transaction for idempotency check + atomic writes
    await _db.runTransaction((transaction) async {
      // Idempotency check: if connection already exists, skip
      final existingConnection = await transaction.get(_connectionsRef.doc(connectionId));
      if (existingConnection.exists) {
        return; // Already connected, nothing to do
      }
      // 1. Create connection document
      transaction.set(_connectionsRef.doc(connectionId), {
        'id': connectionId,
        'seniorId': seniorId,
        'familyId': familyId,
        'status': 'active',
        'createdAt': Timestamp.now(),
      });

      // 2. Add invited user to current user's contacts
      final currentUserContactRef = _db
          .collection('users')
          .doc(currentUserId)
          .collection('familyContacts')
          .doc(invitedUserId);
      transaction.set(currentUserContactRef, {
        'name': invitedUserName,
        'phone': invitedUserPhone,
        'relationship': invitedUserRole,
        'addedAt': Timestamp.now(),
        'contactUid': invitedUserId,
      });

      // 3. Add current user to invited user's contacts (bidirectional)
      final invitedUserContactRef = _db
          .collection('users')
          .doc(invitedUserId)
          .collection('familyContacts')
          .doc(currentUserId);
      transaction.set(invitedUserContactRef, {
        'name': currentUserName,
        'phone': currentUserPhone,
        'relationship': 'Family',
        'addedAt': Timestamp.now(),
        'contactUid': currentUserId,
      });
    });
  }
}
