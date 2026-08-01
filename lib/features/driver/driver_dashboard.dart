// ============================================================
// FILE: driver_dashboard.dart - COMPLETE FIXED VERSION
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Import the separated map controller
import 'driver_map_controller.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> with WidgetsBindingObserver {
  // ============================================================
  // MAP CONTROLLER (Separated)
  // ============================================================
  late DriverMapController _mapController;

  // ============================================================
  // BUSINESS LOGIC STATE - ALL ORIGINAL FIELDS
  // ============================================================
  bool _isTracking = false;
  bool _isOnline = false;
  bool _hasActiveOrder = false;
  bool _isOrderAccepted = false;
  String? _driverId;
  String? _activeOrderId;
  Position? _currentPosition;
  Timer? _locationTimer;
  StreamSubscription<DocumentSnapshot>? _driverSubscription;
  StreamSubscription<DocumentSnapshot>? _activeOrderSubscription;
  Map<String, dynamic>? _activeOrderDetails;
  List<Map<String, dynamic>> _completedOrders = [];
  Map<String, double> _remainingFuel = {
    'Petrol': 200.0,
    'Diesel': 150.0,
    'Kerosene': 100.0,
    'V-Power': 80.0,
  };
  
  List<Map<String, dynamic>> _fuelHistory = [];
  List<Map<String, dynamic>> _onlineHistory = [];
  List<Map<String, dynamic>> _salesHistory = [];
  double _totalFuelSoldToday = 0.0;
  double _totalRevenueToday = 0.0;

  String _driverName = '';
  String _driverPhone = '';
  String _driverEmail = '';
  String _vehicleType = 'Fuel Truck';
  String _numberPlate = '';
  bool _isProfileComplete = false;
  bool _isWaitingForOrder = false;
  bool _showCallClientButton = false;
  bool _hasArrived = false;
  bool _isBackgroundTracking = false;
  bool _isDisposed = false;

  // Driver photo URL
  String _driverPhoto = '';

  // Timer controller for arrival check
  Timer? _arrivalCheckTimer;

  // Unique key generation for list items
  String _getUniqueKey(Map<String, dynamic> item, int index, String prefix) {
    if (item.containsKey('id') && item['id'] != null && item['id'].toString().isNotEmpty) {
      return '${prefix}_${item['id']}';
    }
    if (item.containsKey('orderId') && item['orderId'] != null && item['orderId'].toString().isNotEmpty) {
      return '${prefix}_${item['orderId']}';
    }
    if (item.containsKey('timestamp') && item['timestamp'] != null) {
      return '${prefix}_${item['timestamp']}_$index';
    }
    final hash = DateTime.now().millisecondsSinceEpoch % 100000;
    return '${prefix}_${index}_$hash';
  }

  static const List<String> _vehicleTypes = ['Fuel Truck', 'Small Truck', 'Medium Truck', 'Large Truck', 'Van'];

  // Loading states for async operations
  bool _isAcceptingOrder = false;
  bool _isEndingOrder = false;
  bool _isCancellingOrder = false;
  bool _isTogglingTracking = false;

  // Adaptive location update interval
  Duration _locationUpdateInterval = const Duration(seconds: 5);
  double _averageSpeed = 0.0;

  // Retry configuration for Firebase operations
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  // ============================================================
  // ERROR CONTROL FLAGS
  // ============================================================
  bool _isMapControllerDisposed = false;

  // ============================================================
  // INIT
  // ============================================================
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController = DriverMapController()
      ..onMapUpdated = _handleMapUpdate
      ..onTurnAlert = _handleTurnAlert;
    _getDriverId();
    _getCurrentLocation();
    _startArrivalCheck();
    _checkOnlineStatusOnResume();
    _loadSalesHistory();
  }

  // ============================================================
  // SAFE SETSTATE - Simplified
  // ============================================================
  void _safeSetState(VoidCallback fn) {
    if (!mounted || _isDisposed) return;
    setState(fn);
  }

  // ============================================================
  // SAFE SHOW SNACKBAR
  // ============================================================
  void _showSnackBar(String message, Color backgroundColor, {Duration duration = const Duration(seconds: 3)}) {
    if (!mounted || _isDisposed) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: backgroundColor,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      // Silently fail - better than crashing
    }
  }

  // ============================================================
  // SAFE SHOW DIALOG
  // ============================================================
  Future<T?> _showDialog<T>(Widget dialog) async {
    if (!mounted || _isDisposed) return null;
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: false,
        builder: (context) => dialog,
      );
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // SAFE SHOW BOTTOM SHEET
  // ============================================================
  Future<T?> _showBottomSheet<T>(Widget builder) async {
    if (!mounted || _isDisposed) return null;
    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => builder,
      );
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // RETRY LOGIC
  // ============================================================
  Future<T> _withRetry<T>(Future<T> Function() operation, {String operationName = 'Firebase operation'}) async {
    int attempts = 0;
    while (attempts < _maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempts++;
        if (attempts >= _maxRetries) {
          print('❌ $operationName failed after $_maxRetries attempts: $e');
          rethrow;
        }
        print('⚠️ $operationName attempt $attempts failed, retrying...');
        await Future.delayed(_retryDelay);
      }
    }
    throw Exception('$operationName failed');
  }

  // ============================================================
  // ADAPTIVE LOCATION INTERVAL - Simplified
  // ============================================================
  Duration _getAdaptiveLocationInterval() {
    if (_averageSpeed > 60) {
      return const Duration(seconds: 3);
    } else if (_averageSpeed > 30) {
      return const Duration(seconds: 5);
    } else if (_averageSpeed > 5) {
      return const Duration(seconds: 8);
    } else {
      return const Duration(seconds: 10);
    }
  }

  // ============================================================
  // WIDGETS BINDING OBSERVER
  // ============================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        print('🔄 App resumed - resuming updates');
        _checkOnlineStatusOnResume();
        if (_isOnline) {
          _startBackgroundTracking();
        }
        break;
      case AppLifecycleState.paused:
        print('⏸️ App paused - continuing background tracking');
        if (_isOnline) {
          _startBackgroundTracking();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  // ============================================================
  // MAP CALLBACKS
  // ============================================================
  void _handleMapUpdate() {
    if (_isDisposed || _isMapControllerDisposed) return;
    _safeSetState(() {});
  }

  void _handleTurnAlert(String message, String type) {
    if (!mounted || _isDisposed) return;
    Color backgroundColor;
    switch (type) {
      case 'danger':
        backgroundColor = Colors.red.shade700;
        break;
      case 'warning':
        backgroundColor = Colors.orange.shade700;
        break;
      default:
        backgroundColor = Colors.blue.shade700;
    }
    _showSnackBar(message, backgroundColor);
  }

  // ============================================================
  // MAP CREATION
  // ============================================================
  void _onMapCreated(GoogleMapController controller) {
    if (_isDisposed) return;
    _mapController.mapController = controller;
    if (_currentPosition != null) {
      try {
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              zoom: 15,
            ),
          ),
        );
      } catch (e) {
        // Ignore
      }
    }
    if (_isOrderAccepted) {
      _mapController.updateDriverMarker(_vehicleType, _numberPlate);
    }
  }

  // ============================================================
  // HELPER: Safe conversion
  // ============================================================
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed ?? 0.0;
    }
    return 0.0;
  }

  Map<String, double> _convertFuelMap(Map<String, dynamic> fuelData) {
    final Map<String, double> converted = {};
    fuelData.forEach((key, value) {
      converted[key] = _toDouble(value);
    });
    return converted;
  }

  Map<String, double> _parseFuelString(String fuelString) {
    final Map<String, double> fuelMap = {};
    if (fuelString.isEmpty) return fuelMap;
    final parts = fuelString.split(' • ');
    for (var part in parts) {
      final colonIndex = part.indexOf(':');
      if (colonIndex != -1) {
        final fuelName = part.substring(0, colonIndex).trim();
        final amountPart = part.substring(colonIndex + 1).trim();
        final amount = double.tryParse(amountPart.replaceAll('L', '').trim());
        if (amount != null) {
          fuelMap[fuelName] = amount;
        }
      }
    }
    return fuelMap;
  }

  // ============================================================
  // SYNC FUEL FROM DATABASE
  // ============================================================
  Future<void> _syncFuelFromDatabase() async {
    if (_driverId == null || _isDisposed) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        if (data.containsKey('remainingFuel') && data['remainingFuel'] != null) {
          final fuel = _convertFuelMap(data['remainingFuel'] ?? {});
          if (fuel.isNotEmpty) {
            _safeSetState(() {
              _remainingFuel = fuel;
            });
            print('✅ Fuel loaded from remainingFuel: $fuel');
          }
        } else {
          print('⚠️ No remainingFuel field found. Extracting from onlineHistory...');
          if (data.containsKey('onlineHistory')) {
            final history = List<Map<String, dynamic>>.from(data['onlineHistory'] ?? []);
            Map<String, double> extractedFuel = {};
            for (var entry in history.reversed) {
              if (entry['type'] == 'online' && entry.containsKey('fuelAvailable')) {
                final fuelString = entry['fuelAvailable'] as String;
                extractedFuel = _parseFuelString(fuelString);
                if (extractedFuel.isNotEmpty) break;
              }
            }
            if (extractedFuel.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(_driverId)
                  .update({
                'remainingFuel': extractedFuel,
                'fuelUpdatedAt': FieldValue.serverTimestamp(),
              });
              _safeSetState(() {
                _remainingFuel = extractedFuel;
              });
              print('✅ Fuel extracted from history and saved to main document: $extractedFuel');
              _showSnackBar('⛽ Fuel data synced from history!', Colors.green, duration: const Duration(seconds: 2));
            } else {
              print('⚠️ No fuel data found in onlineHistory');
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error syncing fuel: $e');
    }
  }

  // ============================================================
  // LOCATION & TRACKING
  // ============================================================
  Future<void> _getCurrentLocation() async {
    if (_isDisposed) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return;
      }
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _safeSetState(() {
        _mapController.driverLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        _mapController.interpolatedDriverPosition = _mapController.driverLocation;
      });
      if (_isOrderAccepted) {
        _mapController.updateDriverMarker(_vehicleType, _numberPlate);
      }
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  double get currentSpeed => _mapController.currentSpeed ?? 0.0;

  double _calculateHeading(Position? oldPos, Position newPos) {
    if (oldPos == null) return 0.0;
    return Geolocator.bearingBetween(
      oldPos.latitude,
      oldPos.longitude,
      newPos.latitude,
      newPos.longitude,
    );
  }

  void _startBackgroundTracking() async {
    if (_isBackgroundTracking || _isDisposed) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Location permission permanently denied', Colors.red);
        return;
      }
      _isBackgroundTracking = true;
      _locationUpdateInterval = _getAdaptiveLocationInterval();
      _locationTimer = Timer.periodic(_locationUpdateInterval, (timer) async {
        if (!_isOnline || _isDisposed) {
          timer.cancel();
          _isBackgroundTracking = false;
          return;
        }
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          if (_driverId != null && _isOnline) {
            final newHeading = _calculateHeading(_currentPosition, pos);
            final speed = pos.speed * 3.6;
            _averageSpeed = _averageSpeed * 0.9 + speed * 0.1;
            await FirebaseFirestore.instance
                .collection('drivers')
                .doc(_driverId)
                .update({
              'lat': pos.latitude,
              'lng': pos.longitude,
              'heading': newHeading,
              'speed': speed,
              'lastUpdate': FieldValue.serverTimestamp(),
            });
            _safeSetState(() {
              _currentPosition = pos;
              _mapController.currentSpeed = speed;
              _mapController.updateHeading(newHeading);
            });
            _mapController.updateDriverPosition(pos, _vehicleType, _numberPlate);
            if (_isOrderAccepted && _mapController.customerLocation != null) {
              _mapController.recalculateRouteIfNeeded(
                LatLng(pos.latitude, pos.longitude),
                _vehicleType,
                _numberPlate,
              );
            }
          }
        } catch (e) {
          // Silently handle
        }
      });
      print('📍 Background tracking started with interval: ${_locationUpdateInterval.inSeconds}s');
    } catch (e) {
      print('Error starting background tracking: $e');
    }
  }

  void _stopBackgroundTracking() {
    _isBackgroundTracking = false;
    _locationTimer?.cancel();
    _locationTimer = null;
    print('📍 Background tracking stopped');
  }

  // ============================================================
  // ARRIVAL CHECK
  // ============================================================
  void _startArrivalCheck() {
    _arrivalCheckTimer?.cancel();
    _arrivalCheckTimer = null;
    _arrivalCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isDisposed) {
        timer.cancel();
        _arrivalCheckTimer = null;
        return;
      }
      if (_isOrderAccepted && 
          _mapController.customerLocation != null && 
          _currentPosition != null) {
        _checkArrival();
      }
    });
  }

  void _checkArrival() {
    if (_mapController.customerLocation == null || _currentPosition == null) return;
    double distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _mapController.customerLocation!.latitude,
      _mapController.customerLocation!.longitude,
    );
    if (distance < 100 && !_hasArrived) {
      _safeSetState(() {
        _hasArrived = true;
      });
      _showSnackBar(
        '📍 You have arrived at the destination! Tap "End Order" to complete.',
        Colors.green,
        duration: const Duration(seconds: 4),
      );
    }
  }

  // ============================================================
  // DRAW ROUTE
  // ============================================================
  Future<void> _drawRouteToCustomer() async {
    if (_mapController.customerLocation == null || _currentPosition == null) return;
    if (_isDisposed) return;
    final origin = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final destination = _mapController.customerLocation!;
    await _mapController.drawRouteToCustomer(
      origin, 
      destination,
      _vehicleType,
      _numberPlate,
    );
    _safeSetState(() {});
  }

  // ============================================================
  // DRIVER PROFILE
  // ============================================================
  Future<void> _getDriverId() async {
    if (_isDisposed) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final drivers = await FirebaseFirestore.instance
            .collection('drivers')
            .where('userId', isEqualTo: user.uid)
            .get();
        if (drivers.docs.isNotEmpty) {
          final doc = drivers.docs.first;
          final data = doc.data();
          _driverId = doc.id;
          _safeSetState(() {
            _driverName = data['name'] ?? user.displayName ?? 'Driver';
            _driverPhone = data['phone'] ?? user.phoneNumber ?? 'N/A';
            _driverEmail = data['email'] ?? user.email ?? 'N/A';
            _driverPhoto = data['driverPhoto'] ?? data['photoURL'] ?? '';
            String vehicleType = data['vehicleType'] ?? 'Fuel Truck';
            if (!_vehicleTypes.contains(vehicleType)) {
              vehicleType = 'Fuel Truck';
            }
            _vehicleType = vehicleType;
            _numberPlate = data['numberPlate'] ?? '';
            if (data.containsKey('activeOrderId')) {
              _activeOrderId = data['activeOrderId'];
              _hasActiveOrder = _activeOrderId != null && _activeOrderId!.isNotEmpty;
              _isOrderAccepted = data['orderAccepted'] ?? false;
            }
            if (data.containsKey('isOnline')) {
              _isOnline = data['isOnline'] ?? false;
              _isTracking = _isOnline;
              if (_isOnline) {
                _startBackgroundTracking();
                _isWaitingForOrder = true;
              }
            }
            _isProfileComplete = _driverName != 'Driver' && _driverName.isNotEmpty && 
                                 _numberPlate.isNotEmpty;
          });
          await _syncFuelFromDatabase();
          _listenToDriverDocument();
          _loadFuelStatus();
          _loadActiveOrderDetails();
          _loadCompletedOrders();
          _loadFuelHistory();
          _loadOnlineHistory();
          _loadSalesHistory();
        } else {
          _showDriverProfileSetup(user);
        }
      } catch (e) {
        print('Error getting driver: $e');
      }
    }
  }

  // ============================================================
  // LISTEN TO DRIVER DOCUMENT
  // ============================================================
  void _listenToDriverDocument() {
    if (_driverId == null || _isDisposed) return;
    _driverSubscription?.cancel();
    _driverSubscription = null;
    _driverSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(_driverId)
        .snapshots()
        .listen((doc) {
          if (!mounted || _isDisposed || !doc.exists) return;
          final data = doc.data()!;
          final String newName = data['name'] ?? _driverName;
          final String newPhone = data['phone'] ?? _driverPhone;
          final String newVehicleType = data['vehicleType'] ?? _vehicleType;
          final String newNumberPlate = data['numberPlate'] ?? _numberPlate;
          final String newDriverPhoto = data['driverPhoto'] ?? data['photoURL'] ?? _driverPhoto;
          final bool newIsOnline = data['isOnline'] ?? false;
          final String? newActiveOrderId = data['activeOrderId'];
          final bool newOrderAccepted = data['orderAccepted'] ?? false;
          
          if (data.containsKey('remainingFuel') && data['remainingFuel'] != null) {
            final newFuel = _convertFuelMap(data['remainingFuel'] ?? {});
            if (newFuel.isNotEmpty) {
              _safeSetState(() {
                _remainingFuel = newFuel;
              });
            }
          } else if (data.containsKey('onlineHistory')) {
            final history = List<Map<String, dynamic>>.from(data['onlineHistory'] ?? []);
            for (var entry in history.reversed) {
              if (entry['type'] == 'online' && entry.containsKey('fuelAvailable')) {
                final fuelString = entry['fuelAvailable'] as String;
                final extractedFuel = _parseFuelString(fuelString);
                if (extractedFuel.isNotEmpty) {
                  _safeSetState(() {
                    _remainingFuel = extractedFuel;
                  });
                  break;
                }
              }
            }
          }
          
          if (data.containsKey('fuelHistory')) {
            final newHistory = List<Map<String, dynamic>>.from(data['fuelHistory'] ?? []);
            _safeSetState(() {
              _fuelHistory = newHistory;
            });
          }
          
          if (data.containsKey('onlineHistory')) {
            final newOnlineHistory = List<Map<String, dynamic>>.from(data['onlineHistory'] ?? []);
            _safeSetState(() {
              _onlineHistory = newOnlineHistory;
            });
          }
          
          if (data.containsKey('salesHistory')) {
            final newSalesHistory = List<Map<String, dynamic>>.from(data['salesHistory'] ?? []);
            _safeSetState(() {
              _salesHistory = newSalesHistory;
            });
          }
          if (data.containsKey('totalFuelSoldToday')) {
            _safeSetState(() {
              _totalFuelSoldToday = _toDouble(data['totalFuelSoldToday']);
            });
          }
          if (data.containsKey('totalRevenueToday')) {
            _safeSetState(() {
              _totalRevenueToday = _toDouble(data['totalRevenueToday']);
            });
          }
          
          _safeSetState(() {
            _driverName = newName;
            _driverPhone = newPhone;
            _vehicleType = newVehicleType;
            _numberPlate = newNumberPlate;
            _driverPhoto = newDriverPhoto;
            final bool wasOnline = _isOnline;
            _isOnline = newIsOnline;
            _isTracking = newIsOnline;
            if (_isOnline && !_hasActiveOrder && !wasOnline) {
              _isWaitingForOrder = true;
              _startBackgroundTracking();
              _showSnackBar('🟢 You are now online!', Colors.green, duration: const Duration(seconds: 2));
            } else if (!_isOnline && wasOnline) {
              _isWaitingForOrder = false;
              _stopBackgroundTracking();
              _showSnackBar('🔴 You are now offline.', Colors.red, duration: const Duration(seconds: 2));
            }
            if (newActiveOrderId != null && newActiveOrderId != _activeOrderId) {
              _activeOrderId = newActiveOrderId;
              _hasActiveOrder = true;
              _isOrderAccepted = newOrderAccepted;
              _isWaitingForOrder = false;
              _hasArrived = false;
              _loadActiveOrderDetails();
              if (newOrderAccepted) {
                _drawRouteToCustomer();
                _showCallClientButton = true;
              }
            }
            if (newActiveOrderId == null && _hasActiveOrder) {
              _hasActiveOrder = false;
              _activeOrderId = null;
              _activeOrderDetails = null;
              _isOrderAccepted = false;
              _mapController.customerLocation = null;
              _mapController.clearMarkers();
              _mapController.clearRoute();
              _isWaitingForOrder = _isOnline;
              _showCallClientButton = false;
              _hasArrived = false;
              _activeOrderSubscription?.cancel();
              _activeOrderSubscription = null;
              _loadCompletedOrders();
              _loadSalesHistory();
            }
          });
          if (_isOrderAccepted) {
            _mapController.updateDriverMarker(_vehicleType, _numberPlate);
          }
        }, onError: (error) {
          print('❌ Driver document listener error: $error');
        });
  }

  // ============================================================
  // PROFILE SETUP
  // ============================================================
  void _showDriverProfileSetup(User user) {
    if (_isDisposed) return;
    final TextEditingController nameController = TextEditingController(text: user.displayName ?? '');
    final TextEditingController phoneController = TextEditingController(text: user.phoneNumber ?? '');
    final TextEditingController plateController = TextEditingController();
    String selectedVehicle = 'Fuel Truck';

    _showDialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add, color: Colors.green),
            SizedBox(width: 8),
            Text('Complete Your Profile'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please complete your profile to start receiving orders',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedVehicle,
                decoration: const InputDecoration(
                  labelText: 'Vehicle Type *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.directions_car),
                ),
                items: _vehicleTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    selectedVehicle = value;
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: plateController,
                decoration: const InputDecoration(
                  labelText: 'Number Plate *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.credit_card),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              try {
                Navigator.pop(context);
              } catch (e) {
                // Ignore
              }
            },
            child: const Text('Skip for now'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            onPressed: () async {
              if (_isDisposed) return;
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              final plate = plateController.text.trim().toUpperCase();
              if (name.isEmpty || phone.isEmpty || plate.isEmpty) {
                _showSnackBar('Please fill in all required fields', Colors.red);
                return;
              }
              try {
                String baseId = _generateDocumentId(name, user.uid);
                String docId = await _generateUniqueDocumentId(baseId, user.uid);
                _driverId = docId;
                await FirebaseFirestore.instance
                    .collection('drivers')
                    .doc(docId)
                    .set({
                  'createdAt': FieldValue.serverTimestamp(),
                  'email': user.email ?? 'N/A',
                  'isApproved': false,
                  'isOnline': false,
                  'lat': 0,
                  'lng': 0,
                  'name': name,
                  'numberPlate': plate,
                  'phone': phone,
                  'pricePerKm': 0,
                  'userId': user.uid,
                  'vehicleType': selectedVehicle,
                  'heading': 0.0,
                  'speed': 0.0,
                  'remainingFuel': _remainingFuel,
                  'activeOrderId': null,
                  'orderAccepted': false,
                  'fuelHistory': [],
                  'onlineHistory': [],
                  'lastOnlineTime': null,
                  'lastOfflineTime': null,
                  'status': 'offline',
                  'profileComplete': true,
                  'driverPhoto': user.photoURL ?? '',
                  'photoURL': user.photoURL ?? '',
                  'rating': 0.0,
                  'totalOrders': 0,
                  'completedOrders': 0,
                  'driverSince': FieldValue.serverTimestamp(),
                  'isAvailable': false,
                  'salesHistory': [],
                  'totalFuelSoldToday': 0.0,
                  'totalRevenueToday': 0.0,
                  'lastSaleDate': null,
                });
                _safeSetState(() {
                  _driverName = name;
                  _driverPhone = phone;
                  _driverEmail = user.email ?? 'N/A';
                  _vehicleType = selectedVehicle;
                  _numberPlate = plate;
                  _driverPhoto = user.photoURL ?? '';
                  _isProfileComplete = true;
                });
                try {
                  Navigator.pop(context);
                } catch (e) {
                  // Ignore
                }
                _listenToDriverDocument();
                _showSnackBar('✅ Welcome $name! Profile created successfully.', Colors.green);
              } catch (e) {
                _showSnackBar('Error creating profile: $e', Colors.red);
              }
            },
            child: const Text('Complete Profile'),
          ),
        ],
      ),
    );
  }

  String _generateDocumentId(String name, String userId) {
    String cleanName = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleanName.isEmpty) {
      return userId.substring(0, 8);
    }
    return cleanName;
  }

  Future<bool> _documentIdExists(String docId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(docId)
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<String> _generateUniqueDocumentId(String baseId, String userId) async {
    String docId = baseId;
    int counter = 1;
    if (docId.isEmpty) {
      docId = 'driver_${userId.substring(0, 6)}';
    }
    while (await _documentIdExists(docId)) {
      docId = '${baseId}_$counter';
      counter++;
      if (counter > 100) break;
    }
    return docId;
  }

  // ============================================================
  // EDIT PROFILE
  // ============================================================
  void _editProfile() {
    if (_isDisposed) return;
    final TextEditingController phoneController = TextEditingController(text: _driverPhone);
    final TextEditingController emailController = TextEditingController(text: _driverEmail);
    final TextEditingController currentPasswordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    bool showPasswordFields = false;

    _showDialog(
      StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.edit, color: Colors.green),
                SizedBox(width: 8),
                Text('Edit Profile'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You can edit your phone number and password. Vehicle details can only be changed by admin.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                      helperText: 'Enter your phone number starting with 0',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailController,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                      suffixIcon: Icon(Icons.lock, color: Colors.grey),
                      helperText: 'Email cannot be changed',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: Colors.grey.shade300),
                  Row(
                    children: [
                      Icon(Icons.lock, color: Colors.orange.shade700, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Change Password',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: showPasswordFields,
                        onChanged: (value) {
                          setStateDialog(() {
                            showPasswordFields = value;
                            if (!value) {
                              currentPasswordController.clear();
                              newPasswordController.clear();
                              confirmPasswordController.clear();
                            }
                          });
                        },
                        activeColor: Colors.green,
                      ),
                    ],
                  ),
                  if (showPasswordFields) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: currentPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                        hintText: 'Enter your current password',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                        hintText: 'Min 6 characters',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                        hintText: 'Re-enter new password',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ Vehicle Type and Number Plate can only be updated by admin.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  try {
                    Navigator.pop(context);
                  } catch (e) {
                    // Ignore
                  }
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                onPressed: () async {
                  await _saveProfileChanges(
                    context,
                    phoneController,
                    emailController,
                    currentPasswordController,
                    newPasswordController,
                    confirmPasswordController,
                    showPasswordFields,
                  );
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // SAVE PROFILE CHANGES
  // ============================================================
  Future<void> _saveProfileChanges(
    BuildContext context,
    TextEditingController phoneController,
    TextEditingController emailController,
    TextEditingController currentPasswordController,
    TextEditingController newPasswordController,
    TextEditingController confirmPasswordController,
    bool showPasswordFields,
  ) async {
    if (_isDisposed) return;
    final newPhone = phoneController.text.trim();
    if (newPhone.isEmpty) {
      _showSnackBar('Please enter your phone number', Colors.red);
      return;
    }
    if (!RegExp(r'^0[0-9]{9,}$').hasMatch(newPhone)) {
      _showSnackBar('Please enter a valid phone number (e.g., 0712345678)', Colors.orange);
      return;
    }
    if (showPasswordFields) {
      final currentPassword = currentPasswordController.text.trim();
      final newPassword = newPasswordController.text.trim();
      final confirmPassword = confirmPasswordController.text.trim();
      if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
        _showSnackBar('Please fill in all password fields', Colors.red);
        return;
      }
      if (newPassword.length < 6) {
        _showSnackBar('New password must be at least 6 characters', Colors.red);
        return;
      }
      if (newPassword != confirmPassword) {
        _showSnackBar('New passwords do not match', Colors.red);
        return;
      }
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _showSnackBar('Please login again', Colors.red);
          return;
        }
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        );
        await user.reauthenticateWithCredential(credential);
        await user.updatePassword(newPassword);
        _showSnackBar('✅ Password changed successfully!', Colors.green);
      } on FirebaseAuthException catch (e) {
        String message = 'Failed to change password';
        if (e.code == 'wrong-password') {
          message = 'Current password is incorrect';
        } else if (e.code == 'requires-recent-login') {
          message = 'Please login again to change password';
        }
        _showSnackBar(message, Colors.red);
        return;
      } catch (e) {
        _showSnackBar('Error changing password: $e', Colors.red);
        return;
      }
    }
    try {
      await _withRetry(
        () async {
          final updates = {
            'phone': newPhone,
            'lastUpdate': FieldValue.serverTimestamp(),
          };
          if (_driverPhoto.isNotEmpty) {
            updates['driverPhoto'] = _driverPhoto;
          }
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(_driverId)
              .update(updates);
        },
        operationName: 'Profile update',
      );
      _safeSetState(() {
        _driverPhone = newPhone;
      });
      try {
        Navigator.pop(context);
      } catch (e) {
        // Ignore
      }
      _showSnackBar('✅ Profile updated successfully!', Colors.green);
    } catch (e) {
      _showSnackBar('Error updating profile after retries: $e', Colors.red);
    }
  }

  // ============================================================
  // FUEL & HISTORY
  // ============================================================
  void _loadFuelStatus() {
    if (_driverId != null && !_isDisposed) {
      FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .snapshots()
          .listen((doc) {
            if (doc.exists && mounted && !_isDisposed) {
              final data = doc.data()!;
              if (data.containsKey('remainingFuel')) {
                _safeSetState(() {
                  _remainingFuel = _convertFuelMap(data['remainingFuel'] ?? {});
                });
              }
            }
          });
    }
  }

  void _loadFuelHistory() {
    if (_driverId == null || _isDisposed) return;
    FirebaseFirestore.instance
        .collection('drivers')
        .doc(_driverId)
        .snapshots()
        .listen((doc) {
          if (doc.exists && mounted && !_isDisposed) {
            final data = doc.data()!;
            if (data.containsKey('fuelHistory')) {
              _safeSetState(() {
                _fuelHistory = List<Map<String, dynamic>>.from(data['fuelHistory'] ?? []);
              });
            }
          }
        });
  }

  void _loadOnlineHistory() {
    if (_driverId == null || _isDisposed) return;
    FirebaseFirestore.instance
        .collection('drivers')
        .doc(_driverId)
        .snapshots()
        .listen((doc) {
          if (doc.exists && mounted && !_isDisposed) {
            final data = doc.data()!;
            if (data.containsKey('onlineHistory')) {
              _safeSetState(() {
                _onlineHistory = List<Map<String, dynamic>>.from(data['onlineHistory'] ?? []);
              });
            }
          }
        });
  }

  // ============================================================
  // LOAD ACTIVE ORDER
  // ============================================================
  void _loadActiveOrderDetails() {
    if (_activeOrderId != null && _activeOrderId!.isNotEmpty && !_isDisposed) {
      _activeOrderSubscription?.cancel();
      _activeOrderSubscription = null;
      _activeOrderSubscription = FirebaseFirestore.instance
          .collection('orders')
          .doc(_activeOrderId)
          .snapshots()
          .listen((doc) {
            if (doc.exists && mounted && !_isDisposed) {
              final data = doc.data()!;
              _safeSetState(() {
                _activeOrderDetails = data;
                if (data['userLocation'] != null) {
                  final geoPoint = data['userLocation'] as GeoPoint;
                  _mapController.customerLocation = LatLng(geoPoint.latitude, geoPoint.longitude);
                  if (_isOrderAccepted) {
                    _drawRouteToCustomer();
                  }
                }
              });
              final status = data['status'] ?? '';
              if (status == 'completed' || status == 'cancelled') {
                _clearActiveOrder();
                if (status == 'completed') {
                  _loadSalesHistory();
                  _loadCompletedOrders();
                }
              }
            } else if (!doc.exists && mounted && !_isDisposed) {
              _clearActiveOrder();
            }
          }, onError: (error) {
            print('❌ Error loading active order: $error');
            if (mounted && !_isDisposed) {
              _clearActiveOrder();
            }
          });
    }
  }

  // ============================================================
  // LOAD COMPLETED ORDERS
  // ============================================================
  void _loadCompletedOrders() {
    if (_driverId == null || _isDisposed) return;
    try {
      FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: _driverId)
          .where('status', isEqualTo: 'completed')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get()
          .then((completedSnapshot) {
            FirebaseFirestore.instance
                .collection('orders')
                .where('driverId', isEqualTo: _driverId)
                .where('status', isEqualTo: 'cancelled')
                .orderBy('createdAt', descending: true)
                .limit(20)
                .get()
                .then((cancelledSnapshot) {
                  if (mounted && !_isDisposed) {
                    final allOrders = <Map<String, dynamic>>[];
                    for (var doc in completedSnapshot.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      allOrders.add({
                        'id': doc.id,
                        ...data,
                      });
                    }
                    for (var doc in cancelledSnapshot.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      allOrders.add({
                        'id': doc.id,
                        ...data,
                      });
                    }
                    allOrders.sort((a, b) {
                      final aDate = a['createdAt'] as Timestamp?;
                      final bDate = b['createdAt'] as Timestamp?;
                      if (aDate == null && bDate == null) return 0;
                      if (aDate == null) return 1;
                      if (bDate == null) return -1;
                      return bDate.compareTo(aDate);
                    });
                    _safeSetState(() {
                      _completedOrders = allOrders;
                    });
                  }
                })
                .catchError((error) {
                  print('Error loading cancelled orders: $error');
                });
          })
          .catchError((error) {
            print('Error loading completed orders: $error');
            _loadCompletedOrdersFallback();
          });
    } catch (e) {
      print('Error in _loadCompletedOrders: $e');
      _loadCompletedOrdersFallback();
    }
  }

  void _loadCompletedOrdersFallback() {
    if (_driverId == null || _isDisposed) return;
    try {
      final allOrders = <Map<String, dynamic>>[];
      FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: _driverId)
          .where('status', isEqualTo: 'completed')
          .limit(20)
          .get()
          .then((completedSnapshot) {
            for (var doc in completedSnapshot.docs) {
              final data = doc.data() as Map<String, dynamic>;
              allOrders.add({
                'id': doc.id,
                ...data,
              });
            }
            FirebaseFirestore.instance
                .collection('orders')
                .where('driverId', isEqualTo: _driverId)
                .where('status', isEqualTo: 'cancelled')
                .limit(20)
                .get()
                .then((cancelledSnapshot) {
                  for (var doc in cancelledSnapshot.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    allOrders.add({
                      'id': doc.id,
                      ...data,
                    });
                  }
                  if (mounted && !_isDisposed) {
                    allOrders.sort((a, b) {
                      final aDate = a['createdAt'] as Timestamp?;
                      final bDate = b['createdAt'] as Timestamp?;
                      if (aDate == null && bDate == null) return 0;
                      if (aDate == null) return 1;
                      if (bDate == null) return -1;
                      return bDate.compareTo(aDate);
                    });
                    _safeSetState(() {
                      _completedOrders = allOrders;
                    });
                  }
                })
                .catchError((error) {
                  print('Error in fallback cancelled orders: $error');
                });
          })
          .catchError((error) {
            print('Error in fallback completed orders: $error');
          });
    } catch (e) {
      print('Error in _loadCompletedOrdersFallback: $e');
    }
  }

  // ============================================================
  // CLEAR ACTIVE ORDER
  // ============================================================
  Future<void> _clearActiveOrder() async {
    if (_isDisposed) return;
    if (_driverId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(_driverId)
            .update({
          'activeOrderId': null,
          'orderStartedAt': null,
          'status': 'available',
          'orderAccepted': false,
          'isAvailable': true,
        });
      } catch (e) {
        print('Error clearing active order: $e');
      }
    }
    _safeSetState(() {
      _hasActiveOrder = false;
      _activeOrderId = null;
      _activeOrderDetails = null;
      _isOrderAccepted = false;
      _mapController.customerLocation = null;
      _mapController.clearMarkers();
      _mapController.clearRoute();
      _isWaitingForOrder = _isOnline;
      _showCallClientButton = false;
      _hasArrived = false;
    });
    _activeOrderSubscription?.cancel();
    _activeOrderSubscription = null;
    _loadCompletedOrders();
  }

  // ============================================================
  // LOAD SALES HISTORY
  // ============================================================
  Future<void> _loadSalesHistory() async {
    if (_driverId == null || _isDisposed) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _safeSetState(() {
          if (data.containsKey('salesHistory')) {
            _salesHistory = List<Map<String, dynamic>>.from(data['salesHistory'] ?? []);
          }
          if (data.containsKey('totalFuelSoldToday')) {
            _totalFuelSoldToday = _toDouble(data['totalFuelSoldToday']);
          }
          if (data.containsKey('totalRevenueToday')) {
            _totalRevenueToday = _toDouble(data['totalRevenueToday']);
          }
        });
      }
    } catch (e) {
      print('Error loading sales history: $e');
    }
  }

  // ============================================================
  // RECORD SALE
  // ============================================================
  Future<void> _recordSale(String orderId, String fuelType, double litres, double totalPrice) async {
    if (_driverId == null || _isDisposed) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .get();
      final currentData = doc.data()!;
      final Map<String, dynamic> currentFuel = currentData['remainingFuel'] ?? {};
      final double currentAmount = _toDouble(currentFuel[fuelType]);
      final double newAmount = currentAmount - litres;
      final now = DateTime.now().toIso8601String();
      final saleRecord = {
        'orderId': orderId,
        'fuelType': fuelType,
        'litresSold': litres,
        'pricePerLiter': totalPrice / litres,
        'totalAmount': totalPrice,
        'date': now,
        'timestamp': now,
        'driverId': _driverId,
        'driverName': _driverName,
        'vehiclePlate': _numberPlate,
        'remainingFuelBefore': currentAmount,
        'remainingFuelAfter': newAmount,
      };
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final dailySalesRef = FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .collection('dailySales')
          .doc(today);
      final dailyDoc = await dailySalesRef.get();
      double currentTotalLitres = 0;
      double currentTotalRevenue = 0;
      int salesCount = 0;
      if (dailyDoc.exists) {
        final dailyData = dailyDoc.data()!;
        currentTotalLitres = _toDouble(dailyData['totalLitresSold']);
        currentTotalRevenue = _toDouble(dailyData['totalRevenue']);
        salesCount = (dailyData['salesCount'] ?? 0).toInt();
      }
      await dailySalesRef.set({
        'date': today,
        'driverId': _driverId,
        'driverName': _driverName,
        'totalLitresSold': currentTotalLitres + litres,
        'totalRevenue': currentTotalRevenue + totalPrice,
        'salesCount': salesCount + 1,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final double currentTotalFuelSold = _toDouble(currentData['totalFuelSoldToday']);
      final double currentTotalRevenueToday = _toDouble(currentData['totalRevenueToday']);
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .update({
        'remainingFuel.${fuelType}': newAmount,
        'salesHistory': FieldValue.arrayUnion([saleRecord]),
        'totalFuelSoldToday': currentTotalFuelSold + litres,
        'totalRevenueToday': currentTotalRevenueToday + totalPrice,
        'lastSaleDate': FieldValue.serverTimestamp(),
        'lastSaleFuelType': fuelType,
        'lastSaleLitres': litres,
        'lastSaleAmount': totalPrice,
        'lastSaleTime': FieldValue.serverTimestamp(),
      });
      _safeSetState(() {
        _remainingFuel[fuelType] = newAmount;
        _totalFuelSoldToday += litres;
        _totalRevenueToday += totalPrice;
        _salesHistory.insert(0, saleRecord);
      });
      print('✅ Sale recorded: $litres L of $fuelType sold for KES $totalPrice');
    } catch (e) {
      print('❌ Error recording sale: $e');
      throw e;
    }
  }

  // ============================================================
  // FUEL HELPERS
  // ============================================================
  bool _hasFuelToGoOnline() {
    for (var fuel in _remainingFuel.values) {
      if (fuel > 10) {
        return true;
      }
    }
    return false;
  }

  String _getFuelSummary() {
    List<String> available = [];
    for (var entry in _remainingFuel.entries) {
      if (entry.value > 10) {
        available.add('${entry.key}: ${entry.value.toStringAsFixed(0)}L');
      }
    }
    return available.isEmpty ? 'No fuel available' : available.join(' • ');
  }

  String _getFuelIcon(String fuel) {
    switch (fuel) {
      case 'Petrol':
        return '⛽';
      case 'Diesel':
        return '🛢️';
      case 'Kerosene':
        return '🔥';
      case 'V-Power':
        return '⚡';
      default:
        return '⛽';
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} ${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  // ============================================================
  // CALL CLIENT
  // ============================================================
  Future<void> _callClient(String clientName, String phoneNumber) async {
    if (_isDisposed) return;
    if (phoneNumber.isEmpty || phoneNumber == 'N/A') {
      _showSnackBar('Client phone number not available', Colors.red);
      return;
    }
    _showDialog(
      AlertDialog(
        title: Row(
          children: [
            Icon(Icons.phone, color: Colors.green),
            const SizedBox(width: 8),
            Text('Call Client', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Do you want to call $clientName?',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.phone, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Phone: $phoneNumber',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              try {
                Navigator.pop(context);
              } catch (e) {
                // Ignore
              }
            },
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            onPressed: () async {
              try {
                Navigator.pop(context);
              } catch (e) {
                // Ignore
              }
              final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
              try {
                if (await canLaunchUrl(phoneUri)) {
                  await launchUrl(phoneUri);
                } else {
                  _showSnackBar('Could not launch phone dialer', Colors.red);
                }
              } catch (e) {
                _showSnackBar('Error calling client: $e', Colors.red);
              }
            },
            icon: const Icon(Icons.phone, color: Colors.white),
            label: Text(
              'Call $clientName',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TOGGLE TRACKING
  // ============================================================
  void _toggleTracking() async {
    if (_isDisposed) return;
    if (_isTogglingTracking) return;
    if (!_isTracking && _hasActiveOrder) {
      _showSnackBar('⚠️ Complete your active order first before going offline', Colors.orange);
      return;
    }
    if (!_isTracking && !_hasFuelToGoOnline()) {
      _showSnackBar('⛽ No fuel available! Please check your fuel stock before going online.', Colors.red, duration: const Duration(seconds: 4));
      _showFuelStockDialog();
      return;
    }
    _isTogglingTracking = true;
    _safeSetState(() {});
    try {
      if (_isTracking) {
        _locationTimer?.cancel();
        _locationTimer = null;
        _stopBackgroundTracking();
        final offlineEntry = {
          'type': 'offline',
          'timestamp': DateTime.now().toIso8601String(),
          'date': DateTime.now().toIso8601String(),
          'location': {
            'lat': _currentPosition?.latitude ?? 0,
            'lng': _currentPosition?.longitude ?? 0,
          },
          'reason': 'Driver went offline manually',
          'driverName': _driverName,
          'vehiclePlate': _numberPlate,
        };
        if (_driverId != null) {
          await _withRetry(
            () async {
              await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(_driverId)
                  .update({
                'isOnline': false,
                'isAvailable': false,
                'lat': 0,
                'lng': 0,
                'heading': 0,
                'speed': 0,
                'lastOfflineTime': FieldValue.serverTimestamp(),
                'onlineHistory': FieldValue.arrayUnion([offlineEntry]),
                'status': 'offline',
              });
            },
            operationName: 'Toggle offline update',
          );
        }
        _safeSetState(() {
          _isTracking = false;
          _isOnline = false;
          _isWaitingForOrder = false;
          _showCallClientButton = false;
          _isBackgroundTracking = false;
        });
        _showSnackBar('📍 Offline - You are now offline. Tap Start Tracking to go online.', Colors.orange);
      } else {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          await Geolocator.openLocationSettings();
          return;
        }
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.deniedForever) {
          _showSnackBar('Location permission permanently denied', Colors.red);
          return;
        }
        try {
          _currentPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          final onlineEntry = {
            'type': 'online',
            'timestamp': DateTime.now().toIso8601String(),
            'date': DateTime.now().toIso8601String(),
            'location': {
              'lat': _currentPosition!.latitude,
              'lng': _currentPosition!.longitude,
            },
            'fuelAvailable': _getFuelSummary(),
            'driverName': _driverName,
            'vehiclePlate': _numberPlate,
          };
          if (_driverId != null) {
            await _withRetry(
              () async {
                await FirebaseFirestore.instance
                    .collection('drivers')
                    .doc(_driverId)
                    .update({
                  'isOnline': true,
                  'isAvailable': true,
                  'lat': _currentPosition!.latitude,
                  'lng': _currentPosition!.longitude,
                  'heading': 0.0,
                  'speed': 0.0,
                  'lastUpdate': FieldValue.serverTimestamp(),
                  'lastOnlineTime': FieldValue.serverTimestamp(),
                  'onlineHistory': FieldValue.arrayUnion([onlineEntry]),
                  'status': 'available',
                });
              },
              operationName: 'Toggle online update',
            );
          }
          _startBackgroundTracking();
          _safeSetState(() {
            _isTracking = true;
            _isOnline = true;
            _isWaitingForOrder = true;
          });
          _showSnackBar('🟢 Online - You will stay online even if you close the app!', Colors.green, duration: const Duration(seconds: 4));
        } catch (e) {
          _showSnackBar('Error starting tracking: $e', Colors.red);
        }
      }
    } finally {
      _isTogglingTracking = false;
      _safeSetState(() {});
    }
  }

  // ============================================================
  // ACCEPT ORDER
  // ============================================================
  Future<void> _acceptOrder() async {
    if (_isDisposed) return;
    if (_isAcceptingOrder) return;
    if (_activeOrderId == null || _driverId == null) {
      _showSnackBar('No active order to accept', Colors.red);
      return;
    }
    if (_isOrderAccepted) {
      _showSnackBar('Order already accepted', Colors.orange);
      return;
    }
    _isAcceptingOrder = true;
    _safeSetState(() {});
    try {
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(_activeOrderId)
          .get();
      final orderData = orderDoc.data();
      final fuelType = orderData?['fuelType'] ?? 'Petrol';
      final litres = _toDouble(orderData?['litres']);
      final driverFuel = _remainingFuel[fuelType] ?? 0;
      if (driverFuel < litres) {
        _showSnackBar('Not enough fuel! You have ${driverFuel.toStringAsFixed(0)}L of $fuelType.', Colors.red);
        _isAcceptingOrder = false;
        _safeSetState(() {});
        return;
      }
      await _withRetry(
        () async {
          await FirebaseFirestore.instance
              .collection('orders')
              .doc(_activeOrderId)
              .update({
            'status': 'accepted',
            'acceptedAt': FieldValue.serverTimestamp(),
            'driverId': _driverId,
            'driverName': _driverName,
            'driverPhone': _driverPhone,
            'driverPlateNumber': _numberPlate,
            'driverVehicleType': _vehicleType,
          });
        },
        operationName: 'Accept order update',
      );
      await _withRetry(
        () async {
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(_driverId)
              .update({
            'orderAccepted': true,
            'status': 'busy',
            'isAvailable': false,
            'currentClientName': orderData?['userName'] ?? 'Unknown',
            'currentClientPhone': orderData?['userPhone'] ?? 'N/A',
            'currentClientLocation': orderData?['userLocation'] ?? null,
            'currentClientPhoto': orderData?['customerPhoto'] ?? '',
          });
        },
        operationName: 'Accept order driver update',
      );
      _safeSetState(() {
        _isOrderAccepted = true;
        _isWaitingForOrder = false;
        _activeOrderDetails = orderData;
        _showCallClientButton = true;
        _hasArrived = false;
        if (orderData?['userLocation'] != null) {
          final geoPoint = orderData?['userLocation'] as GeoPoint;
          _mapController.customerLocation = LatLng(geoPoint.latitude, geoPoint.longitude);
          _drawRouteToCustomer();
        }
      });
      _showSnackBar('✅ Order accepted! Navigating to customer.', Colors.green);
    } catch (e) {
      _showSnackBar('Error accepting order after retries: $e', Colors.red);
    } finally {
      _isAcceptingOrder = false;
      _safeSetState(() {});
    }
  }

  // ============================================================
  // END ORDER
  // ============================================================
  Future<void> _endOrder() async {
    if (_isDisposed) return;
    if (_isEndingOrder) return;
    if (_activeOrderId == null || _activeOrderDetails == null) {
      _showSnackBar('No active order to complete', Colors.red);
      return;
    }
    final fuelType = _activeOrderDetails?['fuelType'] ?? 'Petrol';
    final litres = _toDouble(_activeOrderDetails?['litres']);
    final totalPrice = _toDouble(_activeOrderDetails?['totalPrice']);
    final confirmed = await _showDialog<bool>(
      AlertDialog(
        title: const Text('Confirm Delivery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 12),
            Text('Confirm delivery of ${litres.toStringAsFixed(0)} L of $fuelType?'),
            const SizedBox(height: 8),
            Text(
              'Total: KES ${totalPrice.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This will deduct fuel from your remaining stock.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              try {
                Navigator.of(context).pop(false);
              } catch (e) {
                // Ignore
              }
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              try {
                Navigator.of(context).pop(true);
              } catch (e) {
                // Ignore
              }
            },
            child: const Text('Confirm Delivery'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _isEndingOrder = true;
    _safeSetState(() {});
    _showSnackBar('⏳ Processing delivery...', Colors.blue, duration: const Duration(seconds: 2));
    try {
      final currentFuel = _remainingFuel[fuelType] ?? 0;
      final newFuel = currentFuel - litres;
      if (newFuel < 0) {
        _showSnackBar('Error: Not enough fuel in stock to complete delivery.', Colors.red);
        _isEndingOrder = false;
        _safeSetState(() {});
        return;
      }
      final String orderId = _activeOrderId!;
      await _recordSale(
        orderId,
        fuelType,
        litres,
        totalPrice,
      );
      await _withRetry(
        () async {
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(_driverId)
              .update({
            'activeOrderId': null,
            'orderStartedAt': null,
            'status': 'available',
            'orderAccepted': false,
            'isAvailable': true,
            'completedOrders': FieldValue.increment(1),
            'lastCompletedOrderAt': FieldValue.serverTimestamp(),
          });
        },
        operationName: 'End order driver update',
      );
      try {
        final orderDoc = await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .get();
        if (orderDoc.exists) {
          await _withRetry(
            () async {
              await FirebaseFirestore.instance
                  .collection('orders')
                  .doc(orderId)
                  .update({
                'status': 'completed',
                'completedAt': FieldValue.serverTimestamp(),
                'fuelDeducted': litres,
                'completedByDriver': true,
                'completionTime': FieldValue.serverTimestamp(),
              });
            },
            operationName: 'End order status update',
          );
          print('✅ Order $orderId updated to completed');
        } else {
          print('⚠️ Order document $orderId does not exist, skipping update');
        }
      } catch (e) {
        print('Error updating order: $e');
      }
      _safeSetState(() {
        _hasActiveOrder = false;
        _activeOrderId = null;
        _activeOrderDetails = null;
        _isOrderAccepted = false;
        _mapController.customerLocation = null;
        _mapController.clearMarkers();
        _mapController.clearRoute();
        _hasArrived = false;
        _showCallClientButton = false;
        _isWaitingForOrder = _isOnline;
      });
      _activeOrderSubscription?.cancel();
      _activeOrderSubscription = null;
      _loadCompletedOrders();
      _loadSalesHistory();
      _showSnackBar('✅ Delivery confirmed! Remaining $fuelType: ${newFuel.toStringAsFixed(0)}L', Colors.green);
      _showSnackBar('📍 You are now available for new orders. Tap Start Tracking to go online.', Colors.blue, duration: const Duration(seconds: 3));
    } catch (e) {
      print('Error completing delivery: $e');
      _showSnackBar('Error completing delivery: ${e.toString().substring(0, 100)}', Colors.red, duration: const Duration(seconds: 4));
    } finally {
      _isEndingOrder = false;
      _safeSetState(() {});
    }
  }

  // ============================================================
  // CANCEL ORDER
  // ============================================================
  Future<void> _cancelOrder() async {
    if (_isDisposed) return;
    if (_activeOrderId == null) return;
    if (_isCancellingOrder) return;
    if (_isOrderAccepted) {
      await _clearActiveOrder();
      _showSnackBar('Order cancelled. You are available for new orders.', Colors.orange);
      return;
    }
    final TextEditingController reasonController = TextEditingController();
    String selectedReason = 'Cannot fulfill order';
    final List<String> reasons = [
      'Cannot fulfill order',
      'Not enough fuel',
      'Vehicle issue',
      'Customer unreachable',
      'Wrong location',
      'Other',
    ];
    _showDialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red),
            SizedBox(width: 8),
            Text('Cancel Order'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order Details:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_activeOrderDetails?['fuelType'] ?? 'N/A'} - ${_toDouble(_activeOrderDetails?['litres']).toStringAsFixed(0)}L',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Customer: ${_activeOrderDetails?['userName'] ?? 'N/A'}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  Text(
                    'Phone: ${_activeOrderDetails?['userPhone'] ?? 'N/A'}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Reason for cancellation:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedReason,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: reasons.map((reason) {
                return DropdownMenuItem(
                  value: reason,
                  child: Text(reason),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) selectedReason = value;
              },
            ),
            if (selectedReason == 'Other') ...[
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Please specify',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                maxLines: 2,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              try {
                Navigator.pop(context);
              } catch (e) {
                // Ignore
              }
            },
            child: const Text('Keep Order'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              if (_isCancellingOrder) return;
              final reason = selectedReason == 'Other' 
                  ? reasonController.text.trim() 
                  : selectedReason;
              if (reason.isEmpty) {
                _showSnackBar('Please provide a reason for cancellation', Colors.orange);
                return;
              }
              _isCancellingOrder = true;
              try {
                Navigator.pop(context);
              } catch (e) {
                // Ignore
              }
              try {
                await _withRetry(
                  () async {
                    await FirebaseFirestore.instance
                        .collection('orders')
                        .doc(_activeOrderId!)
                        .update({
                      'status': 'cancelled',
                      'cancelledByDriver': true,
                      'driverCancellationReason': reason,
                      'cancelledAt': FieldValue.serverTimestamp(),
                    });
                  },
                  operationName: 'Cancel order update',
                );
                await _withRetry(
                  () async {
                    await FirebaseFirestore.instance
                        .collection('drivers')
                        .doc(_driverId)
                        .update({
                      'activeOrderId': null,
                      'orderStartedAt': null,
                      'status': 'available',
                      'orderAccepted': false,
                      'isAvailable': true,
                    });
                  },
                  operationName: 'Cancel order driver update',
                );
                _safeSetState(() {
                  _hasActiveOrder = false;
                  _activeOrderId = null;
                  _activeOrderDetails = null;
                  _isOrderAccepted = false;
                  _mapController.customerLocation = null;
                  _mapController.clearMarkers();
                  _mapController.clearRoute();
                  _isWaitingForOrder = _isOnline;
                  _showCallClientButton = false;
                  _hasArrived = false;
                });
                _loadCompletedOrders();
                _showSnackBar('Order cancelled: $reason', Colors.orange);
              } catch (e) {
                _showSnackBar('Error cancelling order after retries: $e', Colors.red);
              } finally {
                _isCancellingOrder = false;
              }
            },
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SHOW DIALOGS
  // ============================================================
  void _showSalesSummary() {
    if (_isDisposed) return;
    _showBottomSheet(
      Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.attach_money, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  '📊 Sales Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'Today',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        '${_totalFuelSoldToday.toStringAsFixed(0)}L',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const Text(
                        'Total Sold',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.grey.shade300,
                  ),
                  Column(
                    children: [
                      Text(
                        'KES ${_totalRevenueToday.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const Text(
                        'Total Revenue',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Recent Sales',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _salesHistory.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'No sales yet today',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      key: const PageStorageKey<String>('sales_history_list'),
                      itemCount: _salesHistory.length > 20 ? 20 : _salesHistory.length,
                      itemBuilder: (context, index) {
                        final sale = _salesHistory[index];
                        final date = sale['date'] ?? 'N/A';
                        final fuelType = sale['fuelType'] ?? 'N/A';
                        final litresSold = _toDouble(sale['litresSold']);
                        final amount = _toDouble(sale['totalAmount']);
                        final uniqueKey = _getUniqueKey(sale, index, 'sale');
                        return Card(
                          key: ValueKey(uniqueKey),
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.shade100,
                              child: Text(
                                fuelType[0],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                            title: Text(
                              '$fuelType - ${litresSold.toStringAsFixed(0)}L',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'KES ${amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                              ),
                            ),
                            trailing: Text(
                              _formatDate(date),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFuelStockDialog() {
    if (_isDisposed) return;
    _showDialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.local_gas_station, color: Colors.green),
            SizedBox(width: 8),
            Text('Current Fuel Stock'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '📊 Fuel levels are updated automatically when you complete orders.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ..._remainingFuel.keys.map((fuel) {
                final amount = _remainingFuel[fuel] ?? 0;
                final isLow = amount < 20;
                return Padding(
                  key: ValueKey('fuel_$fuel'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isLow ? Colors.red.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLow ? Colors.red.shade300 : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _getFuelIcon(fuel),
                          style: const TextStyle(fontSize: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fuel,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isLow ? Colors.red.shade700 : Colors.black87,
                                ),
                              ),
                              if (isLow)
                                Text(
                                  '⚠️ Low stock',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isLow ? Colors.red.shade100 : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${amount.toStringAsFixed(0)} L',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: isLow ? Colors.red.shade700 : Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📋 Last Fuel Update:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fuelHistory.isNotEmpty 
                          ? '${_formatDate(_fuelHistory.first['date'] ?? '')} - Total: ${_toDouble(_fuelHistory.first['totalFuel']).toStringAsFixed(0)}L'
                          : 'No update history',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_gas_station, color: Colors.orange.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Fuel is updated automatically when orders are completed.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              try {
                Navigator.pop(context);
              } catch (e) {
                // Ignore
              }
            },
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            onPressed: () {
              try {
                Navigator.pop(context);
              } catch (e) {
                // Ignore
              }
            },
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showOnlineHistory() {
    if (_isDisposed) return;
    _showBottomSheet(
      Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.history, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'Online/Offline History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_onlineHistory.length} records',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _onlineHistory.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'No online history yet',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      key: const PageStorageKey<String>('online_history_list'),
                      itemCount: _onlineHistory.length,
                      itemBuilder: (context, index) {
                        final entry = _onlineHistory[index];
                        final isOnline = entry['type'] == 'online';
                        final date = entry['date'] ?? 'N/A';
                        final location = entry['location'] ?? {};
                        final lat = location['lat']?.toStringAsFixed(6) ?? 'N/A';
                        final lng = location['lng']?.toStringAsFixed(6) ?? 'N/A';
                        final driverName = entry['driverName'] ?? 'Driver';
                        final vehiclePlate = entry['vehiclePlate'] ?? 'N/A';
                        final uniqueKey = _getUniqueKey(entry, index, 'online');
                        return Card(
                          key: ValueKey(uniqueKey),
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isOnline ? Colors.green.shade100 : Colors.red.shade100,
                              child: Icon(
                                isOnline ? Icons.wifi : Icons.wifi_off,
                                color: isOnline ? Colors.green : Colors.red,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              isOnline ? '🟢 $driverName Went Online' : '🔴 $driverName Went Offline',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: isOnline ? Colors.green : Colors.red,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '📍 $lat, $lng',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                if (entry.containsKey('fuelAvailable') && isOnline)
                                  Text(
                                    '⛽ ${entry['fuelAvailable']}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                Text(
                                  '🚗 $vehiclePlate',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Text(
                              _formatDate(date),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CHECK ONLINE STATUS ON RESUME
  // ============================================================
  Future<void> _checkOnlineStatusOnResume() async {
    if (_driverId == null || _isDisposed) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final bool isOnlineFromDb = data['isOnline'] ?? false;
        if (isOnlineFromDb && !_isOnline) {
          _safeSetState(() {
            _isOnline = true;
            _isTracking = true;
            _isWaitingForOrder = true;
          });
          _startBackgroundTracking();
          _showSnackBar('🟢 You are still online!', Colors.green, duration: const Duration(seconds: 2));
        }
      }
    } catch (e) {
      print('Error checking online status: $e');
    }
  }

  // ============================================================
  // BUILD - FIXED
  // ============================================================
  @override
  Widget build(BuildContext context) {
    if (_isDisposed) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚚 Driver Dashboard'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.attach_money, color: Colors.white),
            onPressed: _showSalesSummary,
            tooltip: 'Sales Summary',
          ),
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: _editProfile,
            tooltip: 'Edit Profile',
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: _showOnlineHistory,
            tooltip: 'Online History',
          ),
          IconButton(
            icon: Icon(_isOnline ? Icons.wifi : Icons.wifi_off, color: Colors.white),
            onPressed: _isTogglingTracking ? null : _toggleTracking,
            tooltip: 'Toggle Tracking',
          ),
          IconButton(
            icon: const Icon(Icons.local_gas_station, color: Colors.white),
            onPressed: _showFuelStockDialog,
            tooltip: 'View Fuel Stock',
          ),
        ],
      ),
      body: _isOrderAccepted ? _buildMapView() : _buildDashboardView(),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasActiveOrder && !_isOrderAccepted
                        ? Colors.grey 
                        : (!_hasFuelToGoOnline() && !_isTracking)
                            ? Colors.red
                            : (_isTracking ? Colors.red : Colors.green),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: (_hasActiveOrder || (!_hasFuelToGoOnline() && !_isTracking) || _isTogglingTracking) 
                      ? null 
                      : _toggleTracking,
                  icon: _isTogglingTracking
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _hasActiveOrder && !_isOrderAccepted
                              ? Icons.lock 
                              : (!_hasFuelToGoOnline() && !_isTracking)
                                  ? Icons.warning
                                  : (_isTracking ? Icons.stop : Icons.play_arrow),
                          color: Colors.white,
                          size: 18,
                        ),
                  label: _isTogglingTracking
                      ? const Text(
                          'Please wait...',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        )
                      : Text(
                          _hasActiveOrder && !_isOrderAccepted
                              ? '🔄 Accept to Navigate' 
                              : _hasActiveOrder 
                                  ? '🔴 Busy with order' 
                                  : (!_hasFuelToGoOnline() && !_isTracking)
                                      ? '⛽ No Fuel!'
                                      : (_isTracking ? 'Stop Tracking' : 'Start Tracking'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.green.shade100,
                  padding: const EdgeInsets.all(8),
                ),
                icon: const Icon(Icons.local_gas_station, color: Colors.green, size: 20),
                onPressed: _showFuelStockDialog,
                tooltip: 'View Fuel Stock',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD MAP VIEW
  // ============================================================
  Widget _buildMapView() {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentPosition != null 
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) 
                : const LatLng(-1.2921, 36.8219),
            zoom: 15,
          ),
          markers: _mapController.mapMarkers,
          polylines: _mapController.polylines,
          onMapCreated: _onMapCreated,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          compassEnabled: true,
          mapType: MapType.normal,
        ),
        Positioned(
          top: 80,
          right: 12,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_activeOrderDetails?['fuelType'] ?? 'N/A'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${_toDouble(_activeOrderDetails?['litres']).toStringAsFixed(0)}L',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.green.shade700,
                  ),
                ),
                if (_mapController.distanceToCustomer != null)
                  Text(
                    '${_mapController.distanceToCustomer!.toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                    ),
                  ),
                if (_mapController.estimatedMinutes != null)
                  Text(
                    'ETA: ${_mapController.estimatedMinutes} min',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                if (_mapController.isNavigating && 
                    _mapController.currentStepIndex < _mapController.routeSteps.length)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _mapController.getManeuverIcon(_mapController.nextManeuver),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _mapController.nextInstruction,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_mapController.currentSpeed > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_mapController.currentSpeed.toStringAsFixed(0)} km/h',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_showCallClientButton && _activeOrderDetails != null)
          Positioned(
            top: 80,
            left: 12,
            child: GestureDetector(
              onTap: () {
                final clientName = _activeOrderDetails?['userName'] ?? 'Client';
                final clientPhone = _activeOrderDetails?['userPhone'] ?? 'N/A';
                _callClient(clientName, clientPhone);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.6),
                      blurRadius: 15,
                      spreadRadius: 3,
                    ),
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.phone,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Call Client',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_hasArrived && _hasActiveOrder && _isOrderAccepted)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: GestureDetector(
              onTap: _isEndingOrder ? null : _endOrder,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _isEndingOrder ? Colors.grey : Colors.green,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (_isEndingOrder ? Colors.grey : Colors.green).withOpacity(0.6),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                    BoxShadow(
                      color: (_isEndingOrder ? Colors.grey : Colors.green).withOpacity(0.3),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: _isEndingOrder
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.flag,
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(width: 10),
                            Text(
                              '🏁 End Order',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // BUILD DASHBOARD VIEW - FIXED
  // ============================================================
  Widget _buildDashboardView() {
    return Column(
      children: [
        // Profile Header - Always visible
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            border: Border(bottom: BorderSide(color: Colors.green.shade200)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.green,
                    backgroundImage: _driverPhoto.isNotEmpty
                        ? NetworkImage(_driverPhoto)
                        : null,
                    child: _driverPhoto.isEmpty
                        ? Text(
                            _driverName.isNotEmpty ? _driverName[0].toUpperCase() : 'D',
                            style: const TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _driverName.isNotEmpty ? _driverName : 'Driver',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.phone, size: 11, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text(
                              _driverPhone,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.directions_car, size: 11, color: Colors.blue.shade700),
                            const SizedBox(width: 4),
                            Text(
                              '$_vehicleType • $_numberPlate',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isOnline ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _isOnline ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Fuel Stock - Compact
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 3),
                      child: Text(
                        '⛽ Fuel Stock',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    ..._remainingFuel.keys.map((fuel) {
                      final amount = _remainingFuel[fuel] ?? 0;
                      final isLow = amount < 20;
                      return Padding(
                        key: ValueKey('fuel_display_$fuel'),
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isLow 
                                ? Colors.red.shade600.withOpacity(0.85) 
                                : Colors.red.shade600.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isLow 
                                  ? Colors.red.shade600 
                                  : Colors.grey.shade300,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                _getFuelIcon(fuel),
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  fuel,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isLow 
                                      ? Colors.red.shade900.withOpacity(0.6) 
                                      : Colors.green.shade900.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${amount.toStringAsFixed(0)}L',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isLow ? Colors.red.shade200 : Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              if (_isOnline && _currentPosition != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    children: [
                      Text(
                        '📍 ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      if (_hasActiveOrder)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '🔴 Busy with order',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (!_hasFuelToGoOnline() && !_isOnline)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red.shade700, size: 12),
                        const SizedBox(width: 6),
                        Text(
                          '⛽ No fuel available! Check your fuel stock to go online.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ============================================================
        // ACTIVE ORDER CARD - COMPACT
        // ============================================================
        if (_hasActiveOrder && _activeOrderDetails != null)
          Container(
            key: const ValueKey('active_order_card'),
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade50, Colors.red.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.shade300, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.shade200,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '🔄 NEW ORDER',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'PENDING',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: Center(
                        child: Text(
                          _activeOrderDetails?['fuelType']?[0] ?? '⛽',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_activeOrderDetails?['fuelType'] ?? 'N/A'} - ${_toDouble(_activeOrderDetails?['litres']).toStringAsFixed(0)}L',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Total: KES ${_toDouble(_activeOrderDetails?['totalPrice']).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                              color: Colors.orange,
                            ),
                          ),
                          Text(
                            'Customer: ${_activeOrderDetails?['userName'] ?? 'Unknown'}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '📞 ${_activeOrderDetails?['userPhone'] ?? 'N/A'}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isAcceptingOrder ? Colors.grey : Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _isAcceptingOrder ? null : _acceptOrder,
                        icon: _isAcceptingOrder
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle, color: Colors.white, size: 16),
                        label: _isAcceptingOrder
                            ? const Text(
                                'Accepting...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              )
                            : const Text(
                                'Accept Order',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _isCancellingOrder ? null : _cancelOrder,
                        child: _isCancellingOrder
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red,
                                ),
                              )
                            : const Text(
                                'Cancel Order', 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                )
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        // ============================================================
        // END OF ACTIVE ORDER CARD
        // ============================================================

        // ============================================================
        // WAITING / OFFLINE STATES - FIXED WITH FLEXIBLE
        // ============================================================
        if (!_hasActiveOrder && _isOnline && !_isOrderAccepted)
          Flexible(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.timer,
                    size: 58,
                    color: Colors.orange.shade300,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '⏳ Waiting for Assignment',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The system will assign an order when available',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Stay online to receive orders',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (!_isOnline)
          Flexible(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wifi_off,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _hasFuelToGoOnline()
                        ? '📴 Offline\nGo online to receive orders'
                        : '⛽ No fuel available!\nCheck fuel stock',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  if (!_hasFuelToGoOnline())
                    ElevatedButton(
                      onPressed: _showFuelStockDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: const Text('View Fuel Stock', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  if (_hasFuelToGoOnline() && !_isOnline && !_hasActiveOrder)
                    ElevatedButton(
                      onPressed: _isTogglingTracking ? null : _toggleTracking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isTogglingTracking ? Colors.grey : Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      ),
                      child: _isTogglingTracking
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Go Online', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // DISPOSE - Enhanced with error control
  // ============================================================
  @override
  void dispose() {
    if (_isDisposed) {
      super.dispose();
      return;
    }
    _isDisposed = true;
    _isMapControllerDisposed = true;
    
    // Remove observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Cancel all timers
    _locationTimer?.cancel();
    _locationTimer = null;
    _arrivalCheckTimer?.cancel();
    _arrivalCheckTimer = null;
    
    // Cancel all stream subscriptions
    _driverSubscription?.cancel();
    _driverSubscription = null;
    _activeOrderSubscription?.cancel();
    _activeOrderSubscription = null;
    
    // Stop background tracking
    _stopBackgroundTracking();
    
    // Dispose map controller (which also cleans up its resources)
    try {
      _mapController.dispose();
    } catch (e) {
      print('⚠️ Error disposing map controller: $e');
    }
    
    // Clear any pending async operations
    _isAcceptingOrder = false;
    _isEndingOrder = false;
    _isCancellingOrder = false;
    _isTogglingTracking = false;
    _isBackgroundTracking = false;
    
    super.dispose();
  }
}