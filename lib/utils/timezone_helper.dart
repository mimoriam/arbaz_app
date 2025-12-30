import 'constants.dart';

/// Helper utilities for timezone-aware date handling.
/// 
/// This class provides methods to:
/// - Get the device's timezone identifier
/// - Perform timezone-aware date comparisons
/// - Convert between timezones
/// 
/// Fallback behavior: If timezone is null, empty, or invalid,
/// all methods fall back to [AppConstants.timezone] ('Asia/Karachi').
abstract class TimezoneHelper {
  /// Returns the device's IANA timezone identifier.
  /// 
  /// Example: 'Asia/Karachi', 'America/New_York', 'Europe/London'
  /// 
  /// Falls back to [AppConstants.timezone] if detection fails.
  static String getDeviceTimezone() {
    try {
      // DateTime.now().timeZoneName returns abbreviations like 'PKT', 'EST'
      // For IANA identifiers, we use the offset approach
      final now = DateTime.now();
      final offset = now.timeZoneOffset;
      
      // Map common offsets to IANA timezone identifiers
      // This is a simplified mapping - covers major timezones
      return _offsetToTimezone(offset) ?? AppConstants.timezone;
    } catch (_) {
      return AppConstants.timezone;
    }
  }

  /// Returns the effective timezone to use.
  /// 
  /// If [userTimezone] is null, empty, or invalid, returns [AppConstants.timezone].
  static String getEffectiveTimezone(String? userTimezone) {
    if (userTimezone == null || userTimezone.trim().isEmpty) {
      return AppConstants.timezone;
    }
    
    // Validate the timezone string (basic validation)
    if (!_isValidTimezone(userTimezone)) {
      return AppConstants.timezone;
    }
    
    return userTimezone;
  }

  /// Checks if two DateTimes fall on the same calendar day in the given timezone.
  /// 
  /// This is timezone-aware: 11:30 PM in one timezone might be a different
  /// calendar day than 11:30 PM in another timezone.
  static bool isSameDay(DateTime a, DateTime b, String? timezone) {
    final tz = getEffectiveTimezone(timezone);
    final offset = _getTimezoneOffset(tz);
    
    // Adjust both dates to the target timezone
    final aLocal = a.toUtc().add(offset);
    final bLocal = b.toUtc().add(offset);
    
    return aLocal.year == bLocal.year &&
           aLocal.month == bLocal.month &&
           aLocal.day == bLocal.day;
  }

  /// Gets the current DateTime in the specified timezone.
  /// 
  /// Returns a DateTime adjusted to the target timezone's local time.
  static DateTime nowInTimezone(String? timezone) {
    final tz = getEffectiveTimezone(timezone);
    final offset = _getTimezoneOffset(tz);
    return DateTime.now().toUtc().add(offset);
  }

  /// Converts a DateTime to the specified timezone.
  /// 
  /// The input DateTime is treated as UTC and converted to local time
  /// in the target timezone.
  static DateTime toTimezone(DateTime dateTime, String? timezone) {
    final tz = getEffectiveTimezone(timezone);
    final offset = _getTimezoneOffset(tz);
    return dateTime.toUtc().add(offset);
  }

  /// Gets the start of day (00:00:00) in the specified timezone.
  static DateTime startOfDayInTimezone(DateTime date, String? timezone) {
    final tz = getEffectiveTimezone(timezone);
    final offset = _getTimezoneOffset(tz);
    final localDate = date.toUtc().add(offset);
    
    // Create start of day in the timezone, then convert back to UTC
    return DateTime.utc(localDate.year, localDate.month, localDate.day)
        .subtract(offset);
  }

  /// Gets the end of day (23:59:59.999) in the specified timezone.
  static DateTime endOfDayInTimezone(DateTime date, String? timezone) {
    final tz = getEffectiveTimezone(timezone);
    final offset = _getTimezoneOffset(tz);
    final localDate = date.toUtc().add(offset);
    
    // Create end of day in the timezone, then convert back to UTC
    return DateTime.utc(
      localDate.year, localDate.month, localDate.day,
      23, 59, 59, 999,
    ).subtract(offset);
  }

  // ===== Private Helper Methods =====

  /// Maps a UTC offset to an IANA timezone identifier.
  /// 
  /// This is a simplified mapping covering common timezones.
  /// Returns null for unknown offsets.
  static String? _offsetToTimezone(Duration offset) {
    final hours = offset.inHours;
    final minutes = offset.inMinutes.remainder(60);
    
    // Common timezone mappings (most used)
    final timezoneMap = <String, String>{
      '+5:0': 'Asia/Karachi',      // Pakistan
      '+5:30': 'Asia/Kolkata',     // India
      '+6:0': 'Asia/Dhaka',        // Bangladesh
      '+8:0': 'Asia/Singapore',    // Singapore, Malaysia, Philippines
      '+9:0': 'Asia/Tokyo',        // Japan, Korea
      '+0:0': 'UTC',               // UTC
      '+1:0': 'Europe/Paris',      // Central Europe
      '-5:0': 'America/New_York',  // US Eastern
      '-8:0': 'America/Los_Angeles', // US Pacific
      '+3:0': 'Asia/Riyadh',       // Saudi Arabia
      '+4:0': 'Asia/Dubai',        // UAE
      '+7:0': 'Asia/Bangkok',      // Thailand, Vietnam
      '+10:0': 'Australia/Sydney', // Australia Eastern
    };
    
    final key = '+$hours:${minutes.abs()}';
    final negKey = '-${hours.abs()}:${minutes.abs()}';
    
    return timezoneMap[key] ?? timezoneMap[negKey];
  }

  /// Gets the UTC offset for a given IANA timezone identifier.
  /// 
  /// Returns a Duration representing the offset from UTC.
  /// Falls back to the default timezone offset if unknown.
  static Duration _getTimezoneOffset(String timezone) {
    // Mapping of IANA timezone identifiers to UTC offsets
    // Note: This doesn't handle DST. For full DST support, 
    // consider using the 'timezone' package.
    final offsetMap = <String, Duration>{
      'Asia/Karachi': const Duration(hours: 5),
      'Asia/Kolkata': const Duration(hours: 5, minutes: 30),
      'Asia/Dhaka': const Duration(hours: 6),
      'Asia/Singapore': const Duration(hours: 8),
      'Asia/Tokyo': const Duration(hours: 9),
      'Asia/Seoul': const Duration(hours: 9),
      'UTC': Duration.zero,
      'Europe/London': Duration.zero, // Simplified, ignores DST
      'Europe/Paris': const Duration(hours: 1),
      'Europe/Berlin': const Duration(hours: 1),
      'America/New_York': const Duration(hours: -5),
      'America/Chicago': const Duration(hours: -6),
      'America/Denver': const Duration(hours: -7),
      'America/Los_Angeles': const Duration(hours: -8),
      'Asia/Riyadh': const Duration(hours: 3),
      'Asia/Dubai': const Duration(hours: 4),
      'Asia/Bangkok': const Duration(hours: 7),
      'Asia/Jakarta': const Duration(hours: 7),
      'Australia/Sydney': const Duration(hours: 10),
      'Australia/Melbourne': const Duration(hours: 10),
      'Pacific/Auckland': const Duration(hours: 12),
    };
    
    return offsetMap[timezone] ?? const Duration(hours: 5); // Default: Asia/Karachi
  }

  /// Validates if a timezone string is a known IANA identifier.
  static bool _isValidTimezone(String timezone) {
    // List of commonly valid IANA timezone identifiers
    const validTimezones = {
      'Asia/Karachi', 'Asia/Kolkata', 'Asia/Dhaka', 'Asia/Singapore',
      'Asia/Tokyo', 'Asia/Seoul', 'Asia/Shanghai', 'Asia/Hong_Kong',
      'Asia/Riyadh', 'Asia/Dubai', 'Asia/Bangkok', 'Asia/Jakarta',
      'UTC', 'Europe/London', 'Europe/Paris', 'Europe/Berlin',
      'Europe/Moscow', 'America/New_York', 'America/Chicago',
      'America/Denver', 'America/Los_Angeles', 'America/Toronto',
      'Australia/Sydney', 'Australia/Melbourne', 'Pacific/Auckland',
    };
    
    return validTimezones.contains(timezone);
  }
}
