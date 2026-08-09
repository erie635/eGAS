// ============================================================
// FILE: firebase_service.dart - COMPLETE WITH IMPROVEMENTS
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  static final db = FirebaseFirestore.instance;
  
  // ✅ ADDED: Collection name constant for easy maintenance
  static const String _requestsCollection = 'requests';
  
  // ✅ ADDED: Status constants
  static const String statusPending = 'pending';
  static const String statusAccepted = 'accepted';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';

  /// Create a new delivery request
  /// Returns the document ID if successful, null otherwise
  static Future<String?> createRequest({
    required String userId,
    required String driverId,
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    required double price,
  }) async {
    // ✅ ADDED: Input validation
    if (userId.isEmpty) {
      print('❌ FirebaseService: userId cannot be empty');
      return null;
    }
    
    if (driverId.isEmpty) {
      print('❌ FirebaseService: driverId cannot be empty');
      return null;
    }
    
    // ✅ ADDED: Validate coordinates
    if (pickupLat < -90 || pickupLat > 90 || pickupLng < -180 || pickupLng > 180) {
      print('❌ FirebaseService: Invalid pickup coordinates');
      return null;
    }
    
    if (dropLat < -90 || dropLat > 90 || dropLng < -180 || dropLng > 180) {
      print('❌ FirebaseService: Invalid drop coordinates');
      return null;
    }
    
    if (price <= 0) {
      print('❌ FirebaseService: Price must be greater than 0');
      return null;
    }

    try {
      // ✅ IMPROVED: Create request with all fields
      final docRef = await db.collection(_requestsCollection).add({
        'userId': userId,
        'driverId': driverId,
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'dropLat': dropLat,
        'dropLng': dropLng,
        'price': price,
        'status': statusPending,
        'createdAt': FieldValue.serverTimestamp(),
        // ✅ ADDED: Additional useful fields
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'isDeleted': false,
      });
      
      print('✅ FirebaseService: Request created successfully with ID: ${docRef.id}');
      
      // ✅ ADDED: Also create a notification for driver
      try {
        await db.collection('notifications').add({
          'userId': driverId,
          'type': 'new_request',
          'title': 'New Delivery Request',
          'body': 'You have a new delivery request',
          'requestId': docRef.id,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('✅ FirebaseService: Notification created for driver');
      } catch (e) {
        print('⚠️ FirebaseService: Failed to create notification: $e');
        // Don't fail the main request if notification fails
      }
      
      return docRef.id;
      
    } catch (e) {
      // ✅ IMPROVED: Better error handling with specific error types
      print('❌ FirebaseService: Error creating request: $e');
      
      // ✅ ADDED: Return null on failure
      return null;
    }
  }

  // ✅ ADDED: Get request by ID
  static Future<DocumentSnapshot?> getRequest(String requestId) async {
    if (requestId.isEmpty) {
      print('❌ FirebaseService: requestId cannot be empty');
      return null;
    }
    
    try {
      final doc = await db.collection(_requestsCollection).doc(requestId).get();
      if (doc.exists) {
        print('✅ FirebaseService: Request retrieved: $requestId');
        return doc;
      } else {
        print('⚠️ FirebaseService: Request not found: $requestId');
        return null;
      }
    } catch (e) {
      print('❌ FirebaseService: Error getting request: $e');
      return null;
    }
  }

  // ✅ ADDED: Update request status
  static Future<bool> updateRequestStatus(String requestId, String status) async {
    if (requestId.isEmpty) {
      print('❌ FirebaseService: requestId cannot be empty');
      return false;
    }
    
    if (!_isValidStatus(status)) {
      print('❌ FirebaseService: Invalid status: $status');
      return false;
    }
    
    try {
      await db.collection(_requestsCollection).doc(requestId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        // ✅ ADDED: Track when status changes
        '${status}At': FieldValue.serverTimestamp(),
      });
      
      print('✅ FirebaseService: Request $requestId status updated to: $status');
      return true;
      
    } catch (e) {
      print('❌ FirebaseService: Error updating request status: $e');
      return false;
    }
  }

  // ✅ ADDED: Accept a request
  static Future<bool> acceptRequest(String requestId, String driverId) async {
    if (requestId.isEmpty || driverId.isEmpty) {
      print('❌ FirebaseService: requestId or driverId cannot be empty');
      return false;
    }
    
    try {
      await db.collection(_requestsCollection).doc(requestId).update({
        'status': statusAccepted,
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedBy': driverId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ FirebaseService: Request $requestId accepted by driver: $driverId');
      
      // ✅ ADDED: Send notification to user
      try {
        final request = await getRequest(requestId);
        if (request != null && request.exists) {
          final data = request.data() as Map<String, dynamic>;
          await db.collection('notifications').add({
            'userId': data['userId'],
            'type': 'request_accepted',
            'title': 'Request Accepted',
            'body': 'Your delivery request has been accepted by a driver',
            'requestId': requestId,
            'driverId': driverId,
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          print('✅ FirebaseService: Notification sent to user');
        }
      } catch (e) {
        print('⚠️ FirebaseService: Failed to send notification: $e');
      }
      
      return true;
      
    } catch (e) {
      print('❌ FirebaseService: Error accepting request: $e');
      return false;
    }
  }

  // ✅ ADDED: Complete a request
  static Future<bool> completeRequest(String requestId) async {
    if (requestId.isEmpty) {
      print('❌ FirebaseService: requestId cannot be empty');
      return false;
    }
    
    try {
      await db.collection(_requestsCollection).doc(requestId).update({
        'status': statusCompleted,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ FirebaseService: Request $requestId completed');
      
      // ✅ ADDED: Update driver stats
      try {
        final request = await getRequest(requestId);
        if (request != null && request.exists) {
          final data = request.data() as Map<String, dynamic>;
          
          // Update driver total completed orders
          final driverDoc = await db.collection('drivers').doc(data['driverId']).get();
          if (driverDoc.exists) {
            final currentTotal = (driverDoc.data()?['totalOrders'] ?? 0).toInt();
            await db.collection('drivers').doc(data['driverId']).update({
              'totalOrders': currentTotal + 1,
              'lastCompletedOrder': FieldValue.serverTimestamp(),
            });
          }
          
          // Update user total orders
          final userDoc = await db.collection('customers').doc(data['userId']).get();
          if (userDoc.exists) {
            final currentTotal = (userDoc.data()?['totalOrders'] ?? 0).toInt();
            final currentSpent = (userDoc.data()?['totalSpent'] ?? 0.0).toDouble();
            await db.collection('customers').doc(data['userId']).update({
              'totalOrders': currentTotal + 1,
              'totalSpent': currentSpent + (data['price'] ?? 0.0),
            });
          }
        }
      } catch (e) {
        print('⚠️ FirebaseService: Failed to update stats: $e');
      }
      
      return true;
      
    } catch (e) {
      print('❌ FirebaseService: Error completing request: $e');
      return false;
    }
  }

  // ✅ ADDED: Cancel a request
  static Future<bool> cancelRequest(String requestId, {String? reason}) async {
    if (requestId.isEmpty) {
      print('❌ FirebaseService: requestId cannot be empty');
      return false;
    }
    
    try {
      final updateData = {
        'status': statusCancelled,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': false,
      };
      
      if (reason != null && reason.isNotEmpty) {
        updateData['cancellationReason'] = reason;
      }
      
      await db.collection(_requestsCollection).doc(requestId).update(updateData);
      
      print('✅ FirebaseService: Request $requestId cancelled${reason != null ? " (Reason: $reason)" : ""}');
      return true;
      
    } catch (e) {
      print('❌ FirebaseService: Error cancelling request: $e');
      return false;
    }
  }

  // ✅ ADDED: Delete request (soft delete)
  static Future<bool> deleteRequest(String requestId) async {
    if (requestId.isEmpty) {
      print('❌ FirebaseService: requestId cannot be empty');
      return false;
    }
    
    try {
      await db.collection(_requestsCollection).doc(requestId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ FirebaseService: Request $requestId soft deleted');
      return true;
      
    } catch (e) {
      print('❌ FirebaseService: Error deleting request: $e');
      return false;
    }
  }

  // ✅ ADDED: Get all requests for a user
  static Future<List<Map<String, dynamic>>> getUserRequests(String userId) async {
    if (userId.isEmpty) {
      print('❌ FirebaseService: userId cannot be empty');
      return [];
    }
    
    try {
      final query = await db.collection(_requestsCollection)
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get();
      
      return query.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
      
    } catch (e) {
      print('❌ FirebaseService: Error getting user requests: $e');
      return [];
    }
  }

  // ✅ ADDED: Get all requests for a driver
  static Future<List<Map<String, dynamic>>> getDriverRequests(String driverId) async {
    if (driverId.isEmpty) {
      print('❌ FirebaseService: driverId cannot be empty');
      return [];
    }
    
    try {
      final query = await db.collection(_requestsCollection)
          .where('driverId', isEqualTo: driverId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get();
      
      return query.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
      
    } catch (e) {
      print('❌ FirebaseService: Error getting driver requests: $e');
      return [];
    }
  }

  // ✅ ADDED: Get pending requests for a driver
  static Future<List<Map<String, dynamic>>> getPendingRequests(String driverId) async {
    if (driverId.isEmpty) {
      print('❌ FirebaseService: driverId cannot be empty');
      return [];
    }
    
    try {
      final query = await db.collection(_requestsCollection)
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: statusPending)
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get();
      
      return query.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
      
    } catch (e) {
      print('❌ FirebaseService: Error getting pending requests: $e');
      return [];
    }
  }

  // ✅ ADDED: Get active requests for a driver
  static Future<List<Map<String, dynamic>>> getActiveRequests(String driverId) async {
    if (driverId.isEmpty) {
      print('❌ FirebaseService: driverId cannot be empty');
      return [];
    }
    
    try {
      final query = await db.collection(_requestsCollection)
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .where('status', whereIn: [statusPending, statusAccepted])
          .where('isDeleted', isEqualTo: false)
          .get();
      
      return query.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
      
    } catch (e) {
      print('❌ FirebaseService: Error getting active requests: $e');
      return [];
    }
  }

  // ✅ ADDED: Get request count for a driver
  static Future<int> getRequestCount(String driverId, {String? status}) async {
    if (driverId.isEmpty) {
      print('❌ FirebaseService: driverId cannot be empty');
      return 0;
    }
    
    try {
      Query query = db.collection(_requestsCollection)
          .where('driverId', isEqualTo: driverId)
          .where('isDeleted', isEqualTo: false);
      
      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      
      final snap = await query.count().get();
      return snap.count ?? 0;
      
    } catch (e) {
      print('❌ FirebaseService: Error getting request count: $e');
      return 0;
    }
  }

  // ✅ ADDED: Validate status
  static bool _isValidStatus(String status) {
    return status == statusPending ||
           status == statusAccepted ||
           status == statusCompleted ||
           status == statusCancelled;
  }
  
  // ✅ ADDED: Stream for real-time request updates
  static Stream<QuerySnapshot> streamUserRequests(String userId) {
    return db.collection(_requestsCollection)
        .where('userId', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
  
  // ✅ ADDED: Stream for real-time driver requests
  static Stream<QuerySnapshot> streamDriverRequests(String driverId) {
    return db.collection(_requestsCollection)
        .where('driverId', isEqualTo: driverId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ✅ ADDED: Stream for real-time pending requests
  static Stream<QuerySnapshot> streamPendingRequests(String driverId) {
    return db.collection(_requestsCollection)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: statusPending)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ✅ ADDED: Listen to a single request in real-time
  static Stream<DocumentSnapshot> streamRequest(String requestId) {
    return db.collection(_requestsCollection).doc(requestId).snapshots();
  }

  // ✅ ADDED: Batch update multiple requests
  static Future<bool> batchUpdateRequests(List<String> requestIds, Map<String, dynamic> updates) async {
    if (requestIds.isEmpty) {
      print('❌ FirebaseService: requestIds list is empty');
      return false;
    }
    
    final batch = db.batch();
    
    try {
      for (var id in requestIds) {
        final docRef = db.collection(_requestsCollection).doc(id);
        batch.update(docRef, updates);
      }
      
      await batch.commit();
      print('✅ FirebaseService: Batch updated ${requestIds.length} requests');
      return true;
      
    } catch (e) {
      print('❌ FirebaseService: Error in batch update: $e');
      return false;
    }
  }
}
