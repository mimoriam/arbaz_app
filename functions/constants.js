/**
 * Shared constants used across Cloud Functions
 * Keep in sync with lib/utils/constants.dart
 */

module.exports = {
  // Default check-in schedule time
  DEFAULT_CHECK_IN_SCHEDULE: '11:00 AM',
  
  // Default list of check-in schedules for new users
  DEFAULT_SCHEDULES: ['11:00 AM'],
  
  // Default timezone - ONLY used as fallback when user's profile.timezone is null/undefined
  // User's actual timezone should always be preferred for accurate day boundary calculations
  // See getUserTimezone() in index.js for retrieval logic
  TIMEZONE: 'Asia/Karachi',
  
  // Firestore batch operation limits
  BATCH_SIZE: 500,
  GETALL_CHUNK_SIZE: 500,
  
  // Grace period in minutes before marking check-in as missed
  // Set to 0 for instant notification when scheduled time passes
  GRACE_PERIOD_MINUTES: 0,
  
  // Cloud Tasks configuration
  CLOUD_TASKS_QUEUE: 'check-in-queue',
  CLOUD_TASKS_LOCATION: 'us-central1',
  
  // Escalation threshold: send alerts after this many consecutive missed days
  ESCALATION_THRESHOLD_DAYS: 3,
};
