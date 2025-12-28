import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:arbaz_app/models/family_contact_model.dart';

class FamilyContactsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _contactsRef(String uid) =>
      _db.collection('users').doc(uid).collection('familyContacts');

  /// Gets a stream of user's family contacts
  /// Returns Stream.empty() if uid is invalid
  Stream<List<FamilyContactModel>> getContacts(String uid) {
    // Validate uid
    if (uid.isEmpty) {
      debugPrint('FamilyContactsService.getContacts: uid cannot be empty');
      return Stream.value(<FamilyContactModel>[]);
    }
    
    return _contactsRef(uid)
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => FamilyContactModel.fromFirestore(doc))
              .toList();
        });
  }

  /// Adds a new contact with auto-generated ID if contact.id is empty
  Future<void> addContact(String uid, FamilyContactModel contact) async {
    // Validate uid
    if (uid.isEmpty) {
      throw ArgumentError('uid cannot be empty');
    }
    
    // Determine if this is a new contact (no id) or updating existing
    final isNewContact = contact.id.isEmpty;
    
    // Generate auto-id if not provided, otherwise use existing id
    final docRef = isNewContact 
        ? _contactsRef(uid).doc()  // Auto-generate ID
        : _contactsRef(uid).doc(contact.id);
    
    // Update contact with the actual document ID and ensure addedAt is set
    final contactWithId = contact.copyWith(id: docRef.id);
    
    // Build the data to write, ensuring addedAt is always present
    final data = contactWithId.toFirestore();
    
    // For new contacts: use plain set() to create fresh document
    // For existing contacts with provided id: still use plain set() 
    // since addedAt is ensured to be set in the model
    await docRef.set(data);
  }

  /// Removes a contact by ID
  Future<void> removeContact(String uid, String contactId) async {
    if (uid.isEmpty) {
      throw ArgumentError('uid cannot be empty');
    }
    if (contactId.isEmpty) {
      throw ArgumentError('contactId cannot be empty');
    }
    await _contactsRef(uid).doc(contactId).delete();
  }
  
  /// Checks if the user has any contacts (useful for SOS button state)
  Future<bool> hasContacts(String uid) async {
    if (uid.isEmpty) {
      return false;
    }
    final snapshot = await _contactsRef(uid).limit(1).get();
    return snapshot.docs.isNotEmpty;
  }
}
