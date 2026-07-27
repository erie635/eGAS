import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserMapPage extends StatefulWidget {
  const UserMapPage({super.key});

  @override
  State<UserMapPage> createState() => _UserMapPageState();
}

class _UserMapPageState extends State<UserMapPage> {
  Position? _currentPosition;
  bool _isLoading = true;
  List<QueryDocumentSnapshot> _nearbyDrivers = [];
  String? _selectedFuelType;

  final Map<String, double> _fuelPrices = {
    'Petrol': 185.0,
    'Diesel': 172.0,
    'Kerosene': 140.0,
    'V-Power': 205.0,
  };

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services')),
      );
      setState(() => _isLoading = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    _currentPosition = await Geolocator.getCurrentPosition();
    setState(() => _isLoading = false);
    _loadNearbyDrivers();
  }

  Future<void> _loadNearbyDrivers() async {
    if (_currentPosition == null) return;

    var drivers = await FirebaseFirestore.instance
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .get();
    
    List<QueryDocumentSnapshot> nearby = [];
    
    for (var doc in drivers.docs) {
      double lat = doc['lat'] ?? 0;
      double lng = doc['lng'] ?? 0;
      
      if (lat == 0 && lng == 0) continue;
      
      double distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        lat,
        lng,
      ) / 1000;
      
      if (distance <= 10) {
        nearby.add(doc);
      }
    }
    
    setState(() => _nearbyDrivers = nearby);
  }

  void _orderFuel(QueryDocumentSnapshot driver) {
    showDialog(
      context: context,
      builder: (context) {
        double litres = 20;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            double total = (_selectedFuelType != null ? _fuelPrices[_selectedFuelType!]! : 185) * litres;
            return AlertDialog(
              title: const Text('Order Fuel'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Driver: ${driver['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedFuelType,
                    decoration: const InputDecoration(labelText: 'Select Fuel Type'),
                    items: _fuelPrices.keys.map((fuel) {
                      return DropdownMenuItem(
                        value: fuel,
                        child: Text('$fuel - KES ${_fuelPrices[fuel]}/L'),
                      );
                    }).toList(),
                    onChanged: (value) => setStateDialog(() => _selectedFuelType = value),
                  ),
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
                  Text('Total: KES ${total.toStringAsFixed(2)}', 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () async {
                    if (_selectedFuelType == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select fuel type')),
                      );
                      return;
                    }
                    
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
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Order placed! Driver notified')),
                    );
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _nearbyDrivers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_gas_station, size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text('No fuel tankers around your location', 
                        style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text('Check back later', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNearbyDrivers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _nearbyDrivers.length,
                    itemBuilder: (context, index) {
                      final driver = _nearbyDrivers[index];
                      return Card(
                        elevation: 3,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            child: const Icon(Icons.local_gas_station, color: Colors.green),
                          ),
                          title: Text(driver['name'] ?? 'Fuel Tanker'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Vehicle: ${driver['vehicleType'] ?? 'Fuel Truck'}'),
                              Text('Plate: ${driver['numberPlate'] ?? 'N/A'}'),
                            ],
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () => _orderFuel(driver),
                            child: const Text('Order'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}