import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart'; // Keep for debugPrint

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
  Future<Position?> getCurrentLocation({bool isEmergency = false}) async {
    try {
      final permission = await checkPermission();

      if (permission == LocationPermission.denied) {
        // Optionally request permission here, or just return null
        debugPrint('Location permission denied');
        return null;
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        debugPrint('Location permission denied forever or unable to determine');
        return null;
      }
      // Check if location services are enabled
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        debugPrint('Location services are disabled');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: isEmergency ? LocationAccuracy.best : LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 15),
        ),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  /// Gets the address from a Position
  Future<String?> getAddressFromPosition(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Construct a readable address (e.g., "City, State" or "Street, City")
        final List<String> parts = [];

        if (place.locality != null && place.locality!.isNotEmpty) {
          parts.add(place.locality!);
        }

        if (place.administrativeArea != null &&
            place.administrativeArea!.isNotEmpty) {
          parts.add(place.administrativeArea!);
        }

        // If we don't have city/state, try other fields
        if (parts.isEmpty) {
          if (place.subLocality != null && place.subLocality!.isNotEmpty) {
            parts.add(place.subLocality!);
          }
          if (place.country != null && place.country!.isNotEmpty) {
            parts.add(place.country!);
          }
        }

        return parts.join(', ');
      }
      return null;
    } catch (e) {
      debugPrint('Error decoding address: $e');
      return null;
    }
  }
}
