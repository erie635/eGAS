import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class UserMapPage extends StatefulWidget {
  const UserMapPage({super.key});

  @override
  State<UserMapPage> createState() => _UserMapPageState();
}

class _UserMapPageState extends State<UserMapPage> {
  GoogleMapController? _mapController;
  Set<Marker> _driverMarkers = {};
  Position? _currentPosition;
  String? _selectedFuelType;
  bool _isLoading = true;
  Timer? _refreshTimer;

  final Map<String, dynamic> _fuelPrices = {
    'Petrol': 185.0,
    'Diesel': 172.0,
    'Kerosene': 140.0,
    'V-Power': 205.0,
  };

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _loadNearbyDrivers();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    _currentPosition = await Geolocator.getCurrentPosition();
    setState(() => _isLoading = false);
    
    if (_mapController != null && _currentPosition != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude), zoom: 14),
        ),
      );
    }
    _loadNearbyDrivers();
  }

  Future<void> _loadNearbyDrivers() async {
    if (_currentPosition == null) return;

    var drivers = await FirebaseFirestore.instance.collection('drivers').where('isOnline', isEqualTo: true).get();
    
    Set<Marker> markers = {};
    
    for (var doc in drivers.docs) {
      double lat = doc['lat'] ?? 0;
      double lng = doc['lng'] ?? 0;
      
      if (lat == 0 && lng == 0) continue;
      
      double distance = _calculateDistance(
        _currentPosition!.latitude, _currentPosition!.longitude, lat, lng,
      );
      
      if (distance <= 10) {
        markers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            onTap: () => _showDriverBottomSheet(doc),
            infoWindow: InfoWindow(
              title: doc['name'] ?? 'Fuel Tanker',
              snippet: '${_selectedFuelType ?? 'Petrol'}: KES ${_fuelPrices[_selectedFuelType ?? 'Petrol']}/L • ${distance.toStringAsFixed(1)}km away',
            ),
          ),
        );
      }
    }
    
    setState(() => _driverMarkers = markers);
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  void _showDriverBottomSheet(QueryDocumentSnapshot driver) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 40, backgroundColor: Colors.green.shade100, child: const Icon(Icons.local_gas_station, size: 40, color: Colors.green)),
              const SizedBox(height: 12),
              Text(driver['name'] ?? 'Fuel Tanker', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Vehicle: ${driver['vehicleType'] ?? 'Fuel Truck'}', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text('Plate: ${driver['numberPlate'] ?? 'KBZ 123A'}', style: const TextStyle(fontSize: 16)),
              const Divider(height: 32),
              const Text('Select Fuel Type:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: _fuelPrices.keys.map((fuel) {
                  return FilterChip(
                    label: Text('$fuel\nKES ${_fuelPrices[fuel]}/L'),
                    selected: _selectedFuelType == fuel,
                    onSelected: (selected) {
                      setState(() => _selectedFuelType = selected ? fuel : null);
                      Navigator.pop(context);
                      _showOrderDialog(driver);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOrderDialog(QueryDocumentSnapshot driver) {
    if (_selectedFuelType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select fuel type')));
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        double litres = 20;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            double total = _fuelPrices[_selectedFuelType!] * litres;
            return AlertDialog(
              title: Text('Order ${_selectedFuelType!}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Driver: ${driver['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text('Price: KES ${_fuelPrices[_selectedFuelType!]}/L'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Litres: '),
                      Expanded(
                        child: Slider(
                          value: litres,
                          min: 5,
                          max: 200,
                          divisions: 39,
                          onChanged: (val) => setStateDialog(() => litres = val),
                        ),
                      ),
                      Text('${litres.toStringAsFixed(0)}L'),
                    ],
                  ),
                  const Divider(),
                  Text('Total: KES ${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    await FirebaseFirestore.instance.collection('orders').add({
                      'driverId': driver.id,
                      'driverName': driver['name'],
                      'fuelType': _selectedFuelType,
                      'litres': litres,
                      'totalPrice': total,
                      'userId': user?.uid ?? 'unknown',
                      'status': 'pending',
                      'createdAt': FieldValue.serverTimestamp(),
                      'userLocation': GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude),
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order placed! Driver notified')));
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Fuel Near You'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNearbyDrivers,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
        ],
      ),
      body: _driverMarkers.isEmpty && !_isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_gas_station, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('No fuel tankers around your location', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('Check back later', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                zoom: 14,
              ),
              markers: _driverMarkers,
              onMapCreated: (controller) => _mapController = controller,
              myLocationEnabled: true,
              zoomControlsEnabled: true,
            ),
    );
  }
}
