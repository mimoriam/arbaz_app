import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firestore_service.dart';
import 'notification_service.dart';

/// Background message handler - must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    debugPrint('FCM Background message: ${message.messageId}');
    // Background messages with notification payload are auto-displayed by the system
    // We only need to handle data-only messages here if needed
    
    // Handle specific message types
    final String? type = message.data['type'];
    if (type == 'missed_checkin') {
      debugPrint('FCM Background: Received missed check-in notification');
      // System will auto-display the notification since it has a notification payload
      // No additional handling needed for display
    }
  } catch (e, stack) {
    debugPrint('FCM Background handler error: $e');
    debugPrint('Stack trace: $stack');
    // Note: Consider adding Firebase Crashlytics here if available
    // FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FCM background handler');
  }
}

/// Service for managing Firebase Cloud Messaging (FCM) for push notifications.
/// 
/// Handles:
/// - FCM token registration and refresh
/// - Foreground message handling (delegates to NotificationService)
/// - Background message handling
/// - Deduplication with local notifications
class FcmService {
  // Singleton pattern
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  bool _isInitialized = false;
  String? _currentToken;
  
  /// SharedPreferences key for last FCM notification time (deduplication)
  static const String _fcmLastNotificationKey = 'fcm_last_notification_timestamp';
  static const Duration _deduplicationWindow = Duration(seconds: 5);
  
  /// Whether the service has been initialized
  bool get isInitialized => _isInitialized;
  String? get currentToken => _currentToken;
  
  /// Initializes FCM and sets up message handlers.
  /// 
  /// Call this after Firebase is initialized in main.dart.
  /// [userId] is used to store the FCM token in Firestore for server-side sending.
  Future<void> initialize({String? userId}) async {
    if (_isInitialized) {
      debugPrint('FcmService already initialized');
      return;
    }
    
    try {
      // Request permission (iOS and Android 13+)
      final NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      debugPrint('FCM permission status: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM: User denied permission');
        return;
      }
      
      // Get FCM token
      _currentToken = await _messaging.getToken();
      debugPrint('FCM Token: $_currentToken');
      
      // Store token in Firestore for server-side sending (if userId already set)
      if (_userId != null && _currentToken != null) {
        await _updateTokenInFirestore(_userId!, _currentToken!);
      }
      
      // Listen for token refresh - registered only once, uses _userId instance variable
      // Added error handling to prevent silent token update failures
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM Token refreshed: $newToken');
        _currentToken = newToken;
        if (_userId != null) {
          try {
            await _updateTokenInFirestore(_userId!, newToken);
          } catch (e) {
            debugPrint('FCM: Failed to update refreshed token: $e');
            // Retry once after delay - if this fails, next app launch will fix it
            Future.delayed(const Duration(seconds: 5), () async {
              try {
                await _updateTokenInFirestore(_userId!, newToken);
                debugPrint('FCM: Token update retry succeeded');
              } catch (retryError) {
                debugPrint('FCM: Token update retry also failed: $retryError');
              }
            });
          }
        }
      });
      
      // Set up foreground message handler
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      
      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      // Handle notification tap when app was terminated
      final RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM: App launched from notification: ${initialMessage.messageId}');
        _handleNotificationTap(initialMessage);
      }
      
      // Handle notification tap when app was in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
      
      _isInitialized = true;
      debugPrint('FcmService initialized successfully');
      
    } catch (e, stackTrace) {
      debugPrint('Error initializing FcmService: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
  
  /// Stores the current user ID for token refresh registration
  String? _userId;
  
  /// Registers the FCM token for a user after login.
  /// Call this after user authentication to enable server-side push.
  /// Fetches token if not cached and saves to Firestore.
  Future<void> registerToken(String userId) async {
    _userId = userId;
    
    // If we don't have a cached token, try to fetch it
    if (_currentToken == null) {
      try {
        _currentToken = await _messaging.getToken();
        debugPrint('FCM registerToken: Fetched token for user $userId');
      } catch (e) {
        debugPrint('FCM registerToken: Failed to get token: $e');
      }
    }
    
    // Save current token to Firestore for this user
    if (_currentToken != null) {
      debugPrint('FCM registerToken: Saving token to Firestore for user $userId');
      await _updateTokenInFirestore(userId, _currentToken!);
    } else {
      debugPrint('FCM registerToken: WARNING - No token available for user $userId');
    }
  }
  
  /// Updates the FCM token in Firestore for server-side push.
  Future<void> _updateTokenInFirestore(String userId, String token) async {
    try {
      await FirestoreService().updateFcmToken(userId, token);
      debugPrint('FCM token stored in Firestore for user $userId');
    } catch (e) {
      debugPrint('Error storing FCM token: $e');
    }
  }
  
  /// Handles FCM messages received while app is in foreground.
  /// Shows local notification to display the message.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('FCM Foreground message: ${message.messageId}');
    debugPrint('FCM Data: ${message.data}');
    debugPrint('FCM Notification: ${message.notification?.title}');
    
    // Check for deduplication with local notifications
    if (await _shouldSkipDueToDuplication()) {
      debugPrint('FCM: Skipping foreground notification - recent local notification');
      return;
    }
    
    // Check if this is a missed check-in notification
    final String? type = message.data['type'];
    if (type == 'missed_checkin') {
      final int missedCount = int.tryParse(message.data['missedCount'] ?? '1') ?? 1;
      
      // Use NotificationService to show local notification for foreground
      await NotificationService().showMissedCheckInNotification(
        missedCount: missedCount,
        isVacationMode: false, // Server already checked vacation mode
      );
      
      // Record FCM notification time for deduplication
      await _recordFcmNotificationTime();
    } else if (type == 'family_missed_alert') {
      final int missedCount = int.tryParse(message.data['missedCount'] ?? '1') ?? 1;
      final String seniorId = message.data['seniorUserId'] ?? '';
      
      if (seniorId.isNotEmpty) {
        await NotificationService().showFamilyMissedCheckInNotification(
          missedCount: missedCount,
          seniorId: seniorId,
        );
         // Record FCM notification time for deduplication
        await _recordFcmNotificationTime();
      }
    } else if (type == 'sos_alert') {
      // Handle SOS alert for family members
      final String seniorId = message.data['seniorId'] ?? '';
      final String seniorName = message.data['seniorName'] ?? 'Your family member';
      
      if (seniorId.isNotEmpty) {
        await NotificationService().showFamilySOSNotification(
          seniorId: seniorId,
          seniorName: seniorName,
        );
        // Record FCM notification time for deduplication
        await _recordFcmNotificationTime();
      }
    }
  }

  
  /// Handles notification tap from terminated or background state.
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('FCM Notification tapped: ${message.messageId}');
    // Navigation can be handled here based on message.data
    // For now, we just log it - the main navigation handles deep linking
  }
  
  /// Checks if we should skip showing notification due to recent local notification.
  Future<bool> _shouldSkipDueToDuplication() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localTimestamp = prefs.getInt('notification_last_shown_timestamp');
      
      if (localTimestamp != null) {
        final localTime = DateTime.fromMillisecondsSinceEpoch(localTimestamp);
        final timeSince = DateTime.now().difference(localTime);
        
        if (timeSince < _deduplicationWindow) {
          return true; // Local notification was shown recently
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  
  /// Records the time of FCM notification for local notification deduplication.
  Future<void> _recordFcmNotificationTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_fcmLastNotificationKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error recording FCM notification time: $e');
    }
  }
  
  /// Checks if FCM notification was recently shown (for local notification deduplication).
  Future<bool> wasFcmNotificationRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fcmTimestamp = prefs.getInt(_fcmLastNotificationKey);
      
      if (fcmTimestamp != null) {
        final fcmTime = DateTime.fromMillisecondsSinceEpoch(fcmTimestamp);
        final timeSince = DateTime.now().difference(fcmTime);
        return timeSince < _deduplicationWindow;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
