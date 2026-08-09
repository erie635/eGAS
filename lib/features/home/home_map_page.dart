// ============================================================
// FILE: home_map_page.dart - WITH LARGER FONTS - CLEAN VERSION
// INCLUDES V-POWER + 3 FUEL OPTIONS IN BOTTOM SHEET
// CALL DRIVER BUTTON - CENTERED BOTTOM (ADJUSTED UP)
// ✅ FIXED: Call Driver button only appears after driver accepts order
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_map_controller.dart';

class HomeMapPage extends StatefulWidget {
  const HomeMapPage({super.key});

  @override
  State<HomeMapPage> createState() => _HomeMapPageState();
}

class _HomeMapPageState extends State<HomeMapPage> with WidgetsBindingObserver {
  late HomeMapController _controller;
  double _bottomSheetDragOffset = 0.0;
  bool _isDragging = false;
  bool _isDisposed = false;
  Timer? _debounceTimer;
  Timer? _swipeThrottleTimer;
  double _throttledDragOffset = 0.0;
  
  // ✅ NEW: Track driver acceptance state
  bool _isDriverAccepted = false;
  String? _assignedDriverId;
  String? _assignedDriverPhone;
  String? _assignedDriverName;
  StreamSubscription<DocumentSnapshot>? _orderSubscription;

  static const double _sheetHeight = 280.0;
  static const double _minDragLimit = 0.0;
  static const double _maxDragLimit = 180.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = HomeMapController();
    _controller.setContext(context);
    _controller.addListener(_onControllerUpdate);
    
    // ✅ NEW: Start listening for driver acceptance if there's an active order
    _startListeningForDriverAcceptance();
  }

  @override
  void dispose() {
    if (_isDisposed) {
      super.dispose();
      return;
    }
    _isDisposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _swipeThrottleTimer?.cancel();
    _swipeThrottleTimer = null;
    _orderSubscription?.cancel();
    _orderSubscription = null;
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerUpdate);
    
    try {
      _controller.dispose();
    } catch (e) {
      print('⚠️ Error disposing HomeMapController: $e');
    }
    
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _isDisposed) return;
    setState(fn);
  }

  void _onControllerUpdate() {
    if (_isDisposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _safeSetState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    
    switch (state) {
      case AppLifecycleState.resumed:
        _safeSetState(() {});
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  // ✅ NEW: Listen for driver acceptance in real-time
  void _startListeningForDriverAcceptance() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Get the user's active order
    FirebaseFirestore.instance
        .collection('orders')
        .where('customerId', isEqualTo: user.uid)
        .where('status', whereIn: ['pending', 'accepted', 'confirmed'])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get()
        .then((querySnapshot) {
          if (querySnapshot.docs.isNotEmpty) {
            final doc = querySnapshot.docs.first;
            final orderId = doc.id;
            
            // Listen to this specific order
            _orderSubscription?.cancel();
            _orderSubscription = FirebaseFirestore.instance
                .collection('orders')
                .doc(orderId)
                .snapshots()
                .listen((snapshot) {
                  if (!snapshot.exists) return;
                  
                  final data = snapshot.data()!;
                  final String status = data['status'] ?? 'pending';
                  final String? driverId = data['driverId'];
                  final String? driverPhone = data['driverPhone'];
                  final String? driverName = data['driverName'];
                  
                  // ✅ ONLY when status is 'accepted' and driverId exists
                  if (status == 'accepted' && driverId != null && driverId.isNotEmpty) {
                    _safeSetState(() {
                      _isDriverAccepted = true;
                      _assignedDriverId = driverId;
                      _assignedDriverPhone = driverPhone;
                      _assignedDriverName = driverName;
                      _controller.driverPhoneNumber = driverPhone;
                      _controller.isOrderAccepted = true;
                      _controller.hasActiveOrder = true;
                    });
                    
                    print('✅ Driver has accepted the order!');
                    print('📞 Driver Phone: $driverPhone');
                    print('👤 Driver Name: $driverName');
                    
                    // Show notification
                    _showDriverAcceptedNotification(driverName);
                  } 
                  // ✅ Reset if order is cancelled or completed
                  else if (status == 'cancelled' || status == 'completed' || status == 'delivered') {
                    _safeSetState(() {
                      _isDriverAccepted = false;
                      _assignedDriverId = null;
                      _assignedDriverPhone = null;
                      _assignedDriverName = null;
                      _controller.driverPhoneNumber = null;
                    });
                    _orderSubscription?.cancel();
                    _orderSubscription = null;
                  }
                });
          }
        })
        .catchError((e) {
          print('Error listening for driver acceptance: $e');
        });
  }

  void _showDriverAcceptedNotification(String? driverName) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🚗 Driver ${driverName ?? ''} has accepted your order!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    try {
      if (_controller.isLoading) {
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Finding your location...', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      }

      if (_controller.showFuelSelector && !_controller.hasActiveOrder) {
        return _buildFuelSelectorScreen();
      }

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || _isDisposed) return;
          
          if (_controller.hasActiveOrder || _controller.showConfirmButton) {
            _controller.showConfirmButton = false;
            _controller.selectedDriver = null;
            _controller.hasUserSelectedFuel = false;
            _controller.hasUserAdjustedLitres = false;
            _controller.hasUserSelectedDriver = false;
            _controller.notifyListeners();
            
            _safeSetState(() {});
            
            if (mounted && !_isDisposed) {
              try {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Press back again to exit'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                // Ignore - widget might be disposing
              }
            }
          } else {
            if (mounted && !_isDisposed) {
              try {
                Navigator.of(context).pop(result);
              } catch (e) {
                // Silently ignore - widget being disposed
              }
            }
          }
        },
        child: Scaffold(
          body: Stack(
            children: [
              GoogleMap(
                key: const ValueKey('homeMap'),
                initialCameraPosition: CameraPosition(
                  target: _controller.currentPosition != null 
                      ? LatLng(_controller.currentPosition!.latitude, _controller.currentPosition!.longitude) 
                      : const LatLng(-1.2921, 36.8219),
                  zoom: 16,
                  tilt: 65,
                ),
                markers: {
                  ..._controller.driverMarkers,
                  ..._controller.navigationArrowMarkers,
                },
                polylines: _controller.polylines,
                polygons: _controller.polygons,
                onMapCreated: (controller) {
                  if (_isDisposed) return;
                  _controller.mapController = controller;
                  _controller.isMapReady = true;
                  controller.setMapStyle(_controller.getMapStyle());
                  if (_controller.currentPosition != null) {
                    controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
                      target: LatLng(_controller.currentPosition!.latitude, _controller.currentPosition!.longitude),
                      zoom: 16,
                      tilt: 65,
                    )));
                  }
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                compassEnabled: true,
                mapType: MapType.normal,
                padding: EdgeInsets.only(
                  bottom: _controller.showVehicleSelector && !_controller.hasActiveOrder && !_controller.showConfirmButton && !_controller.showDriverInfo ? 
                    (_controller.isFuelSelectorExpanded ? 420 : 180) : 
                    _controller.showConfirmButton ? 200 :
                    _controller.showDriverInfo ? 200 : 180,
                ),
              ),

              if (_controller.showJunctionOverlay && _controller.isNavigating && !_controller.hasArrived)
                _buildJunctionOverlay(),

              if (_controller.showNavigationBanner && _controller.isNavigating && _controller.routeSteps.isNotEmpty && !_controller.hasArrived)
                _buildNavigationBanner(),

              if (_controller.isWaitingForDrivers && !_controller.isOrderAccepted && _controller.hasActiveOrder)
                _buildWaitingForDriver(),

              _buildTopStatusBar(),

              if (_controller.isOrderAccepted && _controller.isNavigating && _controller.driverActionText.isNotEmpty && !_controller.showNavigationBanner && !_controller.hasArrived)
                _buildDriverActionInfo(),

              if (_controller.showConfirmButton && _controller.selectedDriver != null && !_controller.hasActiveOrder && !_controller.isAutoSelecting && _controller.hasUserSelectedDriver)
                _buildConfirmOrderButton(),

              if (_controller.showUseAvailableButton && _controller.maxAvailableLitres > 0 && !_controller.hasActiveOrder && !_controller.showConfirmButton)
                _buildUseAvailableFuelButton(),

              // ============================================================
              // CALL DRIVER BUTTON - ONLY SHOWS AFTER DRIVER ACCEPTS ORDER ✅
              // ============================================================
              if (_isDriverAccepted && // ✅ ONLY when driver has accepted
                  _assignedDriverPhone != null && 
                  _assignedDriverPhone!.isNotEmpty &&
                  _assignedDriverPhone != 'N/A')
                Positioned(
                  bottom: _controller.hasArrived ? 140 : 100,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      key: const ValueKey('callDriverButton'),
                      onTap: () {
                        if (!_isDisposed && mounted) {
                          final name = _assignedDriverName ?? 'Driver';
                          final phone = _assignedDriverPhone ?? 'N/A';
                          _controller.callDriver(name, phone);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.6),
                              blurRadius: 15,
                              spreadRadius: 3,
                            ),
                            BoxShadow(
                              color: Colors.green.withOpacity(0.3),
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
                              size: 22,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Call Driver',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              _buildBottomSheet(),
            ],
          ),
        ),
      );
    } catch (e) {
      return const Scaffold(body: Center(child: Text('An unexpected UI error occurred.')));
    }
  }

  // ============================================================
  // FUEL SELECTOR SCREEN - LARGER FONTS
  // ============================================================
  Widget _buildFuelSelectorScreen() {
    return Scaffold(
      body: Container(
        key: const ValueKey('fuelSelectorScreen'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.green.shade700, Colors.green.shade100]
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⛽ Fuel Delivery',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select fuel type to find drivers near you',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What fuel do you need?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: GridView.builder(
                          key: const ValueKey('fuelGrid'),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: _controller.fuelOptions.length,
                          itemBuilder: (context, index) {
                            final fuel = _controller.fuelOptions[index];
                            final isSelected = _controller.selectedFuelType == fuel['fuelType'] && _controller.hasUserSelectedFuel;
                            final color = fuel['color'] as Color;
                            final imagePath = fuel['image'] as String;
                            final fuelType = fuel['fuelType'] as String;
                            
                            return GestureDetector(
                              key: ValueKey('fuel_${fuelType}_$index'),
                              onTap: () {
                                if (!_isDisposed && mounted) {
                                  _controller.selectFuel(fuelType);
                                  _safeSetState(() {});
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? color : Colors.grey.shade300,
                                    width: isSelected ? 3 : 1,
                                  ),
                                  boxShadow: isSelected ? [
                                    BoxShadow(
                                      color: color.withOpacity(0.4),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    )
                                  ] : null,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      FutureBuilder<Map<String, dynamic>>(
                                        future: _controller.getFuelImageData(imagePath),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData && snapshot.data!['bytes'] != null) {
                                            return Image.memory(
                                              snapshot.data!['bytes'] as Uint8List,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                color: color.withOpacity(0.3),
                                                child: Center(child: Text('⛽', style: TextStyle(fontSize: 48))),
                                              ),
                                            );
                                          }
                                          return Container(
                                            color: color.withOpacity(0.3),
                                            child: Center(child: Text('⛽', style: TextStyle(fontSize: 48))),
                                          );
                                        },
                                      ),
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.6)],
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const SizedBox(height: 20),
                                            Text(
                                              fuel['name'],
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w700,
                                                color: Colors.white,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black.withOpacity(0.5),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              fuel['subtitle'],
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.white.withOpacity(0.85),
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black.withOpacity(0.5),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.white, width: 2),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const ValueKey('findDriversButton'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              if (!_isDisposed && mounted && _controller.selectedFuelType.isNotEmpty) {
                                _controller.selectFuel(_controller.selectedFuelType);
                              }
                            },
                            child: const Text(
                              'Find Drivers',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // JUNCTION OVERLAY - LARGER FONTS
  // ============================================================
  Widget _buildJunctionOverlay() {
    return Positioned(
      top: 160,
      left: 16,
      right: 16,
      child: Container(
        key: const ValueKey('junctionOverlay'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.orange.shade300, width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _controller.getManeuverIcon(_controller.junctionManeuver),
                style: const TextStyle(fontSize: 28),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _controller.junctionManeuver.replaceAll('-', ' ').toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (_controller.junctionRoadName.isNotEmpty)
                    Text(
                      _controller.junctionRoadName,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  Text(
                    '${_controller.junctionDistance.round()} m',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (_controller.laneGuidance.isNotEmpty)
              Row(
                children: _controller.laneGuidance.map<Widget>((LaneInfo lane) {
                  return Container(
                    key: ValueKey('lane_${lane.displayChar}_${lane.recommended}'),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: lane.recommended ? Colors.blue : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                      border: lane.recommended 
                          ? Border.all(color: Colors.blue.shade700, width: 2)
                          : null,
                    ),
                    child: Text(
                      lane.displayChar,
                      style: TextStyle(
                        color: lane.recommended ? Colors.white : Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // NAVIGATION BANNER - LARGER FONTS
  // ============================================================
  Widget _buildNavigationBanner() {
    return Positioned(
      top: _controller.showJunctionOverlay ? 240 : 80,
      left: 16,
      right: 16,
      child: Container(
        key: const ValueKey('navigationBanner'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _controller.bannerProgress,
                child: Container(
                  decoration: BoxDecoration(
                    color: _controller.isSpeeding ? Colors.red : const Color(0xFF1A73E8),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _controller.bannerManeuver,
                            style: const TextStyle(fontSize: 24),
                          ),
                          if (_controller.laneGuidance.isNotEmpty)
                            Text(
                              _controller.laneGuidance.map((l) => l.displayChar).join(' '),
                              style: const TextStyle(fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_controller.bannerNextRoad.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade700,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _controller.bannerNextRoad.length > 8 
                                      ? _controller.bannerNextRoad.substring(0, 8) 
                                      : _controller.bannerNextRoad,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _controller.bannerInstruction,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.straighten,
                              size: 16,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _controller.bannerDistance.isNotEmpty ? _controller.bannerDistance : '0 m',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Icon(
                              Icons.access_time,
                              size: 16,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_controller.destinationEtaMinutes} min',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (_controller.speedLimit > 0) ...[
                              const SizedBox(width: 14),
                              Icon(
                                Icons.speed,
                                size: 16,
                                color: _controller.isSpeeding ? Colors.red : Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_controller.speedLimit} km/h',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _controller.isSpeeding ? Colors.red : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_controller.stepsCompleted + 1}/${_controller.totalSteps}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // WAITING FOR DRIVER - LARGER FONTS
  // ============================================================
  Widget _buildWaitingForDriver() {
    return Positioned(
      top: 80,
      left: 20,
      right: 20,
      child: Container(
        key: const ValueKey('waitingForDriver'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.green.shade200, width: 2),
        ),
        child: Column(
          children: [
            const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.green),
            ),
            const SizedBox(height: 10),
            Text(
              'Finding Your Driver...',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'A driver will be assigned to your order shortly.\nPlease wait...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '${_controller.activeOrderDetails?['fuelType'] ?? 'Fuel'} - ${_controller.activeOrderDetails?['litres'] ?? 0}L',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                if (!_isDisposed && mounted) {
                  _controller.cancelOrderWithReason();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Cancel Order',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TOP STATUS BAR - LARGER FONTS
  // ============================================================
  Widget _buildTopStatusBar() {
    return Positioned(
      top: 40,
      left: 16,
      right: 16,
      child: Row(
        key: const ValueKey('topStatusBar'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_controller.hasActiveOrder)
            GestureDetector(
              onTap: () {
                if (!_isDisposed && mounted) {
                  _controller.cancelOrderWithReason();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, color: Colors.red.shade700, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Spacer(),
          if (!_controller.showConfirmButton && !_controller.showDriverInfo)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<Map<String, dynamic>>(
                    future: _controller.getFuelImageData(
                      _controller.fuelTypes[_controller.selectedFuelType]!['image'] as String
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data!['bytes'] != null) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            snapshot.data!['bytes'] as Uint8List,
                            width: 24,
                            height: 24,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Text('⛽', style: TextStyle(fontSize: 18)),
                          ),
                        );
                      }
                      return const Text('⛽', style: TextStyle(fontSize: 18));
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _controller.hasActiveOrder && _controller.isOrderAccepted && _controller.estimatedMinutes != null
                        ? '${_controller.estimatedMinutes ?? 2} min'
                        : _controller.hasActiveOrder ? 'Waiting' : _controller.selectedFuelType,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 18)),
                  const SizedBox(width: 6),
                  if (_controller.isSpeeding && _controller.hasActiveOrder && _controller.isOrderAccepted)
                    Icon(Icons.speed, color: Colors.red, size: 18)
                  else if (_controller.isDriverTurning && _controller.hasActiveOrder && _controller.isOrderAccepted)
                    Icon(Icons.turn_right, color: Colors.orange, size: 18)
                  else if (_controller.hasActiveOrder && _controller.isOrderAccepted)
                    Icon(Icons.straighten, color: Colors.green, size: 18)
                  else
                    Text(
                      _controller.isOrderAccepted ? _controller.driverStatusText : _controller.hasActiveOrder ? 'Finding driver' : 'Now',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _controller.isOrderAccepted ? Colors.grey.shade600 : Colors.orange,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // DRIVER ACTION INFO - LARGER FONTS
  // ============================================================
  Widget _buildDriverActionInfo() {
    return Positioned(
      top: 90,
      left: 16,
      right: 16,
      child: Container(
        key: const ValueKey('driverActionInfo'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _controller.isSpeeding ? Colors.red.shade700.withOpacity(0.9) : Colors.blue.shade700.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _controller.getManeuverIcon(_controller.nextManeuver),
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _controller.isSpeeding ? '⚠️ SPEEDING: ${_controller.currentSpeed.toStringAsFixed(0)} km/h' : _controller.driverActionText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_controller.totalSteps > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_controller.stepsCompleted + 1}/${_controller.totalSteps}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CONFIRM ORDER BUTTON - LARGER FONTS
  // ============================================================
  Widget _buildConfirmOrderButton() {
    return Positioned(
      bottom: 200,
      left: 16,
      right: 16,
      child: Container(
        key: const ValueKey('confirmOrderButton'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.green.shade300, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(Icons.local_gas_station, color: Colors.green, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Driver Selected',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Row(
                        children: [
                          Icon(Icons.local_gas_station, size: 16, color: Colors.green.shade700),
                          const SizedBox(width: 4),
                          Text(
                            '${_controller.selectedDriver!['remainingFuel']?.toStringAsFixed(0) ?? '0'}L',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.timer, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 4),
                          Text(
                            '${_controller.selectedDriver!['distance']?.toStringAsFixed(1) ?? '0'} km',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _controller.isAutoSelecting ? null : () {
                      if (!_isDisposed && mounted) {
                        _controller.confirmOrder();
                      }
                    },
                    child: _controller.isAutoSelecting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, color: Colors.white, size: 22),
                              SizedBox(width: 8),
                              Text('Confirm Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blue),
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    if (!_isDisposed && mounted) {
                      _controller.goToUserProfile();
                    }
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person, size: 22),
                      SizedBox(width: 4),
                      Text('Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // USE AVAILABLE FUEL BUTTON - LARGER FONTS
  // ============================================================
  Widget _buildUseAvailableFuelButton() {
    return Positioned(
      bottom: 170,
      left: 16,
      right: 16,
      child: ElevatedButton(
        key: const ValueKey('useAvailableFuelButton'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 4,
        ),
        onPressed: () {
          if (!_isDisposed && mounted) {
            _controller.useAvailableFuel();
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              'Use ${_controller.maxAvailableLitres.toStringAsFixed(0)}L Available',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SMOOTH DRAGGABLE BOTTOM SHEET - WITH V-POWER + 3 FUEL OPTIONS
  // ============================================================
  Widget _buildBottomSheet() {
    final bool showBottomSheet = !_controller.hasActiveOrder && 
                                  !_controller.showConfirmButton && 
                                  !_controller.showDriverInfo &&
                                  !_controller.isOrderAccepted;

    if (!showBottomSheet) {
      return const SizedBox.shrink();
    }

    final double expandedHeight = MediaQuery.of(context).size.height * 0.50;
    final double collapsedHeight = 70.0;
    final double maxHeight = expandedHeight;
    final double minHeight = collapsedHeight;
    
    final double currentHeight = _controller.isFuelSelectorExpanded ? maxHeight : minHeight;
    final double actualHeight = (currentHeight - _bottomSheetDragOffset.clamp(_minDragLimit, _maxDragLimit))
        .clamp(minHeight, maxHeight);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Transform.translate(
        offset: Offset(0.0, _bottomSheetDragOffset.clamp(_minDragLimit, _maxDragLimit)),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (details) {
            if (_isDisposed) return;
            _safeSetState(() {
              _isDragging = true;
            });
          },
          onVerticalDragUpdate: (details) {
            if (_isDisposed) return;
            
            _throttledDragOffset += details.primaryDelta ?? 0.0;
            
            if (_swipeThrottleTimer == null) {
              _swipeThrottleTimer = Timer(const Duration(milliseconds: 16), () {
                _safeSetState(() {
                  _bottomSheetDragOffset += _throttledDragOffset;
                  _throttledDragOffset = 0.0;
                  
                  final double progress = _bottomSheetDragOffset / _maxDragLimit;
                  if (progress > 0.5) {
                    _controller.isFuelSelectorExpanded = false;
                  } else {
                    _controller.isFuelSelectorExpanded = true;
                  }
                });
                _swipeThrottleTimer = null;
              });
            }
          },
          onVerticalDragEnd: (details) {
            if (_isDisposed) return;
            
            _safeSetState(() {
              _isDragging = false;
              
              if (_bottomSheetDragOffset > (_maxDragLimit / 2)) {
                _controller.isFuelSelectorExpanded = false;
                _bottomSheetDragOffset = _maxDragLimit;
              } else {
                _controller.isFuelSelectorExpanded = true;
                _bottomSheetDragOffset = _minDragLimit;
              }
              _throttledDragOffset = 0.0;
            });
          },
          child: Container(
            height: _sheetHeight,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10.0,
                  spreadRadius: 2.0,
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      width: 50,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            if (_controller.isFuelSelectorExpanded) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '⛽ ${_controller.fuelTypes.length} Fuel Options',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.swipe_down,
                                          size: 20,
                                          color: Colors.green.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Swipe down',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 10),
                              
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _controller.fuelTypes.keys.length,
                                itemBuilder: (context, index) {
                                  final fuel = _controller.fuelTypes.keys.elementAt(index);
                                  final fuelData = _controller.fuelTypes[fuel]!;
                                  final isSelected = _controller.selectedFuelType == fuel && _controller.hasUserSelectedFuel;
                                  final price = fuelData['price'] as double;
                                  final imagePath = fuelData['image'] as String;
                                  final color = fuelData['color'] as Color;
                                  final availableDrivers = _controller.nearbyDrivers.where((d) => d['fuelType'] == fuel && d['remainingFuel'] >= _controller.selectedLitres).length;
                                  final eta = _controller.calculateEta(availableDrivers > 0 ? 2 : 5);
                                  final maxFuel = _controller.maxAvailableLitres;

                                  return GestureDetector(
                                    key: ValueKey('fuelItem_${fuel}_$index'),
                                    onTap: () {
                                      if (_isDisposed) return;
                                      _controller.selectedFuelType = fuel;
                                      _controller.selectedLitres = 20;
                                      _controller.isLitresValid = true;
                                      _controller.litresErrorMessage = '';
                                      _controller.showUseAvailableButton = false;
                                      _controller.selectedDriver = null;
                                      _controller.showConfirmButton = false;
                                      _controller.hasUserSelectedFuel = true;
                                      _controller.hasUserAdjustedLitres = false;
                                      _controller.hasUserSelectedDriver = false;
                                      
                                      _controller.isFuelSelectorExpanded = true;
                                      
                                      if (mounted && !_isDisposed) {
                                        _controller.notifyListeners();
                                        _safeSetState(() {});
                                      }
                                      _controller.loadNearbyDrivers();
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? color.withOpacity(0.08) : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected ? color : Colors.grey.shade200,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          FutureBuilder<Map<String, dynamic>>(
                                            future: _controller.getFuelImageData(imagePath),
                                            builder: (context, snapshot) {
                                              if (snapshot.hasData && snapshot.data!['bytes'] != null) {
                                                return ClipRRect(
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: Image.memory(
                                                    snapshot.data!['bytes'] as Uint8List,
                                                    width: 48,
                                                    height: 48,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Container(
                                                      width: 48,
                                                      height: 48,
                                                      decoration: BoxDecoration(
                                                        color: color.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: const Center(child: Text('⛽', style: TextStyle(fontSize: 22))),
                                                    ),
                                                  ),
                                                );
                                              }
                                              return Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: color.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Center(child: Text('⛽', style: TextStyle(fontSize: 22))),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      fuel,
                                                      style: TextStyle(
                                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                        fontSize: 18,
                                                        color: isSelected ? color : Colors.black,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '• KES $price',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                        color: isSelected ? color : Colors.black,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '$eta min',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w500,
                                                        color: Colors.grey.shade600,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: availableDrivers > 0 ? Colors.green.shade100 : Colors.red.shade100,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        '$availableDrivers avail',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                          color: availableDrivers > 0 ? Colors.green.shade700 : Colors.red.shade700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isSelected ? color : Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              isSelected ? '✓' : 'Select',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected ? Colors.white : Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              
                              const SizedBox(height: 10),
                              
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '${_controller.selectedLitres.toStringAsFixed(0)}L',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              'KES ${((_controller.fuelTypes[_controller.selectedFuelType]!['price'] as double) * _controller.selectedLitres).toStringAsFixed(0)}',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Slider(
                                          key: const ValueKey('litresSlider'),
                                          value: _controller.selectedLitres,
                                          min: 5,
                                          max: _controller.maxAvailableLitres > 0 ? _controller.maxAvailableLitres : 200,
                                          divisions: _controller.maxAvailableLitres > 0 ? (_controller.maxAvailableLitres ~/ 1).toInt() : 39,
                                          activeColor: _controller.isLitresValid ? Colors.green : Colors.red,
                                          inactiveColor: Colors.grey.shade300,
                                          onChanged: (value) {
                                            if (!_isDisposed && mounted) {
                                              _controller.onLitresChanged(value);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _controller.isLitresValid && _controller.nearbyDrivers.isNotEmpty ? Colors.green : Colors.grey,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: (_controller.isLitresValid && _controller.nearbyDrivers.isNotEmpty && !_isDisposed && mounted)
                                        ? _controller.selectDriver
                                        : null,
                                    child: Text(
                                      _controller.nearbyDrivers.isEmpty
                                          ? 'No Drivers'
                                          : 'Select Driver',
                                      style: TextStyle(
                                        color: _controller.isLitresValid && _controller.nearbyDrivers.isNotEmpty ? Colors.white : Colors.grey.shade600,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 6),
                              
                              if (_controller.litresErrorMessage.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning, color: Colors.red.shade700, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _controller.litresErrorMessage,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.red.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ] else ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.swipe_up,
                                      size: 20,
                                      color: Colors.red.shade500,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '⬆️ Swipe up for fuel options',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _controller.selectedFuelType.isNotEmpty ? _controller.selectedFuelType : 'Select Fuel',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}