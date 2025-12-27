import 'package:shared_preferences/shared_preferences.dart';

/// Manages active role preferences locally, scoped by user ID.
/// This ensures different users on the same device don't see each other's preferences.
class RolePreferenceService {
  static const String _keyPrefix = 'activeRole_';

  /// Get the active role for a specific user.
  /// Returns 'senior', 'family', or null if not set.
  Future<String?> getActiveRole(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_keyPrefix$uid');
  }

  /// Set the active role for a specific user.
  /// [role] should be 'senior' or 'family'.
  Future<void> setActiveRole(String uid, String role) async {
    if (role != 'senior' && role != 'family') {
      throw ArgumentError('Role must be "senior" or "family"');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$uid', role);
  }

  /// Clear the active role for a specific user (call on logout).
  Future<void> clearActiveRole(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$uid');
  }
}
