import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Callback for handling notification taps when the app is running.
/// This must be a top-level function (not a class method) for background handling.
@pragma('vm:entry-point')
void onDidReceiveNotificationResponse(NotificationResponse notificationResponse) {
  debugPrint('Notification tapped with payload: ${notificationResponse.payload}');
  // Navigation is handled by the app's main navigation logic
  // The payload can be used to determine where to navigate
}

/// Callback for handling notification taps received in background.
/// This must be a top-level function for isolate compatibility.
@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse notificationResponse) {
  debugPrint('Background notification response: ${notificationResponse.payload}');
}

/// Service for managing local notifications in the app.
/// 
/// Handles initialization, permission requests, and displaying notifications
/// for missed check-ins on both Android and iOS platforms.
class NotificationService {
  // Singleton pattern - only one instance ever created
  static final NotificationService _instance = NotificationService._internal();
  
  /// Get the singleton instance of NotificationService
  static NotificationService get instance => _instance;
  
  /// Factory constructor that always returns the same singleton instance
  factory NotificationService() => _instance;
  
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  
  /// Android notification channel configuration
  static const String _channelId = 'check_in_reminders';
  static const String _channelName = 'Check-in Reminders';
  static const String _channelDescription = 'Notifications for missed check-ins';
  
  /// Notification IDs
  static const int missedCheckInNotificationId = 1001;
  
  /// Cooldown period to prevent duplicate notifications (Timer + Firestore stream race)
  static const Duration _notificationCooldown = Duration(seconds: 30);
  /// SOS-specific cooldown period (5 minutes) to prevent repeated SOS alerts
  static const Duration _sosCooldown = Duration(minutes: 5);
  static const String _cooldownPrefKey = 'notification_last_shown_timestamp';
  DateTime? _lastNotificationTime;
  
  /// Whether the service has been initialized
  bool get isInitialized => _isInitialized;
  
  /// Initializes the notification plugin with platform-specific settings.
  /// 
  /// Should be called once during app startup, typically in main.dart.
  /// Returns the details if the app was launched by tapping a notification.
  Future<NotificationAppLaunchDetails?> initialize() async {
    if (_isInitialized) {
      debugPrint('NotificationService already initialized');
      return null;
    }
    
    try {
      // Android initialization settings
      // Uses the app's launcher icon - ensure @mipmap/ic_launcher exists
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      
      // iOS/macOS initialization settings
      // Request permissions during initialization
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        // Default presentation options for foreground notifications
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      );
      
      // Combined initialization settings
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        macOS: iosSettings,
      );
      
      // Initialize the plugin
      final bool? initialized = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: onDidReceiveBackgroundNotificationResponse,
      );
      
      if (initialized != true) {
        debugPrint('NotificationService: initialization returned false or null - aborting');
        _isInitialized = false;
        return null;
      }
      
      // Create the notification channel for Android
      await _createNotificationChannel();
      
      // Request permissions on Android 13+ and iOS
      // This must be done after initialization
      await requestPermissions();
      
      _isInitialized = true;
      debugPrint('NotificationService initialized successfully');
      
      // Load persisted cooldown timestamp
      await _loadCooldownTimestamp();
      
      // Check if app was launched from a notification
      return await getNotificationAppLaunchDetails();
      
    } catch (e, stackTrace) {
      debugPrint('Error initializing NotificationService: $e');
      debugPrint('Stack trace: $stackTrace');
      // Don't crash the app if notifications fail to initialize
      _isInitialized = false;
      return null;
    }
  }
  
  /// Creates the Android notification channel.
  /// Required for Android 8.0+ (API 26+).
  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
      debugPrint('Android notification channel created: $_channelId');
    }
  }
  
  /// Loads the persisted cooldown timestamp from SharedPreferences.
  Future<void> _loadCooldownTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cooldownPrefKey);
      if (timestamp != null) {
        _lastNotificationTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        debugPrint('NotificationService: Loaded cooldown timestamp from $_lastNotificationTime');
      }
    } catch (e) {
      debugPrint('Error loading cooldown timestamp: $e');
    }
  }
  
  /// Saves the cooldown timestamp to SharedPreferences.
  Future<void> _saveCooldownTimestamp() async {
    try {
      if (_lastNotificationTime == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cooldownPrefKey, _lastNotificationTime!.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving cooldown timestamp: $e');
    }
  }
  
  /// Gets details about how the app was launched.
  /// Returns non-null if the app was launched by tapping a notification.
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async {
    try {
      return await _plugin.getNotificationAppLaunchDetails();
    } catch (e) {
      debugPrint('Error getting notification launch details: $e');
      return null;
    }
  }
  
  /// Requests notification permissions on iOS.
  /// On Android 13+, this requests POST_NOTIFICATIONS permission.
  /// 
  /// Returns true if permissions were granted, false otherwise.
  Future<bool> requestPermissions() async {
    try {
      // Request iOS permissions
      final IOSFlutterLocalNotificationsPlugin? iosPlugin =
          _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      
      if (iosPlugin != null) {
        final bool? granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('iOS notification permissions granted: $granted');
        return granted ?? false;
      }
      
      // Request Android 13+ permissions
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        final bool? granted = await androidPlugin.requestNotificationsPermission();
        debugPrint('Android notification permissions granted: $granted');
        return granted ?? false;
      }
      
      return true; // Permissions not needed on this platform
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
      return false;
    }
  }
  
  /// Checks if notifications are enabled on Android.
  Future<bool> areNotificationsEnabled() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        return await androidPlugin.areNotificationsEnabled() ?? false;
      }
      
      return true; // Assume enabled on other platforms
    } catch (e) {
      debugPrint('Error checking notification status: $e');
      return false;
    }
  }
  
  /// Shows a notification for a missed check-in.
  /// 
  /// [missedCount] - The number of missed check-ins today.
  /// [isVacationMode] - If true, notification will not be shown.
  Future<void> showMissedCheckInNotification({
    required int missedCount,
    bool isVacationMode = false,
  }) async {
    // Validate missedCount - don't show notifications for invalid counts
    if (missedCount < 1) {
      debugPrint('NotificationService: Skipping notification - invalid missedCount: $missedCount');
      return;
    }
    
    // Don't show notifications during vacation mode
    if (isVacationMode) {
      debugPrint('NotificationService: Skipping notification - vacation mode enabled');
      return;
    }
    
    if (!_isInitialized) {
      debugPrint('NotificationService: Cannot show notification - not initialized');
      return;
    }
    
    // Prevent duplicate notifications within cooldown period
    // Handles race condition where Timer and Firestore stream both try to show notification
    final now = DateTime.now();
    if (_lastNotificationTime != null) {
      final timeSince = now.difference(_lastNotificationTime!);
      if (timeSince < _notificationCooldown) {
        debugPrint('NotificationService: Skipping duplicate notification (cooldown active, ${timeSince.inSeconds}s since last)');
        return;
      }
    }
    
    // Check if FCM notification was just received (deduplication with server push)
    final prefs = await SharedPreferences.getInstance();
    final fcmTimestamp = prefs.getInt('fcm_last_notification_timestamp');
    if (fcmTimestamp != null) {
      final fcmTime = DateTime.fromMillisecondsSinceEpoch(fcmTimestamp);
      final timeSinceFcm = now.difference(fcmTime);
      if (timeSinceFcm < const Duration(seconds: 5)) {
        debugPrint('NotificationService: Skipping local notification - FCM just received ${timeSinceFcm.inSeconds}s ago');
        return;
      }
    }
    
    try {
      // Check if notifications are enabled on Android
      final bool enabled = await areNotificationsEnabled();
      if (!enabled) {
        debugPrint('NotificationService: Notifications are disabled by user');
        return;
      }
      
      // Build notification content
      final String title = missedCount == 1
          ? "Check-in Reminder"
          : "Multiple Missed Check-ins";
      
      final String body = missedCount == 1
          ? "You haven't checked in yet today. Tap to let your family know you're okay!"
          : "You've missed $missedCount check-ins today. Tap to check in now.";
      
      // Android notification details
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        // Show as a heads-up notification
        fullScreenIntent: false,
        // Category for proper handling
        category: AndroidNotificationCategory.reminder,
        // Auto-cancel when tapped
        autoCancel: true,
      );
      
      // iOS notification details
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        // Use default sound
        sound: null,
        badgeNumber: null, // Don't modify badge
        interruptionLevel: InterruptionLevel.active,
      );
      
      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // Show the notification
      await _plugin.show(
        missedCheckInNotificationId,
        title,
        body,
        notificationDetails,
        payload: 'missed_checkin:$missedCount',
      );
      
      debugPrint('NotificationService: Showed missed check-in notification (count: $missedCount)');
      
      // Update and persist cooldown timestamp
      _lastNotificationTime = DateTime.now();
      await _saveCooldownTimestamp();
      
    } catch (e, stackTrace) {
      debugPrint('Error showing notification: $e');
      debugPrint('Stack trace: $stackTrace');
      // Don't crash the app if notification fails
    }
  }
  
  /// Cancels the missed check-in notification.
  /// Call this when the user checks in successfully.
  Future<void> cancelMissedCheckInNotification() async {
    try {
      await _plugin.cancel(missedCheckInNotificationId);
      debugPrint('NotificationService: Cancelled missed check-in notification');
    } catch (e) {
      debugPrint('Error cancelling notification: $e');
    }
  }
  
  /// Cancels all notifications.
  Future<void> cancelAllNotifications() async {
    try {
      await _plugin.cancelAll();
      debugPrint('NotificationService: Cancelled all notifications');
    } catch (e) {
      debugPrint('Error cancelling all notifications: $e');
    }
  }

  /// Checks if a generic cooldown is active for the given key (uses 30 second cooldown)
  Future<bool> _isInCooldown(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(key);
      if (timestamp != null) {
         final lastTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
         final timeSince = DateTime.now().difference(lastTime);
         return timeSince < _notificationCooldown;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Checks if a SOS-specific cooldown is active for the given key (uses 5 minute cooldown)
  Future<bool> _isInSosCooldown(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(key);
      if (timestamp != null) {
         final lastTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
         final timeSince = DateTime.now().difference(lastTime);
         return timeSince < _sosCooldown;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Sets the cooldown timestamp for a specific key
  Future<void> _setCooldown(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving cooldown: $e');
    }
  }
  /// Shows a notification for a family member about a senior's missed check-in.
  /// 
  /// Includes:
  /// - Validation for missedCount
  /// - Cooldown logic to prevent spam
  /// - Safe notification ID generation
  /// - Critical alert fallback if entitlement missing (implicit by OS)
  Future<void> showFamilyMissedCheckInNotification({
    required int missedCount,
    required String seniorId,
  }) async {
    if (!_isInitialized) return;
    
    // Validate missedCount
    if (missedCount < 1) {
      debugPrint('NotificationService: Invalid missedCount $missedCount for family alert');
      return;
    }
    
    // Check if notifications are enabled
    final bool enabled = await areNotificationsEnabled();
    if (!enabled) return;
    
    // Cooldown check for family notifications (per senior)
    final String cooldownKey = 'last_family_alert_$seniorId';
    if (await _isInCooldown(cooldownKey)) {
      debugPrint('NotificationService: Skipping family alert for $seniorId - cooldown active');
      return;
    }
    
    // Build notification content - customize message for family
    final String title = "Missed Check-in Alert";
    final String body = missedCount == 1
        ? "Your linked senior has missed a check-in. Please ensure they are okay."
        : "Your linked senior has missed $missedCount check-ins. Please check on them immediately.";
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    );
    
    // Critical alerts require 'com.apple.developer.usernotifications.critical-alerts' entitlement.
    // Without it, the interruptionLevel is treated as active/timeSensitive depending on OS version.
    // We use critical here but OS will fallback if entitlement is missing.
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical, 
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    // Use full safe hash for notification ID to prevent collisions across seniors.
    // The bitmask 0x7fffffff ensures a non-negative 31-bit integer, which is valid
    // for notification IDs on both Android and iOS.
    final int notificationId = seniorId.hashCode & 0x7fffffff;
    
    await _plugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: 'family_missed_checkin:$seniorId',
    );
    
    // Set cooldown timestamp
    await _setCooldown(cooldownKey);
    
    debugPrint('NotificationService: Showed family alert for senior $seniorId (ID: $notificationId)');
  }

  /// Shows a notification for a family member when a senior triggers SOS.
  /// 
  /// Includes:
  /// - High-priority notification settings for immediate visibility
  /// - Cooldown logic to prevent duplicate SOS alerts per senior
  /// - Distinct notification ID per senior to allow multiple concurrent alerts
  Future<void> showFamilySOSNotification({
    required String seniorId,
    required String seniorName,
  }) async {
    if (!_isInitialized) return;
    
    // Check if notifications are enabled
    final bool enabled = await areNotificationsEnabled();
    if (!enabled) return;
    
    // Cooldown check for SOS notifications (per senior) - 5 minutes
    final String cooldownKey = 'last_family_sos_$seniorId';
    if (await _isInSosCooldown(cooldownKey)) {
      debugPrint('NotificationService: Skipping family SOS for $seniorId - 5 minute cooldown active');
      return;
    }
    
    // Build notification content
    const String title = '🚨 SOS Alert!';
    final String body = '$seniorName needs help! Tap to respond.';
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true, // Show as full-screen on lock screen
      playSound: true,
      enableVibration: true,
    );
    
    // Critical alerts for iOS
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      interruptionLevel: InterruptionLevel.critical,
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    // Use distinct notification ID for SOS (offset to avoid collision with missed check-in IDs)
    // Bound the base hash to ensure final ID stays within 32-bit signed int range (max 0x7fffffff)
    final int baseHash = (seniorId.hashCode & 0x7fffffff) % (0x7fffffff - 1000000);
    final int notificationId = baseHash + 1000000;
    
    await _plugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: 'family_sos:$seniorId',
    );
    
    // Set cooldown timestamp (5 minute cooldown for SOS)
    await _setCooldown(cooldownKey);
    
    debugPrint('NotificationService: Showed family SOS alert for senior $seniorId (ID: $notificationId)');
  }
}
