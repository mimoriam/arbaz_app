import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';

/// Types of location errors for differentiated error handling
enum LocationErrorType {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  timeout,
  unknown,
}

/// Result of a location fetch operation
class LocationResult {
  final Position? position;
  final LocationErrorType? errorType;
  final String? errorMessage;
  
  bool get isSuccess => position != null;
  bool get isError => errorType != null;
  
  const LocationResult._({
    this.position,
    this.errorType,
    this.errorMessage,
  });
  
  factory LocationResult.success(Position position) {
    return LocationResult._(position: position);
  }
  
  factory LocationResult.error(LocationErrorType type, {String? message}) {
    return LocationResult._(errorType: type, errorMessage: message);
  }
}

/// Service to handle location permissions and retrieval
class LocationService {
  /// Checks the current permission status
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Requests location permission
  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Gets the current position with appropriate accuracy
  ///
  /// [isEmergency] - If true, uses best accuracy (high battery usage).
  /// If false, uses medium accuracy (battery optimized) for regular check-ins.
  /// 
  /// Returns a [LocationResult] containing either the position or error details.
  Future<LocationResult> getCurrentLocationWithDetails({bool isEmergency = false}) async {
    try {
      final permission = await checkPermission();

      if (permission == LocationPermission.denied) {
        debugPrint('Location permission denied');
        return LocationResult.error(LocationErrorType.permissionDenied);
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied forever');
        return LocationResult.error(LocationErrorType.permissionDeniedForever);
      }
      
      if (permission == LocationPermission.unableToDetermine) {
        debugPrint('Location permission unable to determine');
        return LocationResult.error(LocationErrorType.unknown);
      }

      // Check if location services are enabled
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        debugPrint('Location services are disabled');
        return LocationResult.error(LocationErrorType.serviceDisabled);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: isEmergency ? LocationAccuracy.best : LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 15),
        ),
      );
      
      return LocationResult.success(position);
    } on TimeoutException {
      debugPrint('Location request timed out');
      return LocationResult.error(LocationErrorType.timeout);
    } on LocationServiceDisabledException {
      debugPrint('Location service disabled exception');
      return LocationResult.error(LocationErrorType.serviceDisabled);
    } catch (e) {
      debugPrint('Error getting location: $e');
      return LocationResult.error(LocationErrorType.unknown, message: e.toString());
    }
  }

  /// Legacy method that returns Position? for backward compatibility
  Future<Position?> getCurrentLocation({bool isEmergency = false}) async {
    final result = await getCurrentLocationWithDetails(isEmergency: isEmergency);
    return result.position;
  }

  /// Gets the address from a Position
  /// Prioritizes street-level details for emergency situations
  Future<String?> getAddressFromPosition(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Construct a detailed address prioritizing street-level info
        // Format: "Street, Sub-locality/Building, City" or fallback to less specific
        final List<String> parts = [];

        // Add street name if available (most specific)
        if (place.street != null && 
            place.street!.isNotEmpty && 
            place.street != place.name) {
          parts.add(place.street!);
        }
        
        // Add sub-locality (neighborhood/building area)
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          parts.add(place.subLocality!);
        }

        // Add city
        if (place.locality != null && place.locality!.isNotEmpty) {
          parts.add(place.locality!);
        }

        // If we have at least some info, return it
        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
        
        // Fallback: try administrative area and country
        final List<String> fallbackParts = [];
        if (place.administrativeArea != null &&
            place.administrativeArea!.isNotEmpty) {
          fallbackParts.add(place.administrativeArea!);
        }
        if (place.country != null && place.country!.isNotEmpty) {
          fallbackParts.add(place.country!);
        }
        
        if (fallbackParts.isNotEmpty) {
          return fallbackParts.join(', ');
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error decoding address: $e');
      return null;
    }
  }
}
