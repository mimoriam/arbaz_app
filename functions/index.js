/**
 * Firebase Cloud Functions for SafeCheck App
 * 
 * CLOUD TASKS ARCHITECTURE v3:
 * - Uses Cloud Tasks for event-driven check-in monitoring
 * - Tasks are created when schedules are set, cancelled on check-in
 * - No periodic polling - only run code when needed
 * - Consecutive missed days trigger escalation alerts
 */

const { setGlobalOptions } = require("firebase-functions");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const logger = require("firebase-functions/logger");
const { DateTime } = require("luxon");
const { CloudTasksClient } = require("@google-cloud/tasks");

const admin = require("firebase-admin");

// Import shared constants (keep in sync with lib/utils/constants.dart)
const {
  DEFAULT_CHECK_IN_SCHEDULE,
  DEFAULT_SCHEDULES,
  TIMEZONE,
  BATCH_SIZE,
  GETALL_CHUNK_SIZE,
  GRACE_PERIOD_MINUTES,
  CLOUD_TASKS_QUEUE,
  CLOUD_TASKS_LOCATION,
  ESCALATION_THRESHOLD_DAYS,
} = require("./constants");

// Initialize Firebase Admin (guarded to prevent duplicate initialization)
if (!admin.apps.length) {
  initializeApp();
}
const db = getFirestore();
const tasksClient = new CloudTasksClient();

// Global options for cost control
setGlobalOptions({ maxInstances: 20 });

// Get project ID from environment
const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
if (!PROJECT_ID) {
  throw new Error("PROJECT_ID not found in environment variables");
}

/**
 * Parse a schedule time string (e.g., "11:00 AM") into hours and minutes
 */
function parseScheduleToTime(schedule) {
  try {
    if (!schedule || typeof schedule !== "string") return null;
    
    // First add space before AM/PM if missing, then normalize all whitespace
    let normalized = schedule.trim().toUpperCase();
    normalized = normalized.replace(/(AM|PM)$/i, " $1"); // Add space before AM/PM
    normalized = normalized.replace(/\s+/g, " ").trim(); // Normalize to single spaces
    
    const parts = normalized.split(" ");
    if (parts.length !== 2) return null;

    const [time, period] = parts;
    if (period !== "AM" && period !== "PM") return null;
    
    const timeParts = time.split(":");
    if (timeParts.length !== 2) return null;

    let hours = parseInt(timeParts[0], 10);
    const minutes = parseInt(timeParts[1], 10);

    if (isNaN(hours) || isNaN(minutes)) return null;
    if (hours < 1 || hours > 12 || minutes < 0 || minutes > 59) return null;

    if (period === "PM" && hours !== 12) hours += 12;
    if (period === "AM" && hours === 12) hours = 0;

    return { hours, minutes };
  } catch (error) {
    return null;
  }
}

/**
 * Calculate the next expected check-in time based on schedules
 * Uses Luxon for timezone-aware date handling
 * For multi check-in support, considers which schedules are already completed today
 * @param {Array<string>} schedules - Check-in schedule times
 * @param {Date} now - Current time
 * @param {Date|null} lastCheckIn - Last check-in time
 * @param {string|null} userTimezone - User's IANA timezone (optional, defaults to TIMEZONE constant)
 * @param {Array<string>} completedSchedulesToday - List of schedule times already completed today
 * @returns {Date|null} - JS Date object for caller compatibility
 */
function calculateNextExpectedCheckIn(schedules, now, lastCheckIn, userTimezone = null, completedSchedulesToday = []) {
  const effectiveSchedules = schedules?.length ? schedules : ["11:00 AM"];
  
  // Use user's timezone if provided, otherwise fall back to default
  const tz = userTimezone && typeof userTimezone === 'string' && userTimezone.trim() 
    ? userTimezone.trim() 
    : TIMEZONE;
  
  // Convert to timezone-aware DateTime
  const nowInZone = DateTime.fromJSDate(now, { zone: tz });
  const tomorrowInZone = nowInZone.plus({ days: 1 });
  
  // Normalize completed schedules for comparison
  const completedSet = new Set(
    (completedSchedulesToday || []).map(s => s.toUpperCase().trim())
  );
  
  // Check if ALL past-due schedules are completed
  const allPastDueCompleted = effectiveSchedules.every(schedule => {
    const parsed = parseScheduleToTime(schedule);
    if (!parsed) return true;
    
    const scheduleTime = nowInZone.set({ 
      hour: parsed.hours, 
      minute: parsed.minutes, 
      second: 0, 
      millisecond: 0 
    });
    
    // If schedule hasn't passed yet, it doesn't count as past-due
    if (scheduleTime > nowInZone) return true;
    
    // Check if this past-due schedule is completed
    return completedSet.has(schedule.toUpperCase().trim());
  });
  
  // Find next pending schedule today (not completed and in the future)
  let nextPendingToday = null;
  let earliestPastDueToday = null; // For "running late" detection
  let earliestTomorrow = null;
  
  for (const schedule of effectiveSchedules) {
    const parsed = parseScheduleToTime(schedule);
    if (!parsed) continue;
    
    const isCompleted = completedSet.has(schedule.toUpperCase().trim());
    
    const todayTime = nowInZone.set({ 
      hour: parsed.hours, 
      minute: parsed.minutes, 
      second: 0, 
      millisecond: 0 
    });
    
    // Track earliest past-due incomplete schedule for "running late" detection
    if (!isCompleted && todayTime <= nowInZone) {
      if (!earliestPastDueToday || todayTime < earliestPastDueToday) {
        earliestPastDueToday = todayTime;
      }
    }
    
    // Track next future schedule today that's not completed
    if (!isCompleted && todayTime > nowInZone) {
      if (!nextPendingToday || todayTime < nextPendingToday) {
        nextPendingToday = todayTime;
      }
    }
    
    const tomorrowTime = tomorrowInZone.set({ 
      hour: parsed.hours, 
      minute: parsed.minutes, 
      second: 0, 
      millisecond: 0 
    });
    
    if (!earliestTomorrow || tomorrowTime < earliestTomorrow) {
      earliestTomorrow = tomorrowTime;
    }
  }
  
  // Priority: 
  // 1. Next pending future today
  // 2. Past-due incomplete (for "running late" detection)
  // 3. Earliest tomorrow (if all today's schedules are done or no schedules today)
  let result;
  if (nextPendingToday) {
    result = nextPendingToday;
  } else if (earliestPastDueToday) {
    result = earliestPastDueToday;
  } else {
    // All today's schedules done OR no past-due schedules - go to tomorrow
    result = earliestTomorrow;
  }
  
  return result ? result.toJSDate() : null;
}

/**
 * Get list of schedule times that have passed but are not yet completed
 * Used for multi check-in tracking
 * @param {Array<string>} schedules - All scheduled times
 * @param {Array<string>} completedSchedules - Already completed schedules
 * @param {Date} now - Current time
 * @param {string} userTimezone - User's timezone
 * @returns {Array<string>} - List of pending past-due schedules
 */
function getPendingSchedules(schedules, completedSchedules, now, userTimezone) {
  const effectiveSchedules = schedules?.length ? schedules : ["11:00 AM"];
  const tz = userTimezone && typeof userTimezone === 'string' && userTimezone.trim() 
    ? userTimezone.trim() 
    : TIMEZONE;
  
  const nowInZone = DateTime.fromJSDate(now, { zone: tz });
  const completedSet = new Set(
    (completedSchedules || []).map(s => s.toUpperCase().trim())
  );
  
  const pending = [];
  
  for (const schedule of effectiveSchedules) {
    const normalizedSchedule = schedule.toUpperCase().trim();
    
    // Skip if already completed
    if (completedSet.has(normalizedSchedule)) continue;
    
    const parsed = parseScheduleToTime(schedule);
    if (!parsed) continue;
    
    const scheduleTime = nowInZone.set({ 
      hour: parsed.hours, 
      minute: parsed.minutes, 
      second: 0, 
      millisecond: 0 
    });
    
    // If schedule time has passed, it's pending
    if (nowInZone >= scheduleTime) {
      pending.push(normalizedSchedule);
    }
  }
  
  return pending;
}

/**
 * Get user timezone from their profile document
 * @param {string} userId - User's ID
 * @returns {Promise<string|null>} - User's timezone or null if not set
 */
async function getUserTimezone(userId) {
  try {
    const profileDoc = await db.collection("users").doc(userId)
      .collection("data").doc("profile").get();
    
    if (!profileDoc.exists) return null;
    
    const data = profileDoc.data();
    return data?.timezone || null;
  } catch (error) {
    logger.error(`Error fetching timezone for user ${userId}:`, { error: error.message });
    return null;
  }
}

/**
 * Format a Date to schedule string for display
 */
function formatTimeToSchedule(date) {
  if (!date) return "11:00 AM";
  let hours = date.getHours();
  const minutes = date.getMinutes();
  const period = hours >= 12 ? "PM" : "AM";
  if (hours > 12) hours -= 12;
  if (hours === 0) hours = 12;
  return `${hours}:${String(minutes).padStart(2, "0")} ${period}`;
}

/**
 * Generate a deterministic document ID for missed check-in idempotency
 */
function getMissedCheckInKey(userId, schedule, date) {
  const dateStr = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  return `missed_${userId}_${schedule.replace(/[^a-zA-Z0-9]/g, "")}_${dateStr}`;
}

/**
 * Check if a missed check-in was already logged for a specific schedule time
 * Used for idempotency to prevent duplicate alerts
 * @param {string} userId - User ID
 * @param {string} scheduleStr - Schedule string (e.g., "6:45 PM")
 * @param {Date} date - The date to check
 * @returns {Promise<boolean>} - True if already logged
 */
async function checkMissedCheckInLogged(userId, scheduleStr, date) {
  const docId = getMissedCheckInKey(userId, scheduleStr, date);
  const activityRef = db.collection("users").doc(userId).collection("activityLogs").doc(docId);
  const doc = await activityRef.get();
  return doc.exists;
}

/**
 * Find the next future schedule time (for Cloud Task scheduling)
 * Unlike calculateNextExpectedCheckIn which returns earliest missed for UI,
 * this returns only schedules that are still in the future
 * @param {Array<string>} schedules - Check-in schedule times
 * @param {Date} now - Current time
 * @param {string|null} userTimezone - User's IANA timezone
 * @returns {Date|null} - Next future schedule time, or null if none today
 */
function findNextFutureSchedule(schedules, now, userTimezone = null) {
  const effectiveSchedules = schedules?.length ? schedules : ["11:00 AM"];
  const tz = userTimezone && typeof userTimezone === 'string' && userTimezone.trim() 
    ? userTimezone.trim() 
    : TIMEZONE;
  
  const nowInZone = DateTime.fromJSDate(now, { zone: tz });
  
  logger.info(`findNextFutureSchedule DEBUG:`, {
    schedules: effectiveSchedules,
    rawNow: now.toISOString(),
    timezone: tz,
    nowInZone: nowInZone.toISO(),
  });
  
  let nextFuture = null;
  let earliestTomorrow = null;
  const tomorrowInZone = nowInZone.plus({ days: 1 });
  
  for (const schedule of effectiveSchedules) {
    const parsed = parseScheduleToTime(schedule);
    
    logger.info(`findNextFutureSchedule - parsing schedule "${schedule}":`, {
      parsed: parsed ? JSON.stringify(parsed) : 'null (PARSE FAILED)',
    });
    
    if (!parsed) continue;
    
    const todayTime = nowInZone.set({ 
      hour: parsed.hours, 
      minute: parsed.minutes, 
      second: 0, 
      millisecond: 0 
    });
    
    const isFuture = todayTime > nowInZone;
    logger.info(`findNextFutureSchedule - time comparison:`, {
      schedule,
      todayTimeISO: todayTime.toISO(),
      nowInZoneISO: nowInZone.toISO(),
      isFuture,
      diffMs: todayTime.toMillis() - nowInZone.toMillis(),
    });
    
    // Only consider future times for task scheduling
    if (isFuture) {
      if (!nextFuture || todayTime < nextFuture) {
        nextFuture = todayTime;
      }
    }
    
    const tomorrowTime = tomorrowInZone.set({ 
      hour: parsed.hours, 
      minute: parsed.minutes, 
      second: 0, 
      millisecond: 0 
    });
    
    if (!earliestTomorrow || tomorrowTime < earliestTomorrow) {
      earliestTomorrow = tomorrowTime;
    }
  }
  
  // Return next future today, or earliest tomorrow if no future today
  const result = nextFuture || earliestTomorrow;
  
  logger.info(`findNextFutureSchedule - result:`, {
    nextFuture: nextFuture?.toISO() || 'null',
    earliestTomorrow: earliestTomorrow?.toISO() || 'null',
    finalResult: result?.toISO() || 'null',
  });
  
  return result ? result.toJSDate() : null;
}

/**
 * Get the full Cloud Tasks queue path
 */
function getQueuePath() {
  return tasksClient.queuePath(PROJECT_ID, CLOUD_TASKS_LOCATION, CLOUD_TASKS_QUEUE);
}

/**
 * Create a Cloud Task for a scheduled check-in
 * @param {string} userId - Senior's user ID
 * @param {Date} scheduledTime - When to execute (should include grace period)
 * @param {string} userTimezone - User's timezone
 * @returns {Promise<string|null>} - Task name if created, null on failure
 */
async function createCloudTask(userId, scheduledTime, userTimezone) {
  const queuePath = getQueuePath();
  
  // Calculate execution time with grace period
  const executeAt = new Date(scheduledTime.getTime() + GRACE_PERIOD_MINUTES * 60 * 1000);
  
  // Task payload
  const payload = {
    userId,
    scheduledTime: scheduledTime.toISOString(),
    createdAt: new Date().toISOString(),
    timezone: userTimezone || TIMEZONE,
  };

  // Get the function URL for handleMissedCheckIn
  const functionUrl = `https://${CLOUD_TASKS_LOCATION}-${PROJECT_ID}.cloudfunctions.net/handleMissedCheckIn`;

  const task = {
    httpRequest: {
      httpMethod: "POST",
      url: functionUrl,
      headers: {
        "Content-Type": "application/json",
      },
      body: Buffer.from(JSON.stringify(payload)).toString("base64"),
      oidcToken: {
        serviceAccountEmail: `${PROJECT_ID}@appspot.gserviceaccount.com`,
      },
    },
    scheduleTime: {
      seconds: Math.floor(executeAt.getTime() / 1000),
    },
  };

  // Retry with exponential backoff (3 attempts: 1s, 2s, 4s delays)
  const maxAttempts = 3;
  let lastError = null;
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const [response] = await tasksClient.createTask({
        parent: queuePath,
        task,
      });

      logger.info(`Created Cloud Task for user ${userId}`, { 
        taskName: response.name,
        scheduledTime: scheduledTime.toISOString(),
        executeAt: executeAt.toISOString(),
        attempt,
      });

      return response.name;
    } catch (error) {
      lastError = error;
      
      // Only retry on transient errors
      const isTransient = error.code === 14 || // UNAVAILABLE
                         error.code === 4 ||  // DEADLINE_EXCEEDED
                         error.message?.includes("UNAVAILABLE");
      
      if (!isTransient || attempt === maxAttempts) {
        logger.error(`Error creating Cloud Task for user ${userId} (attempt ${attempt}/${maxAttempts}):`, { 
          error: error.message,
          code: error.code,
        });
        break;
      }
      
      // Exponential backoff: 1s, 2s, 4s
      const delay = Math.pow(2, attempt - 1) * 1000;
      logger.warn(`Retrying Cloud Task creation for user ${userId} (attempt ${attempt}/${maxAttempts}), waiting ${delay}ms`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
  
  return null;
}

/**
 * Cancel an existing Cloud Task
 * @param {string} taskName - Full task name/path
 * @returns {Promise<boolean>} - True if cancelled or not found, false on error
 */
async function cancelCloudTask(taskName) {
  if (!taskName) return true;
  
  try {
    await tasksClient.deleteTask({ name: taskName });
    logger.info(`Cancelled Cloud Task: ${taskName}`);
    return true;
  } catch (error) {
    // Task may have already executed or been deleted
    if (error.code === 5) { // NOT_FOUND
      logger.info(`Task already gone: ${taskName}`);
      return true;
    }
    logger.error(`Error cancelling Cloud Task:`, { taskName, error: error.message });
    return false;
  }
}

/**
 * Schedule or reschedule a check-in task for a user
 * Uses transaction to prevent race conditions
 * 
 * IMPORTANT: This function ONLY handles Cloud Task scheduling.
 * It does NOT update nextExpectedCheckIn - that is handled by the Dart client
 * to avoid race conditions where this function overwrites Dart's value.
 */
async function scheduleCheckInTask(userId) {
  const seniorStateRef = db.collection("users").doc(userId).collection("data").doc("seniorState");
  
  try {
    // ========== PHASE 1: Read state outside transaction ==========
    const initialDoc = await seniorStateRef.get();
    
    if (!initialDoc.exists) {
      logger.info(`No senior state for user ${userId}, skipping task scheduling`);
      return;
    }
    
    const initialData = initialDoc.data();
    const initialVacationMode = initialData.vacationMode;
    const initialActiveTaskId = initialData.activeTaskId;
    const schedules = initialData.checkInSchedules || ["11:00 AM"];
    
    // ========== PHASE 2: External I/O outside transaction ==========
    // Cancel existing task if any (safe to do before transaction)
    if (initialActiveTaskId) {
      await cancelCloudTask(initialActiveTaskId);
    }
    
    // If vacation mode is on, just clear the task ID in a transaction
    if (initialVacationMode) {
      logger.info(`User ${userId} is on vacation, skipping task scheduling`);
      await db.runTransaction(async (transaction) => {
        const doc = await transaction.get(seniorStateRef);
        if (!doc.exists) return;
        const data = doc.data();
        
        // Only delete activeTaskId if it still matches what we cancelled
        if (data.activeTaskId === initialActiveTaskId) {
          transaction.update(seniorStateRef, {
            activeTaskId: FieldValue.delete(),
          });
        }
      });
      return;
    }
    
    // Get user timezone (external I/O)
    const userTimezone = await getUserTimezone(userId);
    const now = new Date();
    
    logger.info(`DEBUG: scheduleCheckInTask for user ${userId}`, {
      schedules,
      now: now.toISOString(),
      userTimezone,
      existingNextExpected: initialData.nextExpectedCheckIn?.toDate?.()?.toISOString(),
    });
    
    // Find next FUTURE schedule for Cloud Task (only future times)
    const nextTaskTime = findNextFutureSchedule(schedules, now, userTimezone);
    
    if (!nextTaskTime) {
      logger.info(`No future schedule for user ${userId}, clearing activeTaskId`);
      await db.runTransaction(async (transaction) => {
        const doc = await transaction.get(seniorStateRef);
        if (!doc.exists) return;
        const data = doc.data();
        
        // Only clear if activeTaskId matches what we cancelled
        if (data.activeTaskId === initialActiveTaskId || !data.activeTaskId) {
          transaction.update(seniorStateRef, {
            activeTaskId: FieldValue.delete(),
          });
        }
      });
      return;
    }
    
    // Create Cloud Task (external I/O - do BEFORE transaction)
    const taskName = await createCloudTask(userId, nextTaskTime, userTimezone);
    
    // ========== PHASE 3: Short transaction to validate & update atomically ==========
    let taskNeedsCleanup = false;
    
    await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(seniorStateRef);
      
      if (!doc.exists) {
        // State was deleted, mark task for cleanup
        taskNeedsCleanup = true;
        return;
      }
      
      const data = doc.data();
      
      // Validate state hasn't changed in a way that invalidates our work
      if (data.vacationMode) {
        // Vacation mode was enabled after we started, cleanup required
        taskNeedsCleanup = true;
        transaction.update(seniorStateRef, {
          activeTaskId: FieldValue.delete(),
        });
        return;
      }
      
      // Check if schedules changed (would require different task time)
      const currentSchedules = data.checkInSchedules || ["11:00 AM"];
      if (JSON.stringify(currentSchedules) !== JSON.stringify(schedules)) {
        // Schedules changed, cleanup and let next invocation handle it
        taskNeedsCleanup = true;
        return;
      }
      
      // All good - atomically update activeTaskId
      transaction.update(seniorStateRef, {
        activeTaskId: taskName || FieldValue.delete(),
      });
      
      logger.info(`Scheduled Cloud Task for user ${userId}`, {
        nextTaskTime: nextTaskTime.toISOString(),
        taskName,
      });
    });
    
    // ========== PHASE 4: Compensating cleanup if needed ==========
    if (taskNeedsCleanup && taskName) {
      logger.info(`Cleaning up orphaned task due to state change: ${taskName}`);
      await cancelCloudTask(taskName);
    }
    
  } catch (error) {
    logger.error(`Error scheduling check-in task for user ${userId}:`, { error: error.message });
  }
}

/**
 * Send FCM push notification to senior for missed check-in
 * @param {string} userId - Senior's user ID  
 * @param {number} missedCount - Number of missed check-ins today
 */
async function sendMissedCheckInNotification(userId, missedCount) {
  try {
    // Get user's FCM token from profile
    const profileDoc = await db.collection("users").doc(userId)
      .collection("data").doc("profile").get();
    
    if (!profileDoc.exists) {
      logger.info(`No profile found for user ${userId}, skipping FCM`);
      return;
    }
    
    const fcmToken = profileDoc.data()?.fcmToken;
    if (!fcmToken) {
      logger.info(`No FCM token for user ${userId}, skipping push notification`);
      return;
    }
    
    // Build notification based on missed count
    const title = missedCount === 1 
      ? "Check-in Reminder (FCM)"
      : "Multiple Missed Check-ins (FCM)";
    
    const body = missedCount === 1
      ? "You haven't checked in yet today. Tap to let your family know you're okay!"
      : `You've missed ${missedCount} check-ins today. Tap to check in now.`;
    
    // Send FCM message
    const message = {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: {
        type: "missed_checkin",
        missedCount: String(missedCount),
        source: "server",
        timestamp: new Date().toISOString(),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "check_in_reminders",
          priority: "high",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: missedCount,
          },
        },
      },
    };
    
    const response = await getMessaging().send(message);
    logger.info(`FCM sent for user ${userId}`, { messageId: response, missedCount });
    
  } catch (error) {
    // Handle invalid token errors gracefully
    if (error.code === "messaging/invalid-registration-token" ||
        error.code === "messaging/registration-token-not-registered") {
      logger.warn(`Invalid FCM token for user ${userId}, clearing token`);
      // Clear invalid token
      try {
        await db.collection("users").doc(userId)
          .collection("data").doc("profile")
          .update({ fcmToken: FieldValue.delete() });
      } catch (clearError) {
        logger.error("Error clearing invalid token:", { error: clearError.message });
      }
    } else {
      logger.error(`Error sending FCM for user ${userId}:`, { error: error.message });
    }
  }
}

/**
 * HTTP Handler: Called by Cloud Tasks when check-in time passes
 */
exports.handleMissedCheckIn = onRequest({
  region: CLOUD_TASKS_LOCATION,
  timeoutSeconds: 60,
  memory: "256MiB",
}, async (req, res) => {
  // Validate request
  if (req.method !== "POST") {
    res.status(405).send("Method not allowed");
    return;
  }
  
  let payload;
  try {
    payload = req.body;
    if (typeof payload === "string") {
      payload = JSON.parse(payload);
    }
  } catch (error) {
    logger.error("Invalid request payload:", { error: error.message });
    res.status(400).send("Invalid payload");
    return;
  }
  
  const { userId, scheduledTime, createdAt, timezone } = payload;
  
  if (!userId || !scheduledTime) {
    logger.error("Missing required fields:", { userId, scheduledTime });
    res.status(400).send("Missing required fields");
    return;
  }
  
  logger.info(`Handling missed check-in for user ${userId}`, { scheduledTime, createdAt });
  
  const seniorStateRef = db.collection("users").doc(userId).collection("data").doc("seniorState");
  const now = new Date();
  
  try {
    // Capture missedCount from transaction for FCM notification
    const missedCount = await db.runTransaction(async (transaction) => {
      const seniorStateDoc = await transaction.get(seniorStateRef);
      
      if (!seniorStateDoc.exists) {
        logger.info(`Senior state not found for user ${userId}`);
        return null; // Explicit null return for no action
      }
      
      const data = seniorStateDoc.data();
      
      // Check if vacation mode was enabled after task creation
      if (data.vacationMode) {
        logger.info(`User ${userId} is now on vacation, skipping missed check-in`);
        return null;
      }
      
      // TOCTOU check: Did user check in between task creation and now?
      const lastCheckIn = data.lastCheckIn?.toDate?.();
      const taskCreatedAt = new Date(createdAt);
      
      if (lastCheckIn && lastCheckIn > taskCreatedAt) {
        logger.info(`User ${userId} checked in after task creation, not a miss`);
        return null;
      }
      
      // Also check if checked in today (same day as scheduled time)
      const scheduledDateTime = new Date(scheduledTime);
      if (lastCheckIn) {
        const tz = timezone || TIMEZONE;
        const lastCheckInLuxon = DateTime.fromJSDate(lastCheckIn, { zone: tz });
        const scheduledLuxon = DateTime.fromJSDate(scheduledDateTime, { zone: tz });
        
        if (lastCheckInLuxon.hasSame(scheduledLuxon, "day")) {
          logger.info(`User ${userId} already checked in today`);
          return null;
        }
      }
      
      // Day 1 check: Skip ONLY if account was created today AND using only default schedule
      // If user adds custom schedules on Day 1, those SHOULD work normally
      const seniorCreatedAt = data.seniorCreatedAt?.toDate?.();
      const schedules = data.checkInSchedules || ["11:00 AM"];
      const hasOnlyDefaultSchedule = schedules.length === 1 && 
          schedules[0].toUpperCase() === "11:00 AM";
      
      if (seniorCreatedAt && hasOnlyDefaultSchedule) {
        const tz = timezone || TIMEZONE;
        const createdLuxon = DateTime.fromJSDate(seniorCreatedAt, { zone: tz });
        const nowLuxon = DateTime.fromJSDate(now, { zone: tz });
        
        if (createdLuxon.hasSame(nowLuxon, "day")) {
          logger.info(`User ${userId} is on day 1 with default schedule only, skipping missed check-in`);
          // Still schedule for tomorrow
          return null;
        }
      }
      
      // This is a genuine missed check-in
      const missedSchedule = formatTimeToSchedule(scheduledDateTime);
      // Use scheduledDateTime for idempotency key (not 'now') to prevent duplicate logs across day boundaries
      const docId = getMissedCheckInKey(userId, missedSchedule, scheduledDateTime);
      
      // Check if we already logged this miss (idempotency)
      const activityRef = db.collection("users").doc(userId).collection("activityLogs").doc(docId);
      const existingLog = await transaction.get(activityRef);
      
      if (existingLog.exists) {
        logger.info(`Missed check-in already logged for user ${userId}`);
        return null;
      }
      
      // Log the missed check-in
      transaction.set(activityRef, {
        seniorId: userId,
        activityType: "missed_check_in",
        timestamp: Timestamp.now(),
        isAlert: true,
        metadata: {
          scheduledTime: missedSchedule,
          detectedAt: now.toISOString(),
        },
      });
      
      // Increment consecutive missed days
      const currentConsecutive = data.consecutiveMissedDays || 0;
      const newConsecutive = currentConsecutive + 1;
      
      // Update senior state
      const updates = {
        consecutiveMissedDays: newConsecutive,
        lastMissedCheckIn: Timestamp.now(),
        missedCheckInsToday: FieldValue.increment(1),
        activeTaskId: FieldValue.delete(), // Task completed
      };
      
      transaction.update(seniorStateRef, updates);
      
      logger.info(`Logged missed check-in for user ${userId}`, {
        consecutiveMissedDays: newConsecutive,
        missedSchedule,
      });
      
      // Compute missedCount for FCM notification
      const computedMissedCount = (data.missedCheckInsToday || 0) + 1;
      
      // Check for escalation
      if (newConsecutive >= ESCALATION_THRESHOLD_DAYS) {
        const lastEscalation = data.lastEscalationNotificationAt?.toDate?.();
        const hoursSinceLastEscalation = lastEscalation 
          ? (now.getTime() - lastEscalation.getTime()) / (1000 * 60 * 60)
          : Infinity;
        
        // Rate limit: max once per 24 hours
        if (hoursSinceLastEscalation >= 24) {
          logger.warn(`ESCALATION: User ${userId} has missed ${newConsecutive} consecutive days!`);
          
          // TODO: Send push notification / SMS
          // For now, just log and update timestamp
          transaction.update(seniorStateRef, {
            lastEscalationNotificationAt: Timestamp.now(),
          });
          
          // Log escalation activity
          const escalationRef = db.collection("users").doc(userId)
            .collection("activityLogs").doc();
          transaction.set(escalationRef, {
            seniorId: userId,
            activityType: "escalation_triggered",
            timestamp: Timestamp.now(),
            isAlert: true,
            metadata: {
              consecutiveMissedDays: newConsecutive,
              reason: `Missed ${newConsecutive} consecutive check-ins`,
            },
          });
        }
      }
      
      // Return missedCount for FCM notification (now properly captured outside)
      return computedMissedCount;
    });
    
    // Send FCM push notification outside transaction (non-blocking)
    if (missedCount != null && missedCount > 0) {
      try {
        // 1. Notify the Senior
        await sendMissedCheckInNotification(userId, missedCount);
        
        // 2. Notify Linked Family Members
        // Use top-level connections collection (same pattern as onSOSTriggered)
        // This ensures consistent lookup across all notification types
        const connectionsSnapshot = await db.collection("connections")
          .where("seniorId", "==", userId)
          .where("status", "==", "active")
          .get();
          
        if (!connectionsSnapshot.empty) {
          const familyNotificationPromises = connectionsSnapshot.docs.map(async (doc) => {
            const connectionData = doc.data();
            const familyUserId = connectionData.familyId;
            // Get family user's FCM token from correct subcollection path
            const familyProfileDoc = await db.collection("users")
              .doc(familyUserId)
              .collection("data")
              .doc("profile")
              .get();
              
            const familyData = familyProfileDoc.data();
            const familyFcmToken = familyData?.fcmToken;
            
            if (familyFcmToken) {
              return admin.messaging().send({
                token: familyFcmToken,
                notification: {
                  title: "Missed Check-in Alert (FCM)",
                  body: "Your senior has missed a scheduled check-in. Please check on them.",
                },
                data: {
                  type: "family_missed_alert",
                  seniorUserId: userId,
                  missedCount: String(missedCount),
                  click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                android: {
                  priority: "high",
                  notification: {
                    channelId: "high_importance_channel",
                    priority: "max",
                    visibility: "public",
                  },
                },
                apns: {
                  payload: {
                    aps: {
                      sound: "default",
                      "content-available": 1,
                    },
                  },
                },
              });
            } else {
               logger.warn(`No FCM token found for family user ${familyUserId}`);
            }
          });
          
          await Promise.allSettled(familyNotificationPromises);
          logger.info(`Sent family notifications for user ${userId}`);
        }
        
      } catch (fcmError) {
        // Log but don't fail the request - FCM is best-effort
        logger.error(`FCM notification failed for user ${userId}:`, { error: fcmError.message });
      }
    }
    
    // Schedule next day's task (outside transaction for simplicity)
    await scheduleCheckInTask(userId);
    
    res.status(200).send("OK");
  } catch (error) {
    logger.error(`Error handling missed check-in for user ${userId}:`, { error: error.message });
    res.status(500).send("Internal error");
  }
});

/**
 * TRIGGER: Sync seniorState changes to top-level collection
 * Also schedules/cancels Cloud Tasks based on state changes
 */
exports.syncSeniorStateToTopLevel = onDocumentWritten({
  document: "users/{userId}/data/seniorState",
  region: "us-central1",
}, async (event) => {
  const userId = event.params.userId;
  const topLevelRef = db.collection("seniorStates").doc(userId);
  
  // Document deleted
  if (!event.data?.after?.exists) {
    await topLevelRef.delete().catch(() => {});
    
    // Cancel any pending task
    const beforeData = event.data?.before?.data?.();
    if (beforeData?.activeTaskId) {
      await cancelCloudTask(beforeData.activeTaskId);
    }
    
    logger.info(`Deleted seniorStates/${userId}`);
    return;
  }
  
  const data = event.data.after.data();
  const beforeData = event.data?.before?.data?.() || {};
  
  // Sync to top-level collection
  await topLevelRef.set({
    nextExpectedCheckIn: data.nextExpectedCheckIn || null,
    vacationMode: data.vacationMode || false,
    lastCheckIn: data.lastCheckIn || null,
    checkInSchedules: data.checkInSchedules || ["11:00 AM"],
    seniorCreatedAt: data.seniorCreatedAt || null,
    missedCheckInsToday: data.missedCheckInsToday || 0,
    consecutiveMissedDays: data.consecutiveMissedDays || 0,
    updatedAt: Timestamp.now(),
  }, { merge: true });
  
  // Detect schedule changes that require task rescheduling
  const schedulesChanged = JSON.stringify(data.checkInSchedules) !== JSON.stringify(beforeData.checkInSchedules);
  const vacationToggled = data.vacationMode !== beforeData.vacationMode;
  const newSenior = !event.data?.before?.exists && data.checkInSchedules?.length > 0;
  
  if (schedulesChanged || vacationToggled || newSenior) {
    if (data.vacationMode) {
      // Cancel task when vacation mode enabled
      if (data.activeTaskId) {
        await cancelCloudTask(data.activeTaskId);
        await db.collection("users").doc(userId)
          .collection("data").doc("seniorState")
          .update({ activeTaskId: FieldValue.delete() });
      }
    } else {
      // Schedule new task
      await scheduleCheckInTask(userId);
    }
  }
  
  logger.info(`Synced seniorStates/${userId}`);
});

/**
 * TRIGGER: Update nextExpectedCheckIn when a check-in is recorded
 * Cancels pending task and schedules new one for next day
 */
exports.onCheckInRecorded = onDocumentWritten({
  document: "users/{userId}/checkIns/{checkInId}",
  region: "us-central1",
}, async (event) => {
  if (!event.data?.after?.exists || event.data?.before?.exists) {
    return;
  }
  
  const userId = event.params.userId;
  const checkInData = event.data.after.data();
  const checkInTime = checkInData.timestamp?.toDate?.() || new Date();
  
  logger.info(`Check-in recorded for user ${userId}, rescheduling task`);
  
  const seniorStateRef = db.collection("users").doc(userId)
    .collection("data").doc("seniorState");
  
  try {
    // Fetch user timezone for timezone-aware calculations (external I/O outside transaction)
    const userTimezone = await getUserTimezone(userId);
    
    // ========== Read state and cancel task OUTSIDE transaction ==========
    const initialDoc = await seniorStateRef.get();
    
    if (initialDoc.exists) {
      const initialState = initialDoc.data();
      // Cancel existing task outside transaction (external I/O)
      if (initialState.activeTaskId) {
        await cancelCloudTask(initialState.activeTaskId);
      }
    }
    
    // ========== Short transaction: re-read, validate, and update atomically ==========
    await db.runTransaction(async (transaction) => {
      const seniorStateDoc = await transaction.get(seniorStateRef);
      
      if (!seniorStateDoc.exists) return;
      
      const seniorState = seniorStateDoc.data();
      
      const schedules = seniorState.checkInSchedules || ["11:00 AM"];
      const completedToday = seniorState.completedSchedulesToday || [];
      
      // Pass completedSchedulesToday for multi check-in support
      const nextExpected = calculateNextExpectedCheckIn(
        schedules, 
        new Date(), 
        checkInTime, 
        userTimezone,
        completedToday
      );
      
      // Reset consecutive missed days on successful check-in
      transaction.update(seniorStateRef, {
        nextExpectedCheckIn: nextExpected ? Timestamp.fromDate(nextExpected) : FieldValue.delete(),
        lastCheckIn: Timestamp.fromDate(checkInTime),
        consecutiveMissedDays: 0, // Reset streak
        activeTaskId: FieldValue.delete(), // Will be set by scheduleCheckInTask
      });
      
      logger.info(`Updated nextExpectedCheckIn for ${userId}: ${nextExpected?.toISOString()}, completedSchedules: ${completedToday.length}`);
    });
    
    // Schedule task for next check-in (outside transaction)
    await scheduleCheckInTask(userId);
    
  } catch (error) {
    logger.error(`Error updating check-in for ${userId}:`, { error: error.message });
  }
});

/**
 * SCHEDULED: Reset daily counters at midnight
 */
exports.resetDailyCounters = onRequest({
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "256MiB",
}, async (req, res) => {
  // This can be called via Cloud Scheduler as a simple HTTP trigger
  const startTime = Date.now();
  logger.info("Starting daily counter reset");

  let resetCount = 0;
  let batch = db.batch();
  let batchCount = 0;

  try {
    // Query top-level collection for seniors with missed check-ins
    const snapshot = await db.collection("seniorStates")
      .where("missedCheckInsToday", ">", 0)
      .get();

    for (const doc of snapshot.docs) {
      const userId = doc.id;
      const seniorStateRef = db.collection("users").doc(userId)
        .collection("data").doc("seniorState");
      
      // Reset missed check-ins AND completedSchedulesToday for new day
      batch.update(seniorStateRef, { 
        missedCheckInsToday: 0,
        completedSchedulesToday: [],
        lastScheduleResetDate: Timestamp.now(),
      });
      batchCount++;
      resetCount++;

      if (batchCount >= BATCH_SIZE) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    const duration = Date.now() - startTime;
    logger.info("Daily counter reset completed", { resetCount, durationMs: duration });
    
    res.status(200).json({ resetCount, durationMs: duration });

  } catch (error) {
    logger.error("Error in resetDailyCounters:", { error: error.message });
    res.status(500).send("Internal error");
  }
});

/**
 * SOS Alert Trigger
 * Sends FCM push notification to all connected family members when senior triggers SOS
 * Includes 5-minute cooldown to prevent duplicate notifications
 */
exports.onSOSTriggered = onDocumentWritten({
  document: "users/{userId}/data/seniorState",
  region: "us-central1",
}, async (event) => {
  const beforeData = event.data?.before?.data() || {};
  const afterData = event.data?.after?.data() || {};
  
  // Only trigger when sosActive changes from false to true
  const wasActive = beforeData.sosActive === true;
  const isActive = afterData.sosActive === true;
  
  if (wasActive || !isActive) {
    // SOS was not just triggered (either was already active, or is now inactive)
    return;
  }
  
  const userId = event.params.userId;
  logger.info(`SOS triggered by user ${userId}`);
  
  // Check cooldown - don't send notification if one was sent within 5 minutes
  const sosTriggeredAt = afterData.sosTriggeredAt?.toDate?.();
  const prevTriggeredAt = beforeData.sosTriggeredAt?.toDate?.();
  
  if (sosTriggeredAt && prevTriggeredAt) {
    const diffMs = sosTriggeredAt.getTime() - prevTriggeredAt.getTime();
    const cooldownMs = 1 * 60 * 1000; // 1 minute (matches client-side cooldown)
    
    if (diffMs < cooldownMs) {
      logger.info(`SOS cooldown active for user ${userId}, skipping notification`, {
        diffMs,
        cooldownMs
      });
      return;
    }
  }
  
  try {
    // Get senior's display name
    const profileDoc = await db.collection("users").doc(userId)
      .collection("data").doc("profile").get();
    
    const seniorName = profileDoc.exists 
      ? (profileDoc.data()?.displayName || "Your family member")
      : "Your family member";
    
    // Find all family members connected to this senior
    const connectionsSnapshot = await db.collection("connections")
      .where("seniorId", "==", userId)
      .where("status", "==", "active")
      .get();
    
    if (connectionsSnapshot.empty) {
      logger.info(`No active family connections for user ${userId}`);
      return;
    }
    
    // Collect family member IDs
    const familyIds = connectionsSnapshot.docs.map(doc => doc.data().familyId);
    logger.info(`Found ${familyIds.length} family members to notify`);
    
    // Get FCM tokens for all family members
    const tokens = [];
    for (const familyId of familyIds) {
      try {
        const familyProfileDoc = await db.collection("users").doc(familyId)
          .collection("data").doc("profile").get();
        
        if (familyProfileDoc.exists) {
          const fcmToken = familyProfileDoc.data()?.fcmToken;
          if (fcmToken) {
            tokens.push(fcmToken);
          }
        }
      } catch (error) {
        logger.warn(`Error fetching FCM token for family ${familyId}:`, { error: error.message });
      }
    }
    
    if (tokens.length === 0) {
      logger.info(`No FCM tokens found for family members of user ${userId}`);
      return;
    }
    
    // Send FCM notification to all family members
    const message = {
      tokens,
      notification: {
        title: "🚨 SOS Alert! (FCM)",
        body: `${seniorName} needs help! Tap to respond.`,
      },
      data: {
        type: "sos_alert",
        seniorId: userId,
        seniorName,
        source: "server",
        timestamp: new Date().toISOString(),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "sos_alerts",
          priority: "max",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            alert: {
              title: "🚨 SOS Alert! (FCM)",
              body: `${seniorName} needs help! Tap to respond.`,
            },
          },
        },
        headers: {
          "apns-priority": "10",
        },
      },
    };
    
    const response = await getMessaging().sendEachForMulticast(message);
    logger.info(`SOS FCM sent for user ${userId}`, {
      successCount: response.successCount,
      failureCount: response.failureCount,
    });
    
    // Handle any failures
    if (response.failureCount > 0) {
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          logger.warn(`FCM send failed for token ${idx}:`, { error: resp.error?.message });
        }
      });
    }
    
  } catch (error) {
    logger.error(`Error handling SOS for user ${userId}:`, { error: error.message });
  }
});
