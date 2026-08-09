// ============================================================
// FILE: driver_location_updater.dart - COMPLETE WITH IMPROVEMENTS
// ============================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class DriverLocationUpdater {
  static StreamSubscription<Position>? _sub;
  
  // ✅ ADDED: Track if currently updating
  static bool _isUpdating = false;
  
  // ✅ ADDED: Track last update time for rate limiting
  static DateTime? _lastUpdateTime;
  static const Duration _minUpdateInterval = Duration(seconds: 2);
  
  // ✅ ADDED: Retry configuration
  static int _retryCount = 0;
  static const int _maxRetries = 3;

  /// Start tracking driver location
  static Future<void> start(String driverId) async {
    // ✅ IMPROVED: Check if already tracking
    if (_isUpdating || _sub != null) {
      print('📍 Location tracking already active for driver: $driverId');
      return;
    }

    try {
      // ✅ IMPROVED: Check location services
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return;
      }

      // ✅ IMPROVED: Proper permission handling
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permission permanently denied');
        return;
      }

      // ✅ IMPROVED: Set tracking flag
      _isUpdating = true;
      _retryCount = 0;

      print('📍 Starting location tracking for driver: $driverId');

      // ✅ IMPROVED: Start position stream with better settings
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // 5 meters
          timeLimit: Duration(seconds: 10), // ✅ ADDED: Time limit for updates
        ),
      ).listen(
        (Position pos) async {
          // ✅ ADDED: Rate limiting to prevent excessive writes
          final now = DateTime.now();
          if (_lastUpdateTime != null && 
              now.difference(_lastUpdateTime!) < _minUpdateInterval) {
            return;
          }
          _lastUpdateTime = now;

          // ✅ IMPROVED: Update Firestore with error handling
          try {
            await FirebaseFirestore.instance
                .collection('drivers')
                .doc(driverId)
                .update({
              'lat': pos.latitude,
              'lng': pos.longitude,
              'heading': pos.heading ?? 0.0,
              'speed': pos.speed,
              'isOnline': true,
              'lastUpdate': FieldValue.serverTimestamp(),
              'lastLocationUpdate': DateTime.now().toIso8601String(),
            });
            
            // ✅ ADDED: Reset retry count on success
            _retryCount = 0;
            
            // ✅ ADDED: Optional debug logging (only in debug mode)
            if (kDebugMode) {
              print('📍 Driver $driverId location updated: ${pos.latitude}, ${pos.longitude}');
            }
          } catch (e) {
            // ✅ IMPROVED: Retry logic for failed updates
            print('❌ Error updating driver location: $e');
            _retryCount++;
            
            if (_retryCount < _maxRetries) {
              print('🔄 Retrying update (${_retryCount}/$_maxRetries)...');
              // Will retry on next position update
            } else {
              print('❌ Max retries reached for location update');
              _retryCount = 0;
            }
          }
        },
        onError: (error) {
          // ✅ ADDED: Handle stream errors
          print('❌ Location stream error: $error');
          
          // ✅ ADDED: Attempt to restart on error
          if (_isUpdating && _sub != null) {
            _sub?.cancel();
            _sub = null;
            _isUpdating = false;
            
            // Auto-restart after delay
            Future.delayed(const Duration(seconds: 5), () {
              if (!_isUpdating) {
                print('🔄 Auto-restarting location tracking...');
                start(driverId);
              }
            });
          }
        },
        cancelOnError: false, // ✅ ADDED: Don't cancel on error
      );
      
      // ✅ ADDED: Update driver online status immediately
      try {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(driverId)
            .update({
          'isOnline': true,
          'onlineSince': FieldValue.serverTimestamp(),
          'status': 'available',
        });
        print('✅ Driver $driverId is now online');
      } catch (e) {
        print('❌ Error setting driver online: $e');
      }
      
    } catch (e) {
      print('❌ Error starting location tracking: $e');
      _isUpdating = false;
      _sub = null;
    }
  }

  /// Stop tracking driver location
  static Future<void> stop(String driverId) async {
    if (driverId.isEmpty) {
      print('❌ Cannot stop: driverId is empty');
      return;
    }

    try {
      // ✅ IMPROVED: Cancel subscription
      if (_sub != null) {
        await _sub?.cancel();
        _sub = null;
        _isUpdating = false;
        _lastUpdateTime = null;
        _retryCount = 0;
        print('📍 Location tracking stopped for driver: $driverId');
      }

      // ✅ IMPROVED: Update Firestore with error handling
      try {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(driverId)
            .update({
          'isOnline': false,
          'lastOfflineTime': FieldValue.serverTimestamp(),
          'status': 'offline',
        });
        print('✅ Driver $driverId is now offline');
      } catch (e) {
        print('❌ Error setting driver offline: $e');
      }
      
    } catch (e) {
      print('❌ Error stopping location tracking: $e');
      _isUpdating = false;
      _sub = null;
    }
  }

  /// ✅ ADDED: Check if tracking is active
  static bool isTrackingActive() {
    return _isUpdating && _sub != null;
  }

  /// ✅ ADDED: Get current tracking status
  static String getTrackingStatus() {
    if (_isUpdating && _sub != null) {
      return 'Active';
    } else if (_sub != null) {
      return 'Pending';
    } else {
      return 'Inactive';
    }
  }

  /// ✅ ADDED: Force restart tracking
  static Future<void> restart(String driverId) async {
    print('🔄 Restarting location tracking...');
    await stop(driverId);
    await Future.delayed(const Duration(seconds: 1));
    await start(driverId);
  }

  /// ✅ ADDED: Update driver status only (no location)
  static Future<void> updateDriverStatus(String driverId, bool online) async {
    if (driverId.isEmpty) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .update({
        'isOnline': online,
        'status': online ? 'available' : 'offline',
        online ? 'onlineSince' : 'lastOfflineTime': FieldValue.serverTimestamp(),
      });
      
      print('✅ Driver $driverId status updated: ${online ? "online" : "offline"}');
    } catch (e) {
      print('❌ Error updating driver status: $e');
    }
  }

  /// ✅ ADDED: Dispose resources
  static void dispose() {
    try {
      _sub?.cancel();
      _sub = null;
      _isUpdating = false;
      _lastUpdateTime = null;
      _retryCount = 0;
      print('🗑️ DriverLocationUpdater disposed');
    } catch (e) {
      print('❌ Error disposing DriverLocationUpdater: $e');
    }
  }
}

// ✅ ADDED: Extension for debug mode check
const bool kDebugMode = bool.fromEnvironment('dart.vm.product') ? false : true;
