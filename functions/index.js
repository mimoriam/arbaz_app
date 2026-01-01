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
const logger = require("firebase-functions/logger");
const { DateTime } = require("luxon");
const { CloudTasksClient } = require("@google-cloud/tasks");

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

// Initialize Firebase Admin
initializeApp();
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
    
    let normalized = schedule.trim().toUpperCase().replace(/\s+/g, " ");
    normalized = normalized.replace(/(AM|PM)$/i, " $1").trim();
    
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
 * @param {Array<string>} schedules - Check-in schedule times
 * @param {Date} now - Current time
 * @param {Date|null} lastCheckIn - Last check-in time
 * @param {string|null} userTimezone - User's IANA timezone (optional, defaults to TIMEZONE constant)
 * @returns {Date|null} - JS Date object for caller compatibility
 */
function calculateNextExpectedCheckIn(schedules, now, lastCheckIn, userTimezone = null) {
  const effectiveSchedules = schedules?.length ? schedules : ["11:00 AM"];
  
  // Use user's timezone if provided, otherwise fall back to default
  const tz = userTimezone && typeof userTimezone === 'string' && userTimezone.trim() 
    ? userTimezone.trim() 
    : TIMEZONE;
  
  // Convert to timezone-aware DateTime
  const nowInZone = DateTime.fromJSDate(now, { zone: tz });
  const lastCheckInInZone = lastCheckIn 
    ? DateTime.fromJSDate(lastCheckIn, { zone: tz }) 
    : null;
  
  // Check if checked in today using timezone-aware comparison
  const checkedInToday = lastCheckInInZone && 
    nowInZone.hasSame(lastCheckInInZone, "day");

  if (checkedInToday) {
    // Find earliest schedule tomorrow
    const tomorrowInZone = nowInZone.plus({ days: 1 });
    
    let earliest = null;
    for (const schedule of effectiveSchedules) {
      const parsed = parseScheduleToTime(schedule);
      if (!parsed) continue;
      
      const scheduleTime = tomorrowInZone.set({ 
        hour: parsed.hours, 
        minute: parsed.minutes, 
        second: 0, 
        millisecond: 0 
      });
      
      if (!earliest || scheduleTime < earliest) {
        earliest = scheduleTime;
      }
    }
    return earliest ? earliest.toJSDate() : null;
  }

  // Find next schedule today or tomorrow
  // Also track earliest today (even if passed) for "running late" detection
  let nextToday = null;
  let earliestToday = null; // For "running late" detection
  let earliestTomorrow = null;
  const tomorrowInZone = nowInZone.plus({ days: 1 });
  
  for (const schedule of effectiveSchedules) {
    const parsed = parseScheduleToTime(schedule);
    if (!parsed) continue;
    
    const todayTime = nowInZone.set({ 
      hour: parsed.hours, 
      minute: parsed.minutes, 
      second: 0, 
      millisecond: 0 
    });
    
    // Track earliest schedule for today (even if passed - for running late detection)
    if (!earliestToday || todayTime < earliestToday) {
      earliestToday = todayTime;
    }
    
    if (todayTime > nowInZone) {
      if (!nextToday || todayTime < nextToday) {
        nextToday = todayTime;
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
  
  // If there's an upcoming schedule today, use it
  // Otherwise, if all today's schedules have passed, return earliest today for "running late" detection
  // Only fall back to tomorrow if there are no schedules today at all
  const result = nextToday || earliestToday || earliestTomorrow;
  return result ? result.toJSDate() : null;
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
  
  let nextFuture = null;
  let earliestTomorrow = null;
  const tomorrowInZone = nowInZone.plus({ days: 1 });
  
  for (const schedule of effectiveSchedules) {
    const parsed = parseScheduleToTime(schedule);
    if (!parsed) continue;
    
    const todayTime = nowInZone.set({ 
      hour: parsed.hours, 
      minute: parsed.minutes, 
      second: 0, 
      millisecond: 0 
    });
    
    // Only consider future times for task scheduling
    if (todayTime > nowInZone) {
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
  try {
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

    const [response] = await tasksClient.createTask({
      parent: queuePath,
      task,
    });

    logger.info(`Created Cloud Task for user ${userId}`, { 
      taskName: response.name,
      scheduledTime: scheduledTime.toISOString(),
      executeAt: executeAt.toISOString(),
    });

    return response.name;
  } catch (error) {
    logger.error(`Error creating Cloud Task for user ${userId}:`, { error: error.message });
    return null;
  }
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
    await db.runTransaction(async (transaction) => {
      const seniorStateDoc = await transaction.get(seniorStateRef);
      
      if (!seniorStateDoc.exists) {
        logger.info(`Senior state not found for user ${userId}`);
        return;
      }
      
      const data = seniorStateDoc.data();
      
      // Check if vacation mode was enabled after task creation
      if (data.vacationMode) {
        logger.info(`User ${userId} is now on vacation, skipping missed check-in`);
        return;
      }
      
      // TOCTOU check: Did user check in between task creation and now?
      const lastCheckIn = data.lastCheckIn?.toDate?.();
      const taskCreatedAt = new Date(createdAt);
      
      if (lastCheckIn && lastCheckIn > taskCreatedAt) {
        logger.info(`User ${userId} checked in after task creation, not a miss`);
        return;
      }
      
      // Also check if checked in today (same day as scheduled time)
      const scheduledDateTime = new Date(scheduledTime);
      if (lastCheckIn) {
        const tz = timezone || TIMEZONE;
        const lastCheckInLuxon = DateTime.fromJSDate(lastCheckIn, { zone: tz });
        const scheduledLuxon = DateTime.fromJSDate(scheduledDateTime, { zone: tz });
        
        if (lastCheckInLuxon.hasSame(scheduledLuxon, "day")) {
          logger.info(`User ${userId} already checked in today`);
          return;
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
          return;
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
        return;
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
    });
    
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
      const nextExpected = calculateNextExpectedCheckIn(schedules, new Date(), checkInTime, userTimezone);
      
      // Reset consecutive missed days on successful check-in
      transaction.update(seniorStateRef, {
        nextExpectedCheckIn: nextExpected ? Timestamp.fromDate(nextExpected) : FieldValue.delete(),
        lastCheckIn: Timestamp.fromDate(checkInTime),
        consecutiveMissedDays: 0, // Reset streak
        activeTaskId: FieldValue.delete(), // Will be set by scheduleCheckInTask
      });
      
      logger.info(`Updated nextExpectedCheckIn for ${userId}: ${nextExpected?.toISOString()}`);
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
      
      batch.update(seniorStateRef, { missedCheckInsToday: 0 });
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
