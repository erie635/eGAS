// ============================================================
// FILE: driver_service.dart - COMPLETE WITH IMPROVEMENTS
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class DriverService {
  static final db = FirebaseFirestore.instance;
  
  // ✅ ADDED: Collection name constants
  static const String _driversCollection = 'drivers';
  static const String _fuelRequestsCollection = 'fuel_requests';
  
  // ✅ ADDED: Status constants
  static const String statusPending = 'pending';
  static const String statusAccepted = 'accepted';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';
  static const String statusRejected = 'rejected';

  // ============================================================
  // GO ONLINE/OFFLINE - IMPROVED
  // ============================================================
  static Future<bool> setOnline(String driverId, bool online) async {
    if (driverId.isEmpty) {
      print('❌ DriverService: driverId cannot be empty');
      return false;
    }

    try {
      final updateData = {
        'online': online,
        'lastStatusChange': FieldValue.serverTimestamp(),
        'status': online ? 'available' : 'offline',
      };
      
      // ✅ ADDED: Additional fields when going online
      if (online) {
        updateData['onlineSince'] = FieldValue.serverTimestamp();
        updateData['lastOnlineTime'] = FieldValue.serverTimestamp();
        updateData['isAvailable'] = true;
      } else {
        updateData['offlineSince'] = FieldValue.serverTimestamp();
        updateData['lastOfflineTime'] = FieldValue.serverTimestamp();
        updateData['isAvailable'] = false;
        // ✅ ADDED: Clear current request when going offline
        updateData['currentRequestId'] = null;
      }

      await db.collection(_driversCollection).doc(driverId).set(
        updateData,
        SetOptions(merge: true),
      );
      
      print('✅ DriverService: Driver $driverId is now ${online ? "online" : "offline"}');
      return true;
      
    } catch (e) {
      print('❌ DriverService: Error setting driver online status: $e');
      return false;
    }
  }

  // ============================================================
  // UPDATE LOCATION (REAL TIME) - IMPROVED
  // ============================================================
  static Future<bool> updateLocation(
    String driverId,
    double lat,
    double lng,
  ) async {
    if (driverId.isEmpty) {
      print('❌ DriverService: driverId cannot be empty');
      return false;
    }

    // ✅ ADDED: Validate coordinates
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      print('❌ DriverService: Invalid coordinates: lat=$lat, lng=$lng');
      return false;
    }

    try {
      await db.collection(_driversCollection).doc(driverId).set(
        {
          'lat': lat,
          'lng': lng,
          'lastLocationUpdate': FieldValue.serverTimestamp(),
          'lastKnownLat': lat,
          'lastKnownLng': lng,
          'locationHistory': FieldValue.arrayUnion([
            {
              'lat': lat,
              'lng': lng,
              'timestamp': DateTime.now().toIso8601String(),
            }
          ]),
        },
        SetOptions(merge: true),
      );
      
      // ✅ ADDED: Limit location history to last 50 entries
      try {
        await db.collection(_driversCollection).doc(driverId).update({
          'locationHistory': FieldValue.arrayRemove(
            await _getOldLocationHistory(driverId)
          ),
        });
      } catch (e) {
        // Ignore history cleanup errors
      }
      
      print('✅ DriverService: Driver $driverId location updated: lat=$lat, lng=$lng');
      return true;
      
    } catch (e) {
      print('❌ DriverService: Error updating driver location: $e');
      return false;
    }
  }

  // ✅ ADDED: Helper to get old location history entries
  static Future<List<Map<String, dynamic>>> _getOldLocationHistory(String driverId) async {
    try {
      final doc = await db.collection(_driversCollection).doc(driverId).get();
      if (doc.exists) {
        final data = doc.data();
        final history = List<Map<String, dynamic>>.from(data?['locationHistory'] ?? []);
        if (history.length > 50) {
          return history.sublist(0, history.length - 50);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ============================================================
  // ACCEPT REQUEST - IMPROVED WITH BATCH WRITE
  // ============================================================
  static Future<bool> acceptRequest(
    String driverId,
    String requestId,
  ) async {
    if (driverId.isEmpty || requestId.isEmpty) {
      print('❌ DriverService: driverId or requestId cannot be empty');
      return false;
    }

    try {
      // ✅ IMPROVED: Use batch write for atomicity
      final batch = db.batch();

      // 1. Update fuel request
      final requestRef = db.collection(_fuelRequestsCollection).doc(requestId);
      batch.update(requestRef, {
        'driverId': driverId,
        'status': statusAccepted,
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedBy': driverId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Update driver
      final driverRef = db.collection(_driversCollection).doc(driverId);
      batch.update(driverRef, {
        'currentRequestId': requestId,
        'lastRequestAcceptedAt': FieldValue.serverTimestamp(),
        'status': 'busy',
        'isAvailable': false,
        'activeOrderId': requestId,
      });

      // ✅ ADDED: 3. Create notification for customer
      try {
        final requestDoc = await requestRef.get();
        if (requestDoc.exists) {
          final requestData = requestDoc.data() as Map<String, dynamic>;
          final notificationRef = db.collection('notifications').doc();
          batch.set(notificationRef, {
            'userId': requestData['userId'],
            'driverId': driverId,
            'type': 'request_accepted',
            'title': 'Request Accepted',
            'body': 'Your fuel delivery request has been accepted by a driver',
            'requestId': requestId,
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        print('⚠️ DriverService: Failed to create notification: $e');
      }

      await batch.commit();
      
      print('✅ DriverService: Driver $driverId accepted request $requestId');
      return true;
      
    } catch (e) {
      print('❌ DriverService: Error accepting request: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ ADDED: Complete a delivery
  // ============================================================
  static Future<bool> completeDelivery(String driverId, String requestId) async {
    if (driverId.isEmpty || requestId.isEmpty) {
      print('❌ DriverService: driverId or requestId cannot be empty');
      return false;
    }

    try {
      final batch = db.batch();

      // Update request
      final requestRef = db.collection(_fuelRequestsCollection).doc(requestId);
      batch.update(requestRef, {
        'status': statusCompleted,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update driver
      final driverRef = db.collection(_driversCollection).doc(driverId);
      batch.update(driverRef, {
        'currentRequestId': null,
        'activeOrderId': null,
        'status': 'available',
        'isAvailable': true,
        'totalDeliveries': FieldValue.increment(1),
        'lastCompletedDelivery': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      
      print('✅ DriverService: Driver $driverId completed delivery $requestId');
      return true;
      
    } catch (e) {
      print('❌ DriverService: Error completing delivery: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ ADDED: Cancel a delivery
  // ============================================================
  static Future<bool> cancelDelivery(
    String driverId, 
    String requestId, 
    {String? reason}
  ) async {
    if (driverId.isEmpty || requestId.isEmpty) {
      print('❌ DriverService: driverId or requestId cannot be empty');
      return false;
    }

    try {
      final batch = db.batch();

      // Update request
      final requestRef = db.collection(_fuelRequestsCollection).doc(requestId);
      final updateData = {
        'status': statusCancelled,
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': driverId,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (reason != null && reason.isNotEmpty) {
        updateData['cancellationReason'] = reason;
      }
      batch.update(requestRef, updateData);

      // Update driver
      final driverRef = db.collection(_driversCollection).doc(driverId);
      batch.update(driverRef, {
        'currentRequestId': null,
        'activeOrderId': null,
        'status': 'available',
        'isAvailable': true,
      });

      await batch.commit();
      
      print('✅ DriverService: Driver $driverId cancelled delivery $requestId${reason != null ? " (Reason: $reason)" : ""}');
      return true;
      
    } catch (e) {
      print('❌ DriverService: Error cancelling delivery: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ ADDED: Get driver by ID
  // ============================================================
  static Future<Map<String, dynamic>?> getDriver(String driverId) async {
    if (driverId.isEmpty) {
      print('❌ DriverService: driverId cannot be empty');
      return null;
    }

    try {
      final doc = await db.collection(_driversCollection).doc(driverId).get();
      if (doc.exists) {
        return {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        };
      } else {
        print('⚠️ DriverService: Driver $driverId not found');
        return null;
      }
    } catch (e) {
      print('❌ DriverService: Error getting driver: $e');
      return null;
    }
  }

  // ============================================================
  // ✅ ADDED: Get all online drivers
  // ============================================================
  static Future<List<Map<String, dynamic>>> getOnlineDrivers() async {
    try {
      final query = await db.collection(_driversCollection)
          .where('online', isEqualTo: true)
          .where('isAvailable', isEqualTo: true)
          .get();

      return query.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        };
      }).toList();
      
    } catch (e) {
      print('❌ DriverService: Error getting online drivers: $e');
      return [];
    }
  }

  // ============================================================
  // ✅ ADDED: Get nearby drivers
  // ============================================================
  static Future<List<Map<String, dynamic>>> getNearbyDrivers({
    required double lat,
    required double lng,
    double radiusKm = 10.0,
  }) async {
    try {
      // Note: This is a simple implementation.
      // For production, consider using GeoFire or Firestore geohashes.
      final drivers = await getOnlineDrivers();
      
      final nearby = <Map<String, dynamic>>[];
      for (var driver in drivers) {
        final driverLat = driver['lat'] as double?;
        final driverLng = driver['lng'] as double?;
        
        if (driverLat != null && driverLng != null) {
          final distance = _calculateDistance(lat, lng, driverLat, driverLng);
          if (distance <= radiusKm) {
            driver['distance'] = distance;
            nearby.add(driver);
          }
        }
      }
      
      // Sort by distance
      nearby.sort((a, b) => (a['distance'] ?? 0.0).compareTo(b['distance'] ?? 0.0));
      
      return nearby;
      
    } catch (e) {
      print('❌ DriverService: Error getting nearby drivers: $e');
      return [];
    }
  }

  // ============================================================
  // ✅ ADDED: Get driver's current request
  // ============================================================
  static Future<Map<String, dynamic>?> getCurrentRequest(String driverId) async {
    if (driverId.isEmpty) {
      print('❌ DriverService: driverId cannot be empty');
      return null;
    }

    try {
      final driver = await getDriver(driverId);
      if (driver == null) return null;
      
      final requestId = driver['currentRequestId'];
      if (requestId == null || requestId.isEmpty) {
        return null;
      }
      
      final doc = await db.collection(_fuelRequestsCollection).doc(requestId).get();
      if (doc.exists) {
        return {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        };
      }
      
      return null;
      
    } catch (e) {
      print('❌ DriverService: Error getting current request: $e');
      return null;
    }
  }

  // ============================================================
  // ✅ ADDED: Get driver's delivery history
  // ============================================================
  static Future<List<Map<String, dynamic>>> getDeliveryHistory(
    String driverId, {
    int limit = 20,
  }) async {
    if (driverId.isEmpty) {
      print('❌ DriverService: driverId cannot be empty');
      return [];
    }

    try {
      final query = await db.collection(_fuelRequestsCollection)
          .where('driverId', isEqualTo: driverId)
          .where('status', whereIn: [statusCompleted, statusCancelled])
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return query.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        };
      }).toList();
      
    } catch (e) {
      print('❌ DriverService: Error getting delivery history: $e');
      return [];
    }
  }

  // ============================================================
  // ✅ ADDED: Get driver statistics
  // ============================================================
  static Future<Map<String, dynamic>> getDriverStats(String driverId) async {
    if (driverId.isEmpty) {
      print('❌ DriverService: driverId cannot be empty');
      return {};
    }

    try {
      final driver = await getDriver(driverId);
      if (driver == null) return {};
      
      final completedOrders = await db.collection(_fuelRequestsCollection)
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: statusCompleted)
          .count()
          .get();
      
      final totalOrders = await db.collection(_fuelRequestsCollection)
          .where('driverId', isEqualTo: driverId)
          .count()
          .get();

      return {
        'totalDeliveries': driver['totalDeliveries'] ?? 0,
        'completedOrders': completedOrders.count ?? 0,
        'totalOrders': totalOrders.count ?? 0,
        'rating': driver['rating'] ?? 0.0,
        'totalEarnings': driver['totalEarnings'] ?? 0.0,
        'onlineSince': driver['onlineSince'],
        'isOnline': driver['online'] ?? false,
      };
      
    } catch (e) {
      print('❌ DriverService: Error getting driver stats: $e');
      return {};
    }
  }

  // ============================================================
  // ✅ ADDED: Update driver rating
  // ============================================================
  static Future<bool> updateRating(String driverId, double rating) async {
    if (driverId.isEmpty) {
      print('❌ DriverService: driverId cannot be empty');
      return false;
    }

    if (rating < 0 || rating > 5) {
      print('❌ DriverService: Invalid rating: $rating');
      return false;
    }

    try {
      final doc = await db.collection(_driversCollection).doc(driverId).get();
      if (!doc.exists) {
        print('❌ DriverService: Driver $driverId not found');
        return false;
      }

      final data = doc.data()!;
      final currentRating = data['rating'] ?? 0.0;
      final ratingCount = data['ratingCount'] ?? 0;
      
      final newRating = ((currentRating * ratingCount) + rating) / (ratingCount + 1);

      await db.collection(_driversCollection).doc(driverId).update({
        'rating': newRating,
        'ratingCount': ratingCount + 1,
        'lastRatingAt': FieldValue.serverTimestamp(),
      });

      print('✅ DriverService: Driver $driverId rating updated to: $newRating');
      return true;
      
    } catch (e) {
      print('❌ DriverService: Error updating rating: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ ADDED: Stream driver location (real-time)
  // ============================================================
  static Stream<DocumentSnapshot> streamDriverLocation(String driverId) {
    return db.collection(_driversCollection).doc(driverId).snapshots();
  }

  // ============================================================
  // ✅ ADDED: Stream online drivers
  // ============================================================
  static Stream<QuerySnapshot> streamOnlineDrivers() {
    return db.collection(_driversCollection)
        .where('online', isEqualTo: true)
        .where('isAvailable', isEqualTo: true)
        .snapshots();
  }

  // ============================================================
  // ✅ ADDED: Stream driver's current request
  // ============================================================
  static Stream<DocumentSnapshot> streamCurrentRequest(String driverId) {
    return db.collection(_driversCollection)
        .doc(driverId)
        .snapshots();
  }

  // ============================================================
  // HELPER: Calculate distance between two coordinates
  // ============================================================
  static double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double R = 6371; // Earth's radius in km
    final double dLat = _toRadians(lat2 - lat1);
    final double dLng = _toRadians(lng2 - lng1);
    
    final double a = 
      _sin(dLat / 2) * _sin(dLat / 2) +
      _cos(_toRadians(lat1)) * _cos(_toRadians(lat2)) * 
      _sin(dLng / 2) * _sin(dLng / 2);
    
    final double c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return R * c;
  }

  static double _toRadians(double degrees) {
    return degrees * 3.141592653589793 / 180.0;
  }

  static double _sin(double x) {
    return x - (x * x * x / 6) + (x * x * x * x * x / 120);
  }

  static double _cos(double x) {
    return 1 - (x * x / 2) + (x * x * x * x / 24);
  }

  static double _sqrt(double x) {
    return x > 0 ? x / (2 * _sqrtHelper(x)) : 0;
  }

  static double _sqrtHelper(double x) {
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  static double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0) {
      if (y >= 0) return _atan(y / x) + 3.141592653589793;
      return _atan(y / x) - 3.141592653589793;
    }
    if (y > 0) return 3.141592653589793 / 2;
    if (y < 0) return -3.141592653589793 / 2;
    return 0;
  }

  static double _atan(double x) {
    return x - (x * x * x / 3) + (x * x * x * x * x / 5);
  }
}