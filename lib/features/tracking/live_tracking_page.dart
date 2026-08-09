import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/services/tracking_service.dart';

class LiveTrackingPage extends StatefulWidget {
  final String driverId;
  const LiveTrackingPage({super.key, required this.driverId});

  @override
  State<LiveTrackingPage> createState() => _LiveTrackingPageState();
}

class _LiveTrackingPageState extends State<LiveTrackingPage> {
  GoogleMapController? _mapController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Tanker Tracking 🚚"),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              // Center map on driver
              _mapController?.animateCamera(
                CameraUpdate.newCameraPosition(
                  const CameraPosition(
                    target: LatLng(0, 0),
                    zoom: 14,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: TrackingService.trackDriver(widget.driverId),
        builder: (context, snapshot) {
          // Handle loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Loading driver location..."),
                ],
              ),
            );
          }

          // Handle errors
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  const Text("Failed to load tracking data"),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: TextStyle(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {});
                    },
                    child: const Text("Retry"),
                  ),
                ],
              ),
            );
          }

          // Handle no data
          if (!snapshot.hasData || snapshot.data!.data() == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("Waiting for driver location..."),
                  SizedBox(height: 8),
                  Text("Driver will appear here when online"),
                ],
              ),
            );
          }

          // Extract location data
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final lat = data['lat'] as double? ?? 0.0;
          final lng = data['lng'] as double? ?? 0.0;
          final isOnline = data['isOnline'] as bool? ?? false;
          final driverName = data['name'] as String? ?? 'Fuel Tanker';
          final lastUpdate = data['lastUpdate'] as dynamic;

          // Validate coordinates
          if (lat == 0.0 && lng == 0.0) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gps_off, size: 64, color: Colors.orange),
                  SizedBox(height: 16),
                  Text("Driver location not available"),
                  SizedBox(height: 8),
                  Text("Driver may be offline"),
                ],
              ),
            );
          }

          // Hide loading when map is ready
          if (_isLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() => _isLoading = false);
            });
          }

          return Stack(
            children: [
              // Google Map
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(lat, lng),
                  zoom: 14,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId("driver"),
                    position: LatLng(lat, lng),
                    infoWindow: InfoWindow(
                      title: driverName,
                      snippet: isOnline ? "🟢 Online" : "🔴 Offline",
                    ),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      isOnline ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
                    ),
                  ),
                },
                onMapCreated: (controller) {
                  _mapController = controller;
                  // Animate to driver position when map is created
                  controller.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: LatLng(lat, lng),
                        zoom: 14,
                      ),
                    ),
                  );
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: true,
                compassEnabled: true,
              ),
              
              // Driver info card at bottom
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? Colors.green : Colors.red,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              driverName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              isOnline ? "Online" : "Offline",
                              style: TextStyle(
                                color: isOnline ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              "Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}",
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        if (lastUpdate != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                "Last update: ${_formatTime(lastUpdate)}",
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              
              // Loading overlay while map loads
              if (_isLoading)
                Container(
                  color: Colors.white,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text("Loading map..."),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    if (timestamp is DateTime) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
    return timestamp.toString();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
