/// Shared constants used across the app and Cloud Functions
/// Keep in sync with functions/constants.js
abstract class AppConstants {
  /// Default check-in schedule time
  static const defaultCheckInSchedule = '11:00 AM';
  
  /// Default list of check-in schedules for new users
  static const defaultSchedules = ['11:00 AM'];
  
  /// Default timezone for the app
  static const timezone = 'Asia/Karachi';
  
  /// Firestore batch operation limits
  static const firestoreBatchLimit = 500;
  static const firestoreWhereInLimit = 30;
}
