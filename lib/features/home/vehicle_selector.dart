import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VehicleSelector extends StatefulWidget {
  final Position? currentPosition;
  const VehicleSelector({super.key, this.currentPosition});

  @override
  State<VehicleSelector> createState() => _VehicleSelectorState();
}

class _VehicleSelectorState extends State<VehicleSelector> {
  String _selectedFuelType = 'Petrol';
  String? _selectedVehicleId;
  List<Map<String, dynamic>> _availableVehicles = [];
  bool _isLoading = true;
  String _errorMessage = '';

  final Map<String, Map<String, dynamic>> _fuelTypes = {
    'Petrol': {'price': 185.0, 'icon': '⛽'},
    'Diesel': {'price': 172.0, 'icon': '🛢️'},
    'Kerosene': {'price': 140.0, 'icon': '🔥'},
    'V-Power': {'price': 205.0, 'icon': '⚡'},
  };

  // Vehicle type images
  final Map<String, Map<String, dynamic>> _vehicleTypes = {
    'small': {
      'name': 'Small Tanker',
      'icon': '🚗',
      'capacity': '100L',
      'color': Colors.green,
      'priceMultiplier': 1.0,
    },
    'medium': {
      'name': 'Medium Tanker',
      'icon': '🚚',
      'capacity': '500L',
      'color': Colors.blue,
      'priceMultiplier': 0.8,
    },
    'big': {
      'name': 'Large Tanker',
      'icon': '🚛',
      'capacity': '1000L',
      'color': Colors.orange,
      'priceMultiplier': 0.6,
    },
  };

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (widget.currentPosition == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Location not available. Please enable GPS.';
        });
        return;
      }

      final drivers = await FirebaseFirestore.instance
          .collection('drivers')
          .where('isOnline', isEqualTo: true)
          .get();

      print('✅ Found ${drivers.docs.length} online drivers');

      if (drivers.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No online drivers available.';
        });
        return;
      }

      List<Map<String, dynamic>> vehicles = [];

      for (var doc in drivers.docs) {
        final data = doc.data();
        double lat = (data['lat'] ?? 0).toDouble();
        double lng = (data['lng'] ?? 0).toDouble();

        if (lat == 0 && lng == 0) continue;

        double distance = Geolocator.distanceBetween(
          widget.currentPosition!.latitude,
          widget.currentPosition!.longitude,
          lat,
          lng,
        ) / 1000;

        if (distance > 10) continue;

        String vehicleType = data['vehicleType']?.toLowerCase() ?? 'medium';
        String fuelType = _selectedFuelType;
        double pricePerLiter = _fuelTypes[fuelType]?['price'] ?? 185.0;
        double priceMultiplier = _vehicleTypes[vehicleType]?['priceMultiplier'] ?? 1.0;
        double adjustedPrice = pricePerLiter * priceMultiplier;

        final remainingFuel = data['remainingFuel'] ?? {};
        final fuelAmount = (remainingFuel[fuelType] ?? 0).toDouble();

        if (fuelAmount > 0) {
          vehicles.add({
            'id': doc.id,
            'name': data['name'] ?? 'Fuel Tanker',
            'vehicleType': vehicleType,
            'lat': lat,
            'lng': lng,
            'distance': distance,
            'price': adjustedPrice,
            'fuelAvailable': fuelAmount,
            'plateNumber': data['numberPlate'] ?? 'N/A',
            'driverPhone': data['phone'] ?? 'N/A',
            'photoUrl': data['photoUrl'] ?? '', // Get driver photo
            'vehicleIcon': _vehicleTypes[vehicleType]?['icon'] ?? '🚚',
            'vehicleColor': _vehicleTypes[vehicleType]?['color'] ?? Colors.blue,
            'capacity': _vehicleTypes[vehicleType]?['capacity'] ?? '500L',
            'isOnline': data['isOnline'] ?? false,
          });
        }
      }

      vehicles.sort((a, b) => (a['distance'] ?? 0).compareTo(b['distance'] ?? 0));

      setState(() {
        _availableVehicles = vehicles;
        _isLoading = false;
        if (vehicles.isEmpty) {
          _errorMessage = 'No drivers with $_selectedFuelType fuel available within 10km.';
        }
      });
    } catch (e) {
      print('❌ Error loading vehicles: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading vehicles: $e';
      });
    }
  }

  // ============================================================
  // NEW: Widget to display driver image with fallback
  // ============================================================
  Widget _buildDriverImage(String? photoUrl, String? vehicleIcon) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          photoUrl,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // If image fails to load, show vehicle icon as fallback
            return Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  vehicleIcon ?? '🚚',
                  style: const TextStyle(fontSize: 32),
                ),
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          },
        ),
      );
    } else {
      // No photo URL, show vehicle icon
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            vehicleIcon ?? '🚚',
            style: const TextStyle(fontSize: 32),
          ),
        ),
      );
    }
  }

  void _selectVehicle(Map<String, dynamic> vehicle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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

              // ============================================================
              // UPDATED: Show driver image with photoUrl
              // ============================================================
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: vehicle['photoUrl'] != null && vehicle['photoUrl'].isNotEmpty
                      ? Image.network(
                          vehicle['photoUrl'],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                vehicle['vehicleIcon'] ?? '🚚',
                                style: const TextStyle(fontSize: 48),
                              ),
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          },
                        )
                      : Center(
                          child: Text(
                            vehicle['vehicleIcon'] ?? '🚚',
                            style: const TextStyle(fontSize: 48),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Vehicle Details
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicle['name'] ?? 'Vehicle',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (vehicle['vehicleColor'] as Color?)?.withOpacity(0.1) ?? Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                vehicle['vehicleType']?.toUpperCase() ?? 'MEDIUM',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: vehicle['vehicleColor'] ?? Colors.green,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${vehicle['distance']?.toStringAsFixed(2) ?? 0} km',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'KES ${vehicle['price']?.toStringAsFixed(2) ?? 0}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        'per litre',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const Divider(height: 24),

              // Fuel Details
              Row(
                children: [
                  const Icon(Icons.local_gas_station, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Available: ${vehicle['fuelAvailable']?.toStringAsFixed(0) ?? 0}L',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const Spacer(),
                  const Icon(Icons.confirmation_number, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Plate: ${vehicle['plateNumber']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.phone, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Driver: ${vehicle['driverPhone']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const Spacer(),
                  const Icon(Icons.inventory_2, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Capacity: ${vehicle['capacity']}',
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
                    _showOrderDialog(vehicle);
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

  void _showOrderDialog(Map<String, dynamic> vehicle) {
    double litres = 20;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            double total = (vehicle['price'] ?? 0) * litres;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  // Show small driver image in dialog
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey.shade200,
                      image: vehicle['photoUrl'] != null && vehicle['photoUrl'].isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(vehicle['photoUrl']),
                              fit: BoxFit.cover,
                              onError: (exception, stackTrace) => null,
                            )
                          : null,
                    ),
                    child: vehicle['photoUrl'] == null || vehicle['photoUrl'].isEmpty
                        ? Center(
                            child: Text(
                              vehicle['vehicleIcon'] ?? '🚚',
                              style: const TextStyle(fontSize: 16),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  const Text('Order Fuel'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        // Driver image in order dialog
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade200,
                            image: vehicle['photoUrl'] != null && vehicle['photoUrl'].isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(vehicle['photoUrl']),
                                    fit: BoxFit.cover,
                                    onError: (exception, stackTrace) => null,
                                  )
                                : null,
                          ),
                          child: vehicle['photoUrl'] == null || vehicle['photoUrl'].isEmpty
                              ? Center(
                                  child: Text(
                                    vehicle['vehicleIcon'] ?? '🚚',
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            vehicle['name'] ?? 'Vehicle',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${vehicle['distance']?.toStringAsFixed(2) ?? 0}km',
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
                        '${_fuelTypes[_selectedFuelType]?['icon']} ',
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
                        'KES ${vehicle['price']?.toStringAsFixed(2) ?? 0}/L',
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
                      final driverDoc = await FirebaseFirestore.instance
                          .collection('drivers')
                          .doc(vehicle['id'])
                          .get();

                      final driverData = driverDoc.data();
                      final remainingFuel = driverData?['remainingFuel']?[_selectedFuelType] ?? 0;

                      if (remainingFuel < litres) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Driver only has ${remainingFuel.toStringAsFixed(0)}L of $_selectedFuelType available.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      await FirebaseFirestore.instance.collection('orders').add({
                        'driverId': vehicle['id'],
                        'driverName': vehicle['name'] ?? 'Fuel Tanker',
                        'driverPhone': vehicle['driverPhone'] ?? 'N/A',
                        'driverPhoto': vehicle['photoUrl'] ?? '', // Save driver photo
                        'fuelType': _selectedFuelType,
                        'litres': litres,
                        'pricePerLiter': vehicle['price'] ?? 185.0,
                        'totalPrice': total,
                        'userId': user.uid,
                        'userName': user.displayName ?? 'Customer',
                        'userPhone': user.phoneNumber ?? 'N/A',
                        'userLocation': widget.currentPosition != null
                            ? GeoPoint(widget.currentPosition!.latitude, widget.currentPosition!.longitude)
                            : null,
                        'status': 'pending',
                        'vehicleType': vehicle['vehicleType'] ?? 'medium',
                        'createdAt': FieldValue.serverTimestamp(),
                        'customerLat': widget.currentPosition?.latitude ?? 0,
                        'customerLng': widget.currentPosition?.longitude ?? 0,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fuel Type Selector
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: _fuelTypes.keys.map((fuel) {
                bool isSelected = _selectedFuelType == fuel;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedFuelType = fuel;
                        _loadVehicles();
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.green : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.green : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _fuelTypes[fuel]?['icon'] ?? '⛽',
                            style: const TextStyle(fontSize: 16),
                          ),
                          Text(
                            fuel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.green : Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            'KES ${_fuelTypes[fuel]?['price'] ?? 0}',
                            style: TextStyle(
                              fontSize: 8,
                              color: isSelected ? Colors.green : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Vehicle List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 60,
                              color: Colors.orange.shade300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadVehicles,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              child: const Text('Refresh'),
                            ),
                          ],
                        ),
                      )
                    : _availableVehicles.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.local_gas_station,
                                  size: 60,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No vehicles available',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try selecting a different fuel type',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadVehicles,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                  ),
                                  child: const Text('Refresh'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _availableVehicles.length,
                            itemBuilder: (context, index) {
                              final vehicle = _availableVehicles[index];
                              final isSelected = _selectedVehicleId == vehicle['id'];
                              final distance = vehicle['distance'] ?? 0;
                              final price = vehicle['price'] ?? 0;
                              final fuelAvailable = vehicle['fuelAvailable'] ?? 0;
                              final vehicleIcon = vehicle['vehicleIcon'] ?? '🚚';
                              final photoUrl = vehicle['photoUrl'] ?? '';

                              return Card(
                                elevation: 2,
                                margin: const EdgeInsets.only(bottom: 12),
                                child: InkWell(
                                  onTap: () => _selectVehicle(vehicle),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? Colors.green : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // ============================================================
                                        // UPDATED: Show driver image instead of simple icon
                                        // ============================================================
                                        photoUrl.isNotEmpty
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: Image.network(
                                                  photoUrl,
                                                  width: 60,
                                                  height: 60,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Container(
                                                      width: 60,
                                                      height: 60,
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey.shade100,
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          vehicleIcon,
                                                          style: const TextStyle(fontSize: 32),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  loadingBuilder: (context, child, loadingProgress) {
                                                    if (loadingProgress == null) return child;
                                                    return Container(
                                                      width: 60,
                                                      height: 60,
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey.shade100,
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: const Center(
                                                        child: SizedBox(
                                                          width: 24,
                                                          height: 24,
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              )
                                            : Container(
                                                width: 60,
                                                height: 60,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    vehicleIcon,
                                                    style: const TextStyle(fontSize: 32),
                                                  ),
                                                ),
                                              ),
                                        const SizedBox(width: 12),

                                        // Vehicle Info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                vehicle['name'] ?? 'Vehicle',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green.shade100,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      vehicle['vehicleType']?.toUpperCase() ?? 'MEDIUM',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.green.shade700,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue.shade100,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      '${distance.toStringAsFixed(1)}km',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.blue.shade700,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.orange.shade100,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      '${fuelAvailable.toStringAsFixed(0)}L',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.orange.shade700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  const Icon(Icons.confirmation_number, size: 12, color: Colors.grey),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    vehicle['plateNumber'] ?? 'N/A',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey.shade600,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  const Icon(Icons.inventory_2, size: 12, color: Colors.grey),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    vehicle['capacity'] ?? '500L',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Price and action
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'KES ${price.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Text(
                                              '/L',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: const Text(
                                                'Select',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
