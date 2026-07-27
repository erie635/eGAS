// ============================================================
// FILE: location_service.dart - COMPLETE WITH IMPROVEMENTS
// ============================================================

import 'package:geolocator/geolocator.dart';

class LocationService {
  // ✅ ADDED: Constants for accuracy settings
  static const LocationAccuracy _defaultAccuracy = LocationAccuracy.high;
  static const int _defaultTimeLimit = 10; // seconds
  
  // ✅ ADDED: Error types for better handling
  static const String errorServiceDisabled = 'LOCATION_SERVICE_DISABLED';
  static const String errorPermissionDenied = 'LOCATION_PERMISSION_DENIED';
  static const String errorPermissionDeniedForever = 'LOCATION_PERMISSION_DENIED_FOREVER';
  static const String errorTimeout = 'LOCATION_TIMEOUT';
  static const String errorUnknown = 'LOCATION_UNKNOWN_ERROR';

  /// Get current location with proper permission handling
  static Future<Position> getCurrentLocation() async {
    try {
      // ✅ IMPROVED: Check if location services are enabled
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw Exception('Location services are disabled. Please enable GPS.');
      }

      // ✅ IMPROVED: Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied. Please grant permission.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied. Please enable in settings.');
      }

      // ✅ IMPROVED: Get current position with timeout handling
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: _defaultAccuracy,
          timeLimit: const Duration(seconds: _defaultTimeLimit),
        );
        return position;
      } catch (e) {
        // ✅ ADDED: Handle timeout or other errors
        if (e.toString().contains('timeout')) {
          throw Exception('Location request timed out. Please try again.');
        }
        rethrow;
      }
      
    } catch (e) {
      // ✅ IMPROVED: Re-throw with better error message
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Failed to get location: ${e.toString()}');
    }
  }

  /// ✅ ADDED: Get current location with custom accuracy
  static Future<Position> getCurrentLocationWithAccuracy(
    LocationAccuracy accuracy,
  ) async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw Exception('Location services are disabled. Please enable GPS.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied. Please grant permission.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied. Please enable in settings.');
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: const Duration(seconds: _defaultTimeLimit),
      );
      
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Failed to get location: ${e.toString()}');
    }
  }

  /// ✅ ADDED: Check if location services are enabled
  static Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      return false;
    }
  }

  /// ✅ ADDED: Check location permission status
  static Future<LocationPermission> checkPermission() async {
    try {
      return await Geolocator.checkPermission();
    } catch (e) {
      return LocationPermission.denied;
    }
  }

  /// ✅ ADDED: Request location permission
  static Future<LocationPermission> requestPermission() async {
    try {
      return await Geolocator.requestPermission();
    } catch (e) {
      return LocationPermission.denied;
    }
  }

  /// ✅ ADDED: Open location settings
  static Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      return false;
    }
  }

  /// ✅ ADDED: Get location status with detailed information
  static Future<Map<String, dynamic>> getLocationStatus() async {
    final Map<String, dynamic> status = {};
    
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      status['serviceEnabled'] = serviceEnabled;
      
      final permission = await Geolocator.checkPermission();
      status['permission'] = permission.toString();
      status['permissionGranted'] = permission == LocationPermission.always || 
                                    permission == LocationPermission.whileInUse;
      
      if (serviceEnabled && (permission == LocationPermission.always || 
          permission == LocationPermission.whileInUse)) {
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: _defaultAccuracy,
            timeLimit: const Duration(seconds: 2),
          );
          status['canGetLocation'] = true;
          status['lastLatitude'] = position.latitude;
          status['lastLongitude'] = position.longitude;
        } catch (e) {
          status['canGetLocation'] = false;
          status['error'] = e.toString();
        }
      } else {
        status['canGetLocation'] = false;
      }
      
      return status;
    } catch (e) {
      return {
        'serviceEnabled': false,
        'permission': 'unknown',
        'permissionGranted': false,
        'canGetLocation': false,
        'error': e.toString(),
      };
    }
  }

  /// ✅ ADDED: Calculate distance between two positions
  static double calculateDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    try {
      return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    } catch (e) {
      return 0.0;
    }
  }

  /// ✅ ADDED: Calculate distance in kilometers
  static double calculateDistanceInKm({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    try {
      final meters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
      return meters / 1000.0; // Convert to kilometers
    } catch (e) {
      return 0.0;
    }
  }

  /// ✅ ADDED: Get bearing between two positions
  static double calculateBearing({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    try {
      return Geolocator.bearingBetween(lat1, lng1, lat2, lng2);
    } catch (e) {
      return 0.0;
    }
  }

  /// ✅ ADDED: Get heading from current position to destination
  static Future<double> getHeadingToDestination({
    required double destLat,
    required double destLng,
  }) async {
    try {
      final currentPos = await getCurrentLocation();
      return Geolocator.bearingBetween(
        currentPos.latitude,
        currentPos.longitude,
        destLat,
        destLng,
      );
    } catch (e) {
      return 0.0;
    }
  }

  /// ✅ ADDED: Check if a position is near another position
  static bool isNear({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
    double thresholdMeters = 100.0,
  }) {
    try {
      final distance = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
      return distance <= thresholdMeters;
    } catch (e) {
      return false;
    }
  }

  /// ✅ ADDED: Format position for display
  static String formatPosition(Position position) {
    return '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
  }

  /// ✅ ADDED: Get position as map
  static Map<String, double> positionToMap(Position position) {
    return {
      'lat': position.latitude,
      'lng': position.longitude,
      'altitude': position.altitude,
      'accuracy': position.accuracy,
      'speed': position.speed,
      'heading': position.heading ?? 0.0,
    };
  }

  /// ✅ ADDED: Create Position from lat/lng
  static Position positionFromLatLng({
    required double latitude,
    required double longitude,
    double? altitude,
    double? accuracy,
    double? speed,
    double? heading,
  }) {
    return Position(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude ?? 0.0,
      accuracy: accuracy ?? 0.0,
      speed: speed ?? 0.0,
      heading: heading ?? 0.0,
      timestamp: DateTime.now(),
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );
  }

  /// ✅ ADDED: Get location stream with proper handling
  static Stream<Position> getLocationStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 5, // meters
    int timeLimit = 10, // seconds
  }) async* {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        yield* Stream.error('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          yield* Stream.error('Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        yield* Stream.error('Location permissions are permanently denied');
        return;
      }

      await for (var position in Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
          timeLimit: Duration(seconds: timeLimit),
        ),
      )) {
        yield position;
      }
      
    } catch (e) {
      yield* Stream.error('Failed to get location stream: ${e.toString()}');
    }
  }

  /// ✅ ADDED: Get last known location (cached)
  static Future<Position?> getLastKnownLocation() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      return null;
    }
  }

  /// ✅ ADDED: Check if GPS is accurate enough
  static Future<bool> isLocationAccurate({
    double thresholdAccuracy = 20.0, // meters
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
      return position.accuracy <= thresholdAccuracy;
    } catch (e) {
      return false;
    }
  }
}

// ✅ ADDED: Extension for Position to add helper methods
extension PositionExtension on Position {
  /// Get distance to another position in meters
  double distanceTo(Position other) {
    return Geolocator.distanceBetween(
      latitude,
      longitude,
      other.latitude,
      other.longitude,
    );
  }

  /// Get distance to another position in kilometers
  double distanceToInKm(Position other) {
    final meters = Geolocator.distanceBetween(
      latitude,
      longitude,
      other.latitude,
      other.longitude,
    );
    return meters / 1000.0;
  }

  /// Get bearing to another position
  double bearingTo(Position other) {
    return Geolocator.bearingBetween(
      latitude,
      longitude,
      other.latitude,
      other.longitude,
    );
  }

  /// Check if near another position
  bool isNear(Position other, {double thresholdMeters = 100.0}) {
    return distanceTo(other) <= thresholdMeters;
  }

  /// Format as string
  String get formatted => '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  /// Convert to map
  Map<String, dynamic> toMap() {
    return {
      'lat': latitude,
      'lng': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
    };
  }
}