// ============================================================
// FILE: tracking_service.dart - COMPLETE WITH PRODUCTION FIXES
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class TrackingService {
  static final db = FirebaseFirestore.instance;
  
  // ============================================================
  // STATUS CONSTANTS
  // ============================================================
  static const String statusAvailable = 'available';
  static const String statusBusy = 'busy';
  static const String statusOffline = 'offline';
  static const String statusOnBreak = 'on_break';
  static const String statusEnRoute = 'en_route';
  static const String statusDelivering = 'delivering';
  
  // ============================================================
  // COLLECTION & SUBCOLLECTION PATHS
  // ============================================================
  static const String _driversCollection = 'drivers';
  static const String _locationHistorySubcollection = 'locationHistory';
  static const String _statusHistorySubcollection = 'statusHistory';
  static const int _maxHistoryEntries = 50; // Limit for memory/performance

  // ============================================================
  // STREAM ALL DRIVERS - Original preserved
  // ============================================================
  
  /// Streams all drivers in real-time.
  static Stream<QuerySnapshot> streamDrivers() {
    return db.collection(_driversCollection).snapshots();
  }

  // ============================================================
  // STREAM SINGLE DRIVER - Original preserved
  // ============================================================
  
  /// Streams a single driver document in real-time by [driverId].
  static Stream<DocumentSnapshot> streamDriver(String driverId) {
    return db.collection(_driversCollection).doc(driverId).snapshots();
  }

  // ============================================================
  // SET DRIVER STATUS - Original with improvements
  // ============================================================
  
  /// Updates the status of a driver by [id].
  static Future<bool> setDriverStatus(String id, String status) async {
    if (id.isEmpty) {
      print('❌ TrackingService: driverId cannot be empty');
      return false;
    }
    
    if (!_isValidStatus(status)) {
      print('❌ TrackingService: Invalid status: $status');
      return false;
    }

    try {
      // ✅ FIXED: Use batch write for atomic updates
      final batch = db.batch();
      
      // 1. Update main driver document
      final driverRef = db.collection(_driversCollection).doc(id);
      batch.update(driverRef, {
        'status': status,
        'lastStatusChange': FieldValue.serverTimestamp(),
      });
      
      // 2. Add to status history as a separate document (not array)
      final historyRef = driverRef.collection(_statusHistorySubcollection).doc();
      batch.set(historyRef, {
        'status': status,
        'timestamp': FieldValue.serverTimestamp(),
        'date': DateTime.now().toIso8601String(),
        'driverId': id,
      });
      
      await batch.commit();
      
      // ✅ FIXED: Clean up old history entries using subcollection
      await _cleanupOldHistory(id);
      
      print('✅ TrackingService: Driver $id status updated to: $status');
      return true;
      
    } catch (e) {
      print('❌ TrackingService: Error updating driver status: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ FIXED: Clean up old history using subcollection
  // ============================================================
  static Future<void> _cleanupOldHistory(String driverId) async {
    try {
      final historySnapshot = await db
          .collection(_driversCollection)
          .doc(driverId)
          .collection(_statusHistorySubcollection)
          .orderBy('timestamp', descending: true)
          .get();
      
      if (historySnapshot.docs.length > _maxHistoryEntries) {
        final batch = db.batch();
        final docsToRemove = historySnapshot.docs.sublist(_maxHistoryEntries);
        
        for (var doc in docsToRemove) {
          batch.delete(doc.reference);
        }
        
        await batch.commit();
        print('✅ TrackingService: Cleaned up ${docsToRemove.length} old history entries');
      }
    } catch (e) {
      // Ignore cleanup errors
      print('⚠️ TrackingService: History cleanup warning: $e');
    }
  }

  // ============================================================
  // ✅ FIXED: Stream online drivers only
  // ============================================================
  
  /// Streams only online drivers in real-time.
  static Stream<QuerySnapshot> streamOnlineDrivers() {
    return db.collection(_driversCollection)
        .where('online', isEqualTo: true)
        .where('status', whereNotIn: ['offline', 'on_break'])
        .snapshots();
  }

  // ============================================================
  // ✅ FIXED: Stream available drivers
  // ============================================================
  
  /// Streams only available drivers (ready to accept orders).
  static Stream<QuerySnapshot> streamAvailableDrivers() {
    return db.collection(_driversCollection)
        .where('online', isEqualTo: true)
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: statusAvailable)
        .snapshots();
  }

  // ============================================================
  // ✅ IMPROVED: Stream drivers by location using geohash
  // ============================================================
  
  /// Streams drivers near a specific location using geohashing.
  /// For production use, implement actual geohash queries.
  static Stream<QuerySnapshot> streamNearbyDrivers({
    required double lat,
    required double lng,
    double radiusKm = 10.0,
  }) {
    // ⚠️ IMPORTANT: This is a basic implementation.
    // For production, use GeoFire or Firestore geohash queries.
    // Example: Add a 'geohash' field to driver documents and query it.
    return db.collection(_driversCollection)
        .where('online', isEqualTo: true)
        .where('isAvailable', isEqualTo: true)
        .snapshots();
  }

  // ============================================================
  // ✅ IMPROVED: Get nearby drivers with actual distance calculation
  // ============================================================
  
  /// Gets all drivers near a specific location.
  /// Uses geohash for efficient querying (if implemented).
  static Future<List<Map<String, dynamic>>> getNearbyDrivers({
    required double lat,
    required double lng,
    double radiusKm = 10.0,
  }) async {
    try {
      // ⚠️ PRODUCTION IMPROVEMENT:
      // Add a 'geohash' field to driver documents and use it here.
      // For now, we fetch all online drivers and filter.
      
      final query = await db.collection(_driversCollection)
          .where('online', isEqualTo: true)
          .where('isAvailable', isEqualTo: true)
          .get();
      
      final nearbyDrivers = <Map<String, dynamic>>[];
      
      for (var doc in query.docs) {
        final data = doc.data();
        final driverLat = data['lat'] as double?;
        final driverLng = data['lng'] as double?;
        
        if (driverLat != null && driverLng != null) {
          final distance = Geolocator.distanceBetween(lat, lng, driverLat, driverLng) / 1000;
          
          if (distance <= radiusKm) {
            nearbyDrivers.add({
              'id': doc.id,
              ...data,
              'distanceKm': double.parse(distance.toStringAsFixed(2)),
            });
          }
        }
      }
      
      // Sort by distance
      nearbyDrivers.sort((a, b) => (a['distanceKm'] ?? 0.0).compareTo(b['distanceKm'] ?? 0.0));
      
      return nearbyDrivers;
      
    } catch (e) {
      print('❌ TrackingService: Error getting nearby drivers: $e');
      return [];
    }
  }

  // ============================================================
  // ✅ FIXED: Update driver location with subcollection
  // ============================================================
  
  /// Updates the location of a driver.
  static Future<bool> updateDriverLocation(
    String driverId,
    double lat,
    double lng,
  ) async {
    if (driverId.isEmpty) {
      print('❌ TrackingService: driverId cannot be empty');
      return false;
    }

    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      print('❌ TrackingService: Invalid coordinates: lat=$lat, lng=$lng');
      return false;
    }

    try {
      final batch = db.batch();
      final driverRef = db.collection(_driversCollection).doc(driverId);
      
      // 1. Update main driver document
      batch.update(driverRef, {
        'lat': lat,
        'lng': lng,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
      
      // 2. Add to location history as a separate document
      final historyRef = driverRef.collection(_locationHistorySubcollection).doc();
      batch.set(historyRef, {
        'lat': lat,
        'lng': lng,
        'timestamp': FieldValue.serverTimestamp(),
        'date': DateTime.now().toIso8601String(),
        'driverId': driverId,
      });
      
      await batch.commit();
      
      // 3. Clean up old location history
      await _cleanupOldLocationHistory(driverId);
      
      print('✅ TrackingService: Driver $driverId location updated');
      return true;
      
    } catch (e) {
      print('❌ TrackingService: Error updating driver location: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ FIXED: Clean up old location history using subcollection
  // ============================================================
  static Future<void> _cleanupOldLocationHistory(String driverId) async {
    try {
      final historySnapshot = await db
          .collection(_driversCollection)
          .doc(driverId)
          .collection(_locationHistorySubcollection)
          .orderBy('timestamp', descending: true)
          .get();
      
      if (historySnapshot.docs.length > _maxHistoryEntries) {
        final batch = db.batch();
        final docsToRemove = historySnapshot.docs.sublist(_maxHistoryEntries);
        
        for (var doc in docsToRemove) {
          batch.delete(doc.reference);
        }
        
        await batch.commit();
        print('✅ TrackingService: Cleaned up ${docsToRemove.length} old location history entries');
      }
    } catch (e) {
      // Ignore cleanup errors
      print('⚠️ TrackingService: Location history cleanup warning: $e');
    }
  }

  // ============================================================
  // ✅ NEW: Get driver location history from subcollection
  // ============================================================
  
  /// Gets the location history of a driver.
  static Future<List<Map<String, dynamic>>> getDriverLocationHistory(
    String driverId, {
    int limit = 20,
  }) async {
    if (driverId.isEmpty) {
      print('❌ TrackingService: driverId cannot be empty');
      return [];
    }

    try {
      final query = await db
          .collection(_driversCollection)
          .doc(driverId)
          .collection(_locationHistorySubcollection)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      
      return query.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        };
      }).toList();
      
    } catch (e) {
      print('❌ TrackingService: Error getting location history: $e');
      return [];
    }
  }

  // ============================================================
  // ✅ NEW: Get driver status history from subcollection
  // ============================================================
  
  /// Gets the status history of a driver.
  static Future<List<Map<String, dynamic>>> getDriverStatusHistory(
    String driverId, {
    int limit = 20,
  }) async {
    if (driverId.isEmpty) {
      print('❌ TrackingService: driverId cannot be empty');
      return [];
    }

    try {
      final query = await db
          .collection(_driversCollection)
          .doc(driverId)
          .collection(_statusHistorySubcollection)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      
      return query.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        };
      }).toList();
      
    } catch (e) {
      print('❌ TrackingService: Error getting status history: $e');
      return [];
    }
  }

  // ============================================================
  // ✅ NEW: Stream driver location history in real-time
  // ============================================================
  
  /// Streams the location history of a driver in real-time.
  static Stream<QuerySnapshot> streamDriverLocationHistory(
    String driverId,
  ) {
    return db
        .collection(_driversCollection)
        .doc(driverId)
        .collection(_locationHistorySubcollection)
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots();
  }

  // ============================================================
  // ✅ NEW: Stream driver status history in real-time
  // ============================================================
  
  /// Streams the status history of a driver in real-time.
  static Stream<QuerySnapshot> streamDriverStatusHistory(
    String driverId,
  ) {
    return db
        .collection(_driversCollection)
        .doc(driverId)
        .collection(_statusHistorySubcollection)
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots();
  }

  // ============================================================
  // ✅ NEW: Generate geohash for location
  // ============================================================
  
  /// Generates a geohash for a location.
  /// For production, use a proper geohash library.
  static String generateGeohash(double lat, double lng) {
    // ⚠️ NOTE: This is a placeholder implementation.
    // Use a proper geohash library like 'geohash' package in production.
    // Example: geohash.encode(lat, lng, precision: 8);
    return '${lat.toStringAsFixed(3)}_${lng.toStringAsFixed(3)}';
  }

  // ============================================================
  // ✅ NEW: Update driver geohash for efficient queries
  // ============================================================
  
  /// Updates the geohash of a driver for efficient location queries.
  static Future<bool> updateDriverGeohash(
    String driverId,
    double lat,
    double lng,
  ) async {
    if (driverId.isEmpty) {
      print('❌ TrackingService: driverId cannot be empty');
      return false;
    }

    try {
      final geohash = generateGeohash(lat, lng);
      
      await db.collection(_driversCollection).doc(driverId).update({
        'geohash': geohash,
        'lat': lat,
        'lng': lng,
        'lastGeohashUpdate': FieldValue.serverTimestamp(),
      });
      
      print('✅ TrackingService: Driver $driverId geohash updated: $geohash');
      return true;
      
    } catch (e) {
      print('❌ TrackingService: Error updating driver geohash: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ NEW: Get drivers by geohash prefix
  // ============================================================
  
  /// Gets drivers by geohash prefix (for efficient location queries).
  static Future<List<Map<String, dynamic>>> getDriversByGeohashPrefix(
    String geohashPrefix,
  ) async {
    if (geohashPrefix.isEmpty) {
      print('❌ TrackingService: geohashPrefix cannot be empty');
      return [];
    }

    try {
      final query = await db.collection(_driversCollection)
          .where('online', isEqualTo: true)
          .where('geohash', isGreaterThanOrEqualTo: geohashPrefix)
          .where('geohash', isLessThan: geohashPrefix + 'z')
          .get();
      
      return query.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        };
      }).toList();
      
    } catch (e) {
      print('❌ TrackingService: Error getting drivers by geohash: $e');
      return [];
    }
  }

  // ============================================================
  // HELPER: Validate status
  // ============================================================
  static bool _isValidStatus(String status) {
    return status == statusAvailable ||
           status == statusBusy ||
           status == statusOffline ||
           status == statusOnBreak ||
           status == statusEnRoute ||
           status == statusDelivering;
  }

  // ============================================================
  // UI HELPERS - Preserved from original
  // ============================================================
  static String getStatusDisplayName(String status) {
    switch (status) {
      case statusAvailable:
        return 'Available';
      case statusBusy:
        return 'Busy';
      case statusOffline:
        return 'Offline';
      case statusOnBreak:
        return 'On Break';
      case statusEnRoute:
        return 'En Route';
      case statusDelivering:
        return 'Delivering';
      default:
        return status;
    }
  }

  static String getStatusColor(String status) {
    switch (status) {
      case statusAvailable:
        return '#4CAF50';
      case statusBusy:
        return '#FF9800';
      case statusOffline:
        return '#9E9E9E';
      case statusOnBreak:
        return '#FFC107';
      case statusEnRoute:
        return '#2196F3';
      case statusDelivering:
        return '#F44336';
      default:
        return '#9E9E9E';
    }
  }

  static String getStatusIcon(String status) {
    switch (status) {
      case statusAvailable:
        return '🟢';
      case statusBusy:
        return '🟠';
      case statusOffline:
        return '⚫';
      case statusOnBreak:
        return '🟡';
      case statusEnRoute:
        return '🔵';
      case statusDelivering:
        return '🔴';
      default:
        return '⚪';
    }
  }

  // ============================================================
  // ✅ NEW: Get driver document schema validation
  // ============================================================
  
  /// Validates that a driver document has all required fields.
  static bool validateDriverDocument(Map<String, dynamic> data) {
    final requiredFields = [
      'id',
      'online',
      'isAvailable',
      'status',
      'lat',
      'lng',
      'name',
      'phone',
      'vehicleType',
      'numberPlate',
    ];
    
    for (var field in requiredFields) {
      if (!data.containsKey(field)) {
        print('⚠️ TrackingService: Missing required field: $field');
        return false;
      }
    }
    
    return true;
  }

  // ============================================================
  // ✅ NEW: Create driver document with default fields
  // ============================================================
  
  /// Creates a new driver document with default values.
  static Future<bool> createDriverDocument({
    required String driverId,
    required String name,
    required String phone,
    required String vehicleType,
    required String numberPlate,
    Map<String, dynamic>? additionalData,
  }) async {
    if (driverId.isEmpty) {
      print('❌ TrackingService: driverId cannot be empty');
      return false;
    }

    try {
      final driverData = {
        'online': false,
        'isAvailable': false,
        'status': statusOffline,
        'lat': 0.0,
        'lng': 0.0,
        'name': name,
        'phone': phone,
        'vehicleType': vehicleType,
        'numberPlate': numberPlate,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        ...?additionalData,
      };
      
      await db.collection(_driversCollection).doc(driverId).set(driverData);
      
      print('✅ TrackingService: Driver $driverId document created');
      return true;
      
    } catch (e) {
      print('❌ TrackingService: Error creating driver document: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ NEW: Get driver statistics
  // ============================================================
  
  /// Gets statistics for a driver.
  static Future<Map<String, dynamic>> getDriverStatistics(String driverId) async {
    if (driverId.isEmpty) {
      return {};
    }

    try {
      // Get status history count
      final statusCount = await db
          .collection(_driversCollection)
          .doc(driverId)
          .collection(_statusHistorySubcollection)
          .count()
          .get();
      
      // Get location history count
      final locationCount = await db
          .collection(_driversCollection)
          .doc(driverId)
          .collection(_locationHistorySubcollection)
          .count()
          .get();
      
      // Get driver document
      final driverDoc = await db.collection(_driversCollection).doc(driverId).get();
      
      if (!driverDoc.exists) {
        return {};
      }
      
      final data = driverDoc.data()!;
      
      return {
        'totalStatusChanges': statusCount.count ?? 0,
        'totalLocationUpdates': locationCount.count ?? 0,
        'isOnline': data['online'] ?? false,
        'isAvailable': data['isAvailable'] ?? false,
        'currentStatus': data['status'] ?? statusOffline,
        'lastLocationUpdate': data['lastLocationUpdate'],
        'lastStatusChange': data['lastStatusChange'],
      };
      
    } catch (e) {
      print('❌ TrackingService: Error getting driver statistics: $e');
      return {};
    }
  }
}