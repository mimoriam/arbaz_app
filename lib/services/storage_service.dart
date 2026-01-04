import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

/// Firebase Storage service for handling profile image uploads
/// with proper error handling, retry logic, and TOCTOU prevention.
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  /// Storage path for profile images: profile_images/{uid}/profile.jpg
  String _profileImagePath(String uid) => 'profile_images/$uid/profile';
  
  /// Temp path for atomic uploads
  String _profileImageTempPath(String uid) => 'profile_images/$uid/profile.tmp';
  
  /// Uploads a profile image for the given user.
  /// 
  /// This method uses an atomic upload pattern to prevent data loss:
  /// 1. Upload new image to a temp path first
  /// 2. Verify upload succeeded
  /// 3. Delete old image (if exists)
  /// 4. Copy/move temp to final path (via re-upload since Firebase doesn't support move)
  /// 5. Clean up temp file
  /// 
  /// Returns the download URL on success, null on failure.
  /// Throws no exceptions - errors are logged and null is returned.
  Future<String?> uploadProfileImage(String uid, File imageFile) async {
    try {
      // Detect MIME type from file extension (fallback to application/octet-stream)
      final mimeType = lookupMimeType(imageFile.path) ?? 'application/octet-stream';
      
      // Get appropriate extension from MIME type
      final extension = _getExtensionFromMime(mimeType);
      final finalPath = '${_profileImagePath(uid)}$extension';
      final tempPath = '${_profileImageTempPath(uid)}$extension';
      
      final tempRef = _storage.ref(tempPath);
      final finalRef = _storage.ref(finalPath);
      
      // Upload new image with metadata to temp path first
      final metadata = SettableMetadata(
        contentType: mimeType,
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
          'uid': uid,
        },
      );
      
      // Step 1: Upload to temp path
      final uploadTask = await _uploadWithRetry(tempRef, imageFile, metadata);
      if (uploadTask == null) {
        debugPrint('StorageService: Failed to upload to temp path');
        return null;
      }
      
      // Step 2: Verify temp upload succeeded by getting URL
      String tempUrl;
      try {
        tempUrl = await tempRef.getDownloadURL();
      } catch (e) {
        debugPrint('StorageService: Failed to verify temp upload: $e');
        await _deleteWithRetry(tempRef); // Clean up temp
        return null;
      }
      
      // Step 3: Delete old image (if exists) - safe now that we have backup
      await _deleteWithRetry(finalRef);
      
      // Step 4: Upload directly to final path (Firebase Storage doesn't support move)
      final finalTask = await _uploadWithRetry(finalRef, imageFile, metadata);
      if (finalTask == null) {
        debugPrint('StorageService: Failed to upload to final path, temp preserved');
        // Keep temp file as backup - user still has their image
        return tempUrl;
      }
      
      // Step 5: Clean up temp file
      await _deleteWithRetry(tempRef);
      
      // Get final download URL
      final downloadUrl = await finalRef.getDownloadURL();
      debugPrint('StorageService: Profile image uploaded successfully for $uid');
      return downloadUrl;
    } catch (e) {
      debugPrint('StorageService: Failed to upload profile image: $e');
      return null;
    }
  }
  
  /// Maps MIME type to file extension
  String _getExtensionFromMime(String mimeType) {
    switch (mimeType) {
      case 'image/png':
        return '.png';
      case 'image/gif':
        return '.gif';
      case 'image/webp':
        return '.webp';
      case 'image/jpeg':
      default:
        return '.jpg';
    }
  }
  
  /// Uploads an image from XFile (from image_picker)
  Future<String?> uploadProfileImageFromXFile(String uid, XFile xFile) async {
    try {
      final file = File(xFile.path);
      return uploadProfileImage(uid, file);
    } catch (e) {
      debugPrint('StorageService: Failed to convert XFile: $e');
      return null;
    }
  }
  
  /// Deletes the profile image for the given user.
  /// Tries all possible extensions since we don't know which format was used.
  /// Returns true on success or if image doesn't exist, false on error.
  Future<bool> deleteProfileImage(String uid) async {
    try {
      final basePath = _profileImagePath(uid);
      final extensions = ['.jpg', '.png', '.gif', '.webp'];
      
      // Try to delete all possible extensions
      for (final ext in extensions) {
        final ref = _storage.ref('$basePath$ext');
        await _deleteWithRetry(ref);
      }
      
      // Also clean up any temp files
      final tempBasePath = _profileImageTempPath(uid);
      for (final ext in extensions) {
        final tempRef = _storage.ref('$tempBasePath$ext');
        await _deleteWithRetry(tempRef);
      }
      
      return true;
    } catch (e) {
      debugPrint('StorageService: Failed to delete profile image: $e');
      return false;
    }
  }
  
  /// Gets the download URL for a user's profile image.
  /// Tries multiple extensions since format may vary.
  /// Returns null if image doesn't exist or on error.
  Future<String?> getProfileImageUrl(String uid) async {
    final basePath = _profileImagePath(uid);
    final extensions = ['.jpg', '.png', '.gif', '.webp'];
    
    for (final ext in extensions) {
      try {
        final ref = _storage.ref('$basePath$ext');
        return await ref.getDownloadURL();
      } on FirebaseException catch (e) {
        // Object not found - try next extension
        if (e.code == 'object-not-found') continue;
        debugPrint('StorageService: Failed to get profile image URL: $e');
        return null;
      } catch (e) {
        debugPrint('StorageService: Unexpected error getting profile URL: $e');
        return null;
      }
    }
    
    // No image found with any extension
    return null;
  }
  
  /// Gets the best available profile photo URL for the current user.
  /// Priority:
  /// 1. Custom uploaded photo (from Firebase Storage)
  /// 2. Google Sign-in photo (from Firebase Auth)
  /// 3. null (show initials)
  Future<String?> getBestProfilePhotoUrl(String uid) async {
    // First try custom uploaded photo
    final customUrl = await getProfileImageUrl(uid);
    if (customUrl != null) return customUrl;
    
    // Fall back to Google Sign-in photo if available
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && currentUser.uid == uid) {
      return currentUser.photoURL;
    }
    
    return null;
  }
  
  /// Syncs the profile photo URL based on sign-in provider and stored data.
  /// 
  /// For Google Sign-in users without a custom photo, returns their Google photo.
  /// For users with a custom photo, returns that.
  /// For email/password users without a custom photo, returns null.
  String? getInitialPhotoUrl(User? firebaseUser) {
    if (firebaseUser == null) return null;
    
    // Check if user signed in with Google
    final isGoogleUser = firebaseUser.providerData.any(
      (info) => info.providerId == 'google.com',
    );
    
    // For Google users, use their Google photo as default
    if (isGoogleUser && firebaseUser.photoURL != null) {
      return firebaseUser.photoURL;
    }
    
    return null;
  }
  
  // ==================== PRIVATE HELPERS ====================
  
  /// Upload with exponential backoff retry
  Future<TaskSnapshot?> _uploadWithRetry(
    Reference ref,
    File file,
    SettableMetadata metadata, {
    int maxAttempts = 3,
  }) async {
    int attempts = 0;
    Duration delay = const Duration(milliseconds: 500);
    
    while (attempts < maxAttempts) {
      try {
        attempts++;
        final task = ref.putFile(file, metadata);
        return await task;
      } on FirebaseException catch (e) {
        debugPrint('StorageService: Upload attempt $attempts failed: ${e.code}');
        
        // Don't retry on permission errors
        if (e.code == 'unauthorized' || e.code == 'permission-denied') {
          return null;
        }
        
        if (attempts < maxAttempts) {
          await Future.delayed(delay);
          delay *= 2; // Exponential backoff
        }
      }
    }
    
    debugPrint('StorageService: Upload failed after $maxAttempts attempts');
    return null;
  }
  
  /// Delete with retry, returns true on success or if not found
  Future<bool> _deleteWithRetry(Reference ref, {int maxAttempts = 3}) async {
    int attempts = 0;
    Duration delay = const Duration(milliseconds: 500);
    
    while (attempts < maxAttempts) {
      try {
        attempts++;
        await ref.delete();
        return true;
      } on FirebaseException catch (e) {
        // Object not found means already deleted - that's success
        if (e.code == 'object-not-found') {
          return true;
        }
        
        debugPrint('StorageService: Delete attempt $attempts failed: ${e.code}');
        
        // Don't retry on permission errors
        if (e.code == 'unauthorized' || e.code == 'permission-denied') {
          return false;
        }
        
        if (attempts < maxAttempts) {
          await Future.delayed(delay);
          delay *= 2;
        }
      }
    }
    
    debugPrint('StorageService: Delete failed after $maxAttempts attempts');
    return false;
  }
}
