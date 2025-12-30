/**
 * Firebase Cloud Functions for SafeCheck App
 * 
 * SCALABLE ARCHITECTURE v2:
 * - Uses top-level 'seniorStates' collection for efficient queries (no CollectionGroup scans)
 * - Triggers maintain the top-level collection in sync with user subcollections
 * - Batched reads for idempotency checks (no N+1 queries)
 * - Derives missed schedule from nextExpectedCheckIn field
 * - Designed to handle 1M+ users
 */

const { setGlobalOptions } = require("firebase-functions");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const { DateTime } = require("luxon");

// Import shared constants (keep in sync with lib/utils/constants.dart)
const {
  DEFAULT_CHECK_IN_SCHEDULE,
  DEFAULT_SCHEDULES,
  TIMEZONE,
  BATCH_SIZE,
  GETALL_CHUNK_SIZE,
  GRACE_PERIOD_MINUTES,
} = require("./constants");

// Initialize Firebase Admin
initializeApp();
const db = getFirestore();

// Global options for cost control
setGlobalOptions({ maxInstances: 20 });

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
  let nextToday = null;
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
  
  const result = nextToday || earliestTomorrow;
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
 * TRIGGER: Sync seniorState changes to top-level collection
 * This enables efficient queries without CollectionGroup scans
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
    logger.info(`Deleted seniorStates/${userId}`);
    return;
  }
  
  const data = event.data.after.data();
  
  // Only sync relevant fields for querying
  await topLevelRef.set({
    nextExpectedCheckIn: data.nextExpectedCheckIn || null,
    vacationMode: data.vacationMode || false,
    lastCheckIn: data.lastCheckIn || null,
    checkInSchedules: data.checkInSchedules || ["11:00 AM"],
    seniorCreatedAt: data.seniorCreatedAt || null,
    missedCheckInsToday: data.missedCheckInsToday || 0,
    updatedAt: Timestamp.now(),
  }, { merge: true });
  
  logger.info(`Synced seniorStates/${userId}`);
});

/**
 * SCALABLE: Check for missed check-ins using top-level collection
 * Queries directly with proper indexes - no full scans
 */
exports.checkMissedCheckIns = onSchedule({
  schedule: "every 15 minutes",
  timeZone: TIMEZONE,
  retryCount: 3,
  timeoutSeconds: 540,
  memory: "512MiB",
  // minInstances: 1, // TODO: Uncomment to Prevent cold starts for this critical function
}, async (event) => {
  const startTime = Date.now();
  const now = new Date();
  const checkTime = new Date(now.getTime() - GRACE_PERIOD_MINUTES * 60 * 1000);
  const checkTimestamp = Timestamp.fromDate(checkTime);
  
  logger.info("Starting optimized missed check-in detection", {
    currentTime: now.toISOString(),
    checkingBefore: checkTime.toISOString(),
  });

  const metrics = {
    queriedSeniors: 0,
    missedCheckInsRecorded: 0,
    skippedVacation: 0,
    skippedDay1: 0,
    skippedAlreadyRecorded: 0,
    updatedNextExpected: 0,
    errors: 0,
  };

  try {
    // SCALABLE QUERY: Direct index query on top-level collection
    // No CollectionGroup scan, no in-memory filtering
    const lateSnapshot = await db.collection("seniorStates")
      .where("vacationMode", "==", false)
      .where("nextExpectedCheckIn", "<", checkTimestamp)
      .get();

    metrics.queriedSeniors = lateSnapshot.size;
    logger.info(`Found ${lateSnapshot.size} late seniors via indexed query`);

    if (lateSnapshot.empty) {
      logger.info("No late seniors found");
      return;
    }

    // Filter out Day 1 users
    const lateSeniors = lateSnapshot.docs.filter(doc => {
      const data = doc.data();
      const createdAt = data.seniorCreatedAt?.toDate?.();
      if (createdAt && 
          createdAt.getFullYear() === now.getFullYear() &&
          createdAt.getMonth() === now.getMonth() &&
          createdAt.getDate() === now.getDate()) {
        metrics.skippedDay1++;
        return false;
      }
      return true;
    });

    if (lateSeniors.length === 0) {
      logger.info("All late seniors are Day 1 users, skipping");
      return;
    }

    // BATCH IDEMPOTENCY CHECK: Fetch all existing activity logs in parallel
    const existingDocRefs = lateSeniors.map(doc => {
      const userId = doc.id;
      const data = doc.data();
      
      // Derive missed schedule from nextExpectedCheckIn
      const expectedTime = data.nextExpectedCheckIn?.toDate?.();
      const missedSchedule = expectedTime ? formatTimeToSchedule(expectedTime) : "11:00 AM";
      const docId = getMissedCheckInKey(userId, missedSchedule, now);
      
      return {
        userId,
        docId,
        missedSchedule,
        data,
        ref: db.collection("users").doc(userId).collection("activityLogs").doc(docId),
      };
    });

    // Batch fetch existing docs in chunks of 500 (Firestore limit)
    const allRefs = existingDocRefs.map(r => r.ref);
    const existingDocs = [];
    for (let i = 0; i < allRefs.length; i += GETALL_CHUNK_SIZE) {
      const chunk = allRefs.slice(i, i + GETALL_CHUNK_SIZE);
      try {
        const chunkResults = await db.getAll(...chunk);
        existingDocs.push(...chunkResults);
      } catch (chunkError) {
        logger.error(`Error fetching chunk ${i / GETALL_CHUNK_SIZE}:`, { error: chunkError.message });
        throw chunkError; // Re-throw to make failures observable
      }
    }
    
    // Map results to determine which need processing
    const toProcess = [];
    existingDocRefs.forEach((item, index) => {
      if (existingDocs[index].exists) {
        metrics.skippedAlreadyRecorded++;
      } else {
        toProcess.push(item);
      }
    });

    logger.info(`Processing ${toProcess.length} new missed check-ins (skipped ${metrics.skippedAlreadyRecorded} already recorded)`);

    // Process in batches
    let batch = db.batch();
    let batchCount = 0;

    for (const item of toProcess) {
      try {
        const { userId, docId, missedSchedule, data } = item;
        
        // Write activity log
        const activityRef = db.collection("users").doc(userId).collection("activityLogs").doc(docId);
        batch.set(activityRef, {
          seniorId: userId,
          activityType: "missed_check_in",
          timestamp: Timestamp.now(),
          isAlert: true,
          metadata: {
            scheduledTime: missedSchedule,
            detectedAt: now.toISOString(),
          },
        }, { merge: true });
        metrics.missedCheckInsRecorded++;
        
        // Update nextExpectedCheckIn to prevent re-alerting
        // Fetch user timezone for accurate scheduling
        const userTimezone = await getUserTimezone(userId);
        const schedules = data.checkInSchedules || ["11:00 AM"];
        const nextExpected = calculateNextExpectedCheckIn(schedules, now, null, userTimezone);
        
        batchCount++; // Activity log write is guaranteed
        
        if (nextExpected) {
          const seniorStateRef = db.collection("users").doc(userId).collection("data").doc("seniorState");
          batch.update(seniorStateRef, {
            nextExpectedCheckIn: Timestamp.fromDate(nextExpected),
            lastMissedCheckIn: Timestamp.now(),
            missedCheckInsToday: FieldValue.increment(1),
          });
          metrics.updatedNextExpected++;
          batchCount++; // Senior state write only when nextExpected is truthy
        }
        
        if (batchCount >= BATCH_SIZE) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
      } catch (error) {
        metrics.errors++;
        logger.error(`Error processing user:`, { error: error.message });
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    const duration = Date.now() - startTime;
    logger.info("Missed check-in detection completed", {
      ...metrics,
      durationMs: duration,
    });

  } catch (error) {
    logger.error("Critical error in checkMissedCheckIns:", { error: error.message, stack: error.stack });
    throw error;
  }
});

/**
 * TRIGGER: Update nextExpectedCheckIn when a check-in is recorded
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
  
  logger.info(`Check-in recorded for user ${userId}, updating nextExpectedCheckIn`);
  
  const seniorStateRef = db.collection("users").doc(userId)
    .collection("data").doc("seniorState");
  
  try {
    // Fetch user timezone for timezone-aware calculations
    const userTimezone = await getUserTimezone(userId);
    
    // Use transaction to prevent race condition with checkMissedCheckIns job
    await db.runTransaction(async (transaction) => {
      const seniorStateDoc = await transaction.get(seniorStateRef);
      
      if (!seniorStateDoc.exists) return;
      
      const seniorState = seniorStateDoc.data();
      const currentNextExpected = seniorState.nextExpectedCheckIn;
      const schedules = seniorState.checkInSchedules || ["11:00 AM"];
      const nextExpected = calculateNextExpectedCheckIn(schedules, new Date(), checkInTime, userTimezone);
      
      if (nextExpected) {
        // Only update if nextExpectedCheckIn hasn't changed (prevents race condition)
        // Or if there was no previous value
        const shouldUpdate = !currentNextExpected || 
          currentNextExpected.isEqual(seniorState.nextExpectedCheckIn);
        
        if (shouldUpdate) {
          transaction.update(seniorStateRef, {
            nextExpectedCheckIn: Timestamp.fromDate(nextExpected),
            lastCheckIn: Timestamp.fromDate(checkInTime),
          });
          
          logger.info(`Updated nextExpectedCheckIn for ${userId}: ${nextExpected.toISOString()}`);
        } else {
          logger.info(`Skipped update for ${userId}: nextExpectedCheckIn was modified concurrently`);
        }
      }
    });
  } catch (error) {
    logger.error(`Error updating nextExpectedCheckIn for ${userId}:`, { error: error.message });
  }
});

/**
 * SCHEDULED: Reset daily counters at midnight
 */
exports.resetDailyCounters = onSchedule({
  schedule: "0 0 * * *",
  timeZone: "Asia/Karachi",
  retryCount: 3,
  timeoutSeconds: 540,
  memory: "256MiB",
}, async (event) => {
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

  } catch (error) {
    logger.error("Error in resetDailyCounters:", { error: error.message });
    throw error;
  }
});

/**
 * SCHEDULED: Backfill top-level seniorStates for existing users
 * Run once daily to catch any seniors not yet synced
 */
exports.backfillSeniorStates = onSchedule({
  schedule: "30 0 * * *",
  timeZone: "Asia/Karachi",
  retryCount: 1,
  timeoutSeconds: 540,
  memory: "512MiB",
}, async (event) => {
  const startTime = Date.now();
  logger.info("Starting seniorStates backfill");

  let processedCount = 0;
  let batch = db.batch();
  let batchCount = 0;

  try {
    // Paginate through users collection to handle scale
    const PAGE_SIZE = 500;
    let lastDoc = null;
    
    while (true) {
      // Build paginated query
      let usersQuery = db.collection("users").limit(PAGE_SIZE);
      if (lastDoc) {
        usersQuery = usersQuery.startAfter(lastDoc);
      }
      
      const usersSnapshot = await usersQuery.get();
      if (usersSnapshot.empty) break;
      
      lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];
      
      // Batch fetch seniorState docs for this page
      const seniorStateRefs = usersSnapshot.docs.map(d => 
        db.collection("users").doc(d.id).collection("data").doc("seniorState")
      );
      
      let seniorStateDocs = [];
      for (let i = 0; i < seniorStateRefs.length; i += GETALL_CHUNK_SIZE) {
        const chunk = seniorStateRefs.slice(i, i + GETALL_CHUNK_SIZE);
        const chunkResults = await db.getAll(...chunk);
        seniorStateDocs.push(...chunkResults);
      }
      
      // Batch fetch top-level docs for this page
      const topLevelRefs = usersSnapshot.docs.map(d => 
        db.collection("seniorStates").doc(d.id)
      );
      
      let topLevelDocs = [];
      for (let i = 0; i < topLevelRefs.length; i += GETALL_CHUNK_SIZE) {
        const chunk = topLevelRefs.slice(i, i + GETALL_CHUNK_SIZE);
        const chunkResults = await db.getAll(...chunk);
        topLevelDocs.push(...chunkResults);
      }
      
      // Process each user
      for (let i = 0; i < usersSnapshot.docs.length; i++) {
        const userId = usersSnapshot.docs[i].id;
        const seniorStateDoc = seniorStateDocs[i];
        const topLevelDoc = topLevelDocs[i];
        
        if (!seniorStateDoc.exists) continue;
        
        const data = seniorStateDoc.data();
        
        if (!topLevelDoc.exists || !topLevelDoc.data()?.nextExpectedCheckIn) {
          const topLevelRef = db.collection("seniorStates").doc(userId);
          batch.set(topLevelRef, {
            nextExpectedCheckIn: data.nextExpectedCheckIn || null,
            vacationMode: data.vacationMode || false,
            lastCheckIn: data.lastCheckIn || null,
            checkInSchedules: data.checkInSchedules || ["11:00 AM"],
            seniorCreatedAt: data.seniorCreatedAt || null,
            missedCheckInsToday: data.missedCheckInsToday || 0,
            updatedAt: Timestamp.now(),
          }, { merge: true });
          
          batchCount++;
          processedCount++;

          if (batchCount >= BATCH_SIZE) {
            await batch.commit();
            batch = db.batch();
            batchCount = 0;
          }
        }
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    const duration = Date.now() - startTime;
    logger.info("SeniorStates backfill completed", { processedCount, durationMs: duration });

  } catch (error) {
    logger.error("Error in backfillSeniorStates:", { error: error.message });
    throw error;
  }
});
