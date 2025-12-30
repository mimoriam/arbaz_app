/**
 * Shared constants used across Cloud Functions
 * Keep in sync with lib/utils/constants.dart
 */

module.exports = {
  // Default check-in schedule time
  DEFAULT_CHECK_IN_SCHEDULE: '11:00 AM',
  
  // Default list of check-in schedules for new users
  DEFAULT_SCHEDULES: ['11:00 AM'],
  
  // Default timezone for the app
  TIMEZONE: 'Asia/Karachi',
  
  // Firestore batch operation limits
  BATCH_SIZE: 500,
  GETALL_CHUNK_SIZE: 500,
  
  // Grace period in minutes before marking check-in as missed
  GRACE_PERIOD_MINUTES: 5,
};
