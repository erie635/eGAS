import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class HomeMapPage extends StatefulWidget {
  const HomeMapPage({super.key});

  @override
  State<HomeMapPage> createState() => _HomeMapPageState();
}

class _HomeMapPageState extends State<HomeMapPage> {
  GoogleMapController? _mapController;
  Set<Marker> _driverMarkers = {};
  Position? _currentPosition;
  bool _isLoading = true;
  bool _isMapReady = false;
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _nearbyDrivers = [];

  // Fuel types with prices and icons
  final Map<String, Map<String, dynamic>> _fuelTypes = {
    'Petrol': {
      'price': 185.0,
      'icon': '⛽',
      'color': Colors.green,
    },
    'Diesel': {
      'price': 172.0,
      'icon': '🛢️',
      'color': Colors.blue,
    },
    'Kerosene': {
      'price': 140.0,
      'icon': '🔥',
      'color': Colors.orange,
    },
    'V-Power': {
      'price': 205.0,
      'icon': '⚡',
      'color': Colors.purple,
    },
  };

  String _selectedFuelType = 'Petrol';
  double _selectedLitres = 20;
  String? _selectedDriverId;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isMapReady) _loadNearbyDrivers();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission permanently denied')),
      );
      return;
    }

    _currentPosition = await Geolocator.getCurrentPosition();
    setState(() => _isLoading = false);
    
    if (_mapController != null && _currentPosition != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            zoom: 15,
          ),
        ),
      );
    }
    _loadNearbyDrivers();
  }

  Future<void> _loadNearbyDrivers() async {
    if (_currentPosition == null) return;

    try {
      final drivers = await FirebaseFirestore.instance
          .collection('drivers')
          .where('isOnline', isEqualTo: true)
          .get();

      Set<Marker> markers = {};
      List<Map<String, dynamic>> nearby = [];

      for (var doc in drivers.docs) {
        final data = doc.data();
        double lat = (data['lat'] ?? 0).toDouble();
        double lng = (data['lng'] ?? 0).toDouble();

        if (lat == 0 && lng == 0) continue;

        double distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          lat,
          lng,
        ) / 1000;

        // Check if driver has the selected fuel type available
        bool hasFuel = data['remainingFuel'] != null && 
                       data['remainingFuel'][_selectedFuelType] != null &&
                       data['remainingFuel'][_selectedFuelType] >= _selectedLitres;

        if (distance <= 10 && hasFuel) {
          final fuelType = _selectedFuelType;
          final price = _fuelTypes[fuelType]!['price'] as double;
          final fuelIcon = _fuelTypes[fuelType]!['icon'] as String;

          nearby.add({
            'id': doc.id,
            'data': data,
            'distance': distance,
            'fuelType': fuelType,
            'price': price,
            'fuelIcon': fuelIcon,
            'remainingFuel': data['remainingFuel']?[_selectedFuelType] ?? 0,
          });

          markers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
              onTap: () => _showDriverDetails(doc, distance, price, fuelIcon),
              infoWindow: InfoWindow(
                title: data['name'] ?? 'Fuel Tanker',
                snippet: '${distance.toStringAsFixed(2)}km • ${_selectedFuelType} KES ${price}/L',
              ),
            ),
          );
        }
      }

      setState(() {
        _driverMarkers = markers;
        _nearbyDrivers = nearby;
      });

      if (nearby.isEmpty) {
        _showNoDriversFound();
      }
    } catch (e) {
      print('Error loading drivers: $e');
    }
  }

  void _showNoDriversFound() {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No available drivers with ${_selectedFuelType} fuel nearby. Try another fuel type.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showDriverDetails(QueryDocumentSnapshot driver, double distance, double price, String fuelIcon) {
    final data = driver.data() as Map<String, dynamic>;
    final remainingFuel = data['remainingFuel']?[_selectedFuelType] ?? 0;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Center(
                      child: Text(
                        fuelIcon,
                        style: const TextStyle(fontSize: 30),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['name'] ?? 'Fuel Tanker',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _selectedFuelType,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'KES ${price}/L',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${distance.toStringAsFixed(2)}km',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),

              Row(
                children: [
                  const Icon(Icons.local_shipping, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Vehicle: ${data['vehicleType'] ?? 'Fuel Truck'}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.confirmation_number, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Plate: ${data['numberPlate'] ?? 'KBZ 123A'}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Est. arrival: ${(distance * 2).toStringAsFixed(0)} min',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.local_gas_station, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Available: ${remainingFuel.toStringAsFixed(0)}L of $_selectedFuelType',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _showOrderDialog(driver, price);
                  },
                  child: const Text(
                    'Order Fuel Now',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOrderDialog(QueryDocumentSnapshot driver, double pricePerLiter) {
    double litres = 20;
    final data = driver.data() as Map<String, dynamic>;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            double total = pricePerLiter * litres;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  const Icon(Icons.local_gas_station, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('Order ${_selectedFuelType}'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          data['name'] ?? 'Fuel Tanker',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_getDistanceToDriver(data).toStringAsFixed(2)}km',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '${_fuelTypes[_selectedFuelType]!['icon']} ',
                        style: const TextStyle(fontSize: 20),
                      ),
                      Text(
                        _selectedFuelType,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'KES ${pricePerLiter.toStringAsFixed(2)}/L',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Quantity: ', style: TextStyle(fontSize: 16)),
                      Expanded(
                        child: Slider(
                          value: litres,
                          min: 5,
                          max: 200,
                          divisions: 39,
                          activeColor: Colors.green,
                          onChanged: (val) => setStateDialog(() => litres = val),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${litres.toStringAsFixed(0)}L',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'KES ${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please login first')),
                      );
                      return;
                    }

                    try {
                      // Check if driver has enough fuel
                      final driverDoc = await FirebaseFirestore.instance
                          .collection('drivers')
                          .doc(driver.id)
                          .get();
                      
                      final driverData = driverDoc.data();
                      final remainingFuel = driverData?['remainingFuel']?[_selectedFuelType] ?? 0;
                      
                      if (remainingFuel < litres) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Driver only has ${remainingFuel.toStringAsFixed(0)}L of $_selectedFuelType available. Please reduce quantity or choose another driver.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // Create order
                      await FirebaseFirestore.instance.collection('orders').add({
                        'driverId': driver.id,
                        'driverName': data['name'] ?? 'Fuel Tanker',
                        'driverPhone': data['phone'] ?? 'N/A',
                        'fuelType': _selectedFuelType,
                        'litres': litres,
                        'pricePerLiter': pricePerLiter,
                        'totalPrice': total,
                        'userId': user.uid,
                        'userName': user.displayName ?? 'Customer',
                        'userPhone': user.phoneNumber ?? 'N/A',
                        'userLocation': _currentPosition != null
                            ? GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude)
                            : null,
                        'status': 'pending',
                        'createdAt': FieldValue.serverTimestamp(),
                        'customerLat': _currentPosition?.latitude ?? 0,
                        'customerLng': _currentPosition?.longitude ?? 0,
                      });

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Order placed! Driver will arrive soon.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  },
                  child: const Text('Place Order'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double _getDistanceToDriver(Map<String, dynamic> data) {
    if (_currentPosition == null) return 0;
    double lat = (data['lat'] ?? 0).toDouble();
    double lng = (data['lng'] ?? 0).toDouble();
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      lat,
      lng,
    ) / 1000;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Finding your location...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.local_gas_station, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('⛽ Fuel Delivery'),
          ],
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text(
                    _fuelTypes[_selectedFuelType]!['icon'] as String,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _selectedFuelType,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                ],
              ),
            ),
            onSelected: (value) {
              setState(() => _selectedFuelType = value);
              _loadNearbyDrivers();
            },
            itemBuilder: (context) {
              return _fuelTypes.keys.map((fuel) {
                return PopupMenuItem(
                  value: fuel,
                  child: Row(
                    children: [
                      Text(_fuelTypes[fuel]!['icon'] as String),
                      const SizedBox(width: 8),
                      Text(fuel),
                      const Spacer(),
                      Text(
                        'KES ${_fuelTypes[fuel]!['price']}/L',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNearbyDrivers,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_nearbyDrivers.length} available',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null
                  ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                  : const LatLng(-1.2921, 36.8219),
              zoom: 15,
            ),
            markers: _driverMarkers,
            onMapCreated: (controller) {
              _mapController = controller;
              _isMapReady = true;
              if (_currentPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      zoom: 15,
                    ),
                  ),
                );
              }
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            compassEnabled: true,
          ),

          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.radio_button_checked, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '10km radius',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_gas_station, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        '${_fuelTypes[_selectedFuelType]!['icon']} $_selectedFuelType',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.green.shade300, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${_nearbyDrivers.length} available',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
