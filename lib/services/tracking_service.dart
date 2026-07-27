import 'package:cloud_firestore/cloud_firestore.dart';

class TrackingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Track a single driver in real-time
  static Stream<DocumentSnapshot> trackDriver(String driverId) {
    return _firestore.collection('drivers').doc(driverId).snapshots();
  }

  // Get all online drivers
  static Stream<QuerySnapshot> getOnlineDrivers() {
    return _firestore
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .snapshots();
  }

  // Update driver location (for driver app)
  static Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
  }) async {
    await _firestore.collection('drivers').doc(driverId).update({
      'lat': lat,
      'lng': lng,
      'lastUpdate': FieldValue.serverTimestamp(),
      'isOnline': true,
    });
  }

  // Set driver offline
  static Future<void> setDriverOffline(String driverId) async {
    await _firestore.collection('drivers').doc(driverId).update({
      'isOnline': false,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }
}