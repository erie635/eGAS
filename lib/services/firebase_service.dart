import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // COLLECTION REFERENCES
  // ============================================================
  static CollectionReference get drivers => _db.collection('drivers');
  static CollectionReference get orders => _db.collection('orders');
  static CollectionReference get requests => _db.collection('requests');
  static CollectionReference get customers => _db.collection('customers');
  static CollectionReference get cancellations => _db.collection('cancellations');

  // ============================================================
  // DRIVER METHODS
  // ============================================================

  /// Create a new driver document
  static Future<String> createDriver({
    required String userId,
    required String name,
    required String email,
    String phone = 'N/A',
    String vehicleType = 'Fuel Truck',
    String numberPlate = 'KBZ 123A',
    double pricePerKm = 150,
    Map<String, double> remainingFuel = const {
      'Petrol': 200.0,
      'Diesel': 150.0,
      'Kerosene': 100.0,
      'V-Power': 80.0,
    },
  }) async {
    final docRef = await _db.collection('drivers').add({
      'userId': userId,
      'name': name,
      'email': email,
      'phone': phone,
      'vehicleType': vehicleType,
      'numberPlate': numberPlate,
      'pricePerKm': pricePerKm,
      'isOnline': false,
      'lat': 0,
      'lng': 0,
      'location': GeoPoint(0.0, 0.0),
      'heading': 0.0,
      'speed': 0.0,
      'remainingFuel': remainingFuel,
      'activeOrderId': null,
      'orderStartedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdate': FieldValue.serverTimestamp(),
      'lastOnlineTime': null,
      'lastOfflineTime': null,
      'fuelHistory': [],
      'onlineHistory': [],
      'fuelUsageHistory': [],
    });
    return docRef.id;
  }

  /// Get driver by ID
  static Future<DocumentSnapshot> getDriver(String driverId) async {
    return await _db.collection('drivers').doc(driverId).get();
  }

  /// Get driver by user ID
  static Future<QuerySnapshot> getDriverByUserId(String userId) async {
    return await _db
        .collection('drivers')
        .where('userId', isEqualTo: userId)
        .get();
  }

  /// Update driver online status with location
  static Future<void> updateDriverStatus({
    required String driverId,
    required bool isOnline,
    required double lat,
    required double lng,
    double heading = 0.0,
    double speed = 0.0,
  }) async {
    final now = DateTime.now();
    final timestamp = FieldValue.serverTimestamp();

    // ✅ FIXED: Removed 'timestamp' from historyEntry (no serverTimestamp in arrays)
    final historyEntry = {
      'type': isOnline ? 'online' : 'offline',
      'date': now.toIso8601String(),
      'location': {'lat': lat, 'lng': lng},
    };

    final Map<String, dynamic> updates = {
      'isOnline': isOnline,
      'lat': lat,
      'lng': lng,
      'location': GeoPoint(lat, lng),
      'heading': heading,
      'speed': speed,
      'lastUpdate': timestamp,
      'onlineHistory': FieldValue.arrayUnion([historyEntry]),
    };

    if (isOnline) {
      updates['lastOnlineTime'] = timestamp;
      updates['lastOfflineTime'] = null;
    } else {
      updates['lastOfflineTime'] = timestamp;
      updates['lastOnlineTime'] = null;
    }

    await _db.collection('drivers').doc(driverId).update(updates);
  }

  /// Update driver location only (for when already online)
  static Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0.0,
    double speed = 0.0,
  }) async {
    await _db.collection('drivers').doc(driverId).update({
      'lat': lat,
      'lng': lng,
      'location': GeoPoint(lat, lng),
      'heading': heading,
      'speed': speed,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }

  /// Get all online drivers
  static Future<List<QueryDocumentSnapshot>> getOnlineDrivers() async {
    final snapshot = await _db
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .get();
    return snapshot.docs;
  }

  /// Get online drivers with enough fuel for a specific fuel type and litres
  static Future<List<QueryDocumentSnapshot>> getOnlineDriversWithFuel({
    required String fuelType,
    required double litres,
  }) async {
    final snapshot = await _db
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .get();

    return snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final remainingFuel = data['remainingFuel'] as Map<String, dynamic>? ?? {};
      final available = (remainingFuel[fuelType] as num?)?.toDouble() ?? 0.0;
      return available >= litres;
    }).toList();
  }

  /// Update driver's remaining fuel
  static Future<void> updateDriverFuel({
    required String driverId,
    required Map<String, double> remainingFuel,
  }) async {
    // ✅ FIXED: Removed 'timestamp' from fuelHistoryEntry
    final fuelHistoryEntry = {
      'date': DateTime.now().toIso8601String(),
      'fuelData': remainingFuel,
      'totalFuel': remainingFuel.values.reduce((a, b) => a + b),
    };

    await _db.collection('drivers').doc(driverId).update({
      'remainingFuel': remainingFuel,
      'fuelUpdateTime': FieldValue.serverTimestamp(),
      'fuelHistory': FieldValue.arrayUnion([fuelHistoryEntry]),
    });
  }

  /// Deduct fuel after delivery
  static Future<void> deductDriverFuel({
    required String driverId,
    required String fuelType,
    required double litresUsed,
  }) async {
    final doc = await _db.collection('drivers').doc(driverId).get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    final remainingFuel = Map<String, double>.from(data['remainingFuel'] ?? {});
    final currentFuel = remainingFuel[fuelType] ?? 0.0;
    final newFuel = (currentFuel - litresUsed).clamp(0.0, double.infinity);

    // ✅ FIXED: Removed 'timestamp' from fuelUsageEntry
    final fuelUsageEntry = {
      'date': DateTime.now().toIso8601String(),
      'fuelType': fuelType,
      'amountUsed': litresUsed,
      'previousAmount': currentFuel,
      'newAmount': newFuel,
    };

    remainingFuel[fuelType] = newFuel;

    await _db.collection('drivers').doc(driverId).update({
      'remainingFuel': remainingFuel,
      'fuelUsageHistory': FieldValue.arrayUnion([fuelUsageEntry]),
    });
  }

  /// Get driver online history
  static Future<List<Map<String, dynamic>>> getDriverOnlineHistory({
    required String driverId,
    int limit = 50,
  }) async {
    final doc = await _db.collection('drivers').doc(driverId).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final history = List<Map<String, dynamic>>.from(data['onlineHistory'] ?? []);
      return history.reversed.take(limit).toList();
    }
    return [];
  }

  // ============================================================
  // ORDER METHODS
  // ============================================================

  /// Create a new order
  static Future<String> createOrder({
    required String driverId,
    required String driverName,
    required String driverPhone,
    String? driverPhoto,
    required String driverPlateNumber,
    required String driverVehicleType,
    required String fuelType,
    required double litres,
    required double pricePerLiter,
    required double totalPrice,
    required String userId,
    required String userName,
    String userPhone = 'N/A',
    required double customerLat,
    required double customerLng,
  }) async {
    final docRef = await _db.collection('orders').add({
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'driverPhoto': driverPhoto ?? '',
      'driverPlateNumber': driverPlateNumber,
      'driverVehicleType': driverVehicleType,
      'fuelType': fuelType,
      'litres': litres,
      'pricePerLiter': pricePerLiter,
      'totalPrice': totalPrice,
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'customerLat': customerLat,
      'customerLng': customerLng,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Get order by ID
  static Future<DocumentSnapshot> getOrder(String orderId) async {
    return await _db.collection('orders').doc(orderId).get();
  }

  /// Update order status
  static Future<void> updateOrderStatus({
    required String orderId,
    required String status,
    Map<String, dynamic>? additionalData,
  }) async {
    final Map<String, dynamic> updates = {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (additionalData != null) {
      updates.addAll(additionalData);
    }
    await _db.collection('orders').doc(orderId).update(updates);
  }

  /// Accept order (driver accepts)
  static Future<void> acceptOrder({
    required String orderId,
    required String driverId,
  }) async {
    await _db.collection('orders').doc(orderId).update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('drivers').doc(driverId).update({
      'activeOrderId': orderId,
      'orderStartedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Complete order (driver delivers)
  static Future<void> completeOrder({
    required String orderId,
    required String driverId,
    required String fuelType,
    required double litresUsed,
  }) async {
    await _db.collection('orders').doc(orderId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await deductDriverFuel(
      driverId: driverId,
      fuelType: fuelType,
      litresUsed: litresUsed,
    );

    await _db.collection('drivers').doc(driverId).update({
      'activeOrderId': null,
      'orderStartedAt': null,
    });
  }

  /// Cancel order
  static Future<void> cancelOrder({
    required String orderId,
    required String driverId,
    required String reason,
    bool cancelledByDriver = true,
    bool cancelledByUser = false,
  }) async {
    await _db.collection('orders').doc(orderId).update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledByDriver': cancelledByDriver,
      'cancelledByUser': cancelledByUser,
      'cancellationReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('drivers').doc(driverId).update({
      'activeOrderId': null,
      'orderStartedAt': null,
    });
  }

  /// Get user's active orders
  static Future<QuerySnapshot> getUserActiveOrders(String userId) async {
    return await _db
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'accepted'])
        .get();
  }

  /// Get driver's orders by status
  static Future<QuerySnapshot> getDriverOrdersByStatus({
    required String driverId,
    required String status,
  }) async {
    return await _db
        .collection('orders')
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: status)
        .orderBy('createdAt', descending: true)
        .get();
  }

  /// Get driver's order history
  static Future<QuerySnapshot> getDriverOrderHistory({
    required String driverId,
    int limit = 20,
  }) async {
    return await _db
        .collection('orders')
        .where('driverId', isEqualTo: driverId)
        .where('status', whereIn: ['completed', 'cancelled'])
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
  }

  // ============================================================
  // REQUEST METHODS (Fuel delivery requests)
  // ============================================================

  /// Create a fuel delivery request
  static Future<String> createRequest({
    required String userId,
    required String driverId,
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    required double price,
    String? fuelType,
    double? litres,
  }) async {
    final docRef = await _db.collection('requests').add({
      'userId': userId,
      'driverId': driverId,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropLat': dropLat,
      'dropLng': dropLng,
      'price': price,
      'fuelType': fuelType ?? '',
      'litres': litres ?? 0,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Update request status
  static Future<void> updateRequestStatus({
    required String requestId,
    required String status,
  }) async {
    await _db.collection('requests').doc(requestId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // CANCELLATION METHODS
  // ============================================================

  /// Record an order cancellation
  static Future<void> recordCancellation({
    required String orderId,
    required String userId,
    required String userName,
    required String userPhone,
    required String userEmail,
    required String fuelType,
    required double litres,
    required double totalPrice,
    String? driverId,
    String? driverName,
    required String reason,
  }) async {
    await _db.collection('cancellations').add({
      'orderId': orderId,
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'userEmail': userEmail,
      'fuelType': fuelType,
      'litres': litres,
      'totalPrice': totalPrice,
      'driverId': driverId ?? '',
      'driverName': driverName ?? 'N/A',
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // STREAM LISTENERS (Real-time updates)
  // ============================================================

  /// Listen to driver document changes in real-time
  static Stream<DocumentSnapshot> listenToDriver(String driverId) {
    return _db.collection('drivers').doc(driverId).snapshots();
  }

  /// Listen to order document changes in real-time
  static Stream<DocumentSnapshot> listenToOrder(String orderId) {
    return _db.collection('orders').doc(orderId).snapshots();
  }

  /// Listen to all online drivers in real-time
  static Stream<QuerySnapshot> listenToOnlineDrivers() {
    return _db
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .snapshots();
  }

  /// Listen to driver's pending orders in real-time
  static Stream<QuerySnapshot> listenToDriverOrders(String driverId) {
    return _db
        .collection('orders')
        .where('driverId', isEqualTo: driverId)
        .where('status', whereIn: ['pending', 'accepted'])
        .snapshots();
  }

  /// Listen to user's active orders in real-time
  static Stream<QuerySnapshot> listenToUserOrders(String userId) {
    return _db
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'accepted'])
        .snapshots();
  }

  // ============================================================
  // DISTANCE-BASED DRIVER QUERIES (NO PACKAGE REQUIRED)
  // ============================================================

  /// Find drivers within a radius using manual filtering
  static Future<List<Map<String, dynamic>>> findNearbyDrivers({
    required double lat,
    required double lng,
    required double radiusInKm,
    bool onlyOnline = true,
    bool includeBusy = false,
    String? requiredFuelType,
    double? requiredLitres,
  }) async {
    try {
      QuerySnapshot snapshot;
      if (onlyOnline) {
        snapshot = await _db
            .collection('drivers')
            .where('isOnline', isEqualTo: true)
            .get();
      } else {
        snapshot = await _db.collection('drivers').get();
      }

      List<Map<String, dynamic>> nearbyDrivers = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        final driverLat = (data['lat'] as num?)?.toDouble() ?? 0.0;
        final driverLng = (data['lng'] as num?)?.toDouble() ?? 0.0;
        
        final distance = _calculateDistance(lat, lng, driverLat, driverLng);
        
        if (distance > radiusInKm) continue;
        if (!includeBusy && data['activeOrderId'] != null) continue;
        
        if (requiredFuelType != null && requiredLitres != null) {
          final remainingFuel = data['remainingFuel'] as Map<String, dynamic>? ?? {};
          final available = (remainingFuel[requiredFuelType] as num?)?.toDouble() ?? 0.0;
          if (available < requiredLitres) continue;
        }

        nearbyDrivers.add({
          'id': doc.id,
          ...data,
          'distance': distance,
        });
      }

      nearbyDrivers.sort((a, b) => (a['distance'] ?? 0.0).compareTo(b['distance'] ?? 0.0));
      return nearbyDrivers;
    } catch (e) {
      print('Error finding nearby drivers: $e');
      return [];
    }
  }

  /// Get nearest driver
  static Future<Map<String, dynamic>?> findNearestDriver({
    required double lat,
    required double lng,
    bool onlyOnline = true,
    bool includeBusy = false,
    String? requiredFuelType,
    double? requiredLitres,
  }) async {
    final drivers = await findNearbyDrivers(
      lat: lat,
      lng: lng,
      radiusInKm: 100,
      onlyOnline: onlyOnline,
      includeBusy: includeBusy,
      requiredFuelType: requiredFuelType,
      requiredLitres: requiredLitres,
    );
    return drivers.isNotEmpty ? drivers.first : null;
  }

  /// Get driver distance to a specific point
  static Future<double?> getDriverDistance({
    required String driverId,
    required double targetLat,
    required double targetLng,
  }) async {
    try {
      final doc = await _db.collection('drivers').doc(driverId).get();
      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;
      final driverLat = (data['lat'] as num?)?.toDouble() ?? 0.0;
      final driverLng = (data['lng'] as num?)?.toDouble() ?? 0.0;

      return _calculateDistance(driverLat, driverLng, targetLat, targetLng);
    } catch (e) {
      print('Error getting driver distance: $e');
      return null;
    }
  }

  /// Calculate distance between two coordinates (Haversine formula)
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double R = 6371.0;

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(
      math.sqrt(a),
      math.sqrt(1 - a),
    );

    return R * c;
  }

  static double _toRadians(double degrees) {
    return degrees * 3.141592653589793 / 180.0;
  }
}