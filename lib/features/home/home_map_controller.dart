// ============================================================
// FILE: lib/features/home/home_map_controller.dart
// COMPLETE - FIXED WITH ARRIVAL LISTENER AND FIXED ONTIMEOUT
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';

const String googleAPIKey = 'AIzaSyATIUosv_VCeiVsQ3q6_LSQhZkrHr0E79o';

// ============================================================
// ENHANCED LANE INFO
// ============================================================
class LaneInfo {
  final bool left;
  final bool straight;
  final bool right;
  final bool recommended;
  final String label;

  LaneInfo({
    required this.left,
    required this.straight,
    required this.right,
    this.recommended = false,
    this.label = '',
  });

  String get displayChar {
    if (left && right) return '⟷';
    if (left) return '←';
    if (right) return '→';
    if (straight) return '↑';
    return '•';
  }

  Color get color => recommended ? Colors.blue : Colors.grey;
}

// ============================================================
// NAVIGATION STEP WITH HEADING
// ============================================================
class NavigationStep {
  final String instruction;
  final String maneuver;
  final double distance;
  final String distanceText;
  final Duration duration;
  final String durationText;
  final LatLng startLocation;
  final LatLng endLocation;
  final List<LatLng> points;
  final String roadName;
  final String roadShield;
  final List<LaneInfo> lanes;
  final double startHeading;
  final double endHeading;

  NavigationStep({
    required this.instruction,
    required this.maneuver,
    required this.distance,
    required this.distanceText,
    required this.duration,
    required this.durationText,
    required this.startLocation,
    required this.endLocation,
    required this.points,
    required this.roadName,
    required this.roadShield,
    required this.lanes,
    required this.startHeading,
    required this.endHeading,
  });
}

// ============================================================
// HOME MAP CONTROLLER 
// ============================================================
class HomeMapController extends ChangeNotifier {
  // ============================================================
  // GOOGLE API KEY
  // ============================================================
  static const String googleAPIKey = 'AIzaSyATIUosv_VCeiVsQ3q6_LSQhZkrHr0E79o';

  // ============================================================
  // MAP CONTROLLER & STATE
  // ============================================================
  GoogleMapController? mapController;
  Set<Marker> driverMarkers = {};
  Set<Polyline> polylines = {};
  Set<Polygon> polygons = {};
  Position? currentPosition;
  bool isLoading = true;
  bool isMapReady = false;
  Timer? refreshTimer;
  List<Map<String, dynamic>> nearbyDrivers = [];
  bool hasActiveOrder = false;
  String? activeOrderId;
  String? activeDriverId;
  Map<String, dynamic>? activeOrderDetails;
  Map<String, dynamic>? activeDriverLocation;
  double? distanceToDriver;
  int? estimatedMinutes;
  bool showVehicleSelector = true;
  double driverSpeedKmh = 40;
  String? driverPhotoUrl;
  bool isOrderAccepted = false;
  bool showFuelSelector = true;
  bool noDriversFound = false;
  bool isWaitingForDrivers = false;
  StreamSubscription<DocumentSnapshot>? orderStatusSubscription;
  StreamSubscription<DocumentSnapshot>? driverLocationSubscription;
  
  String? driverPhoneNumber;
  bool showDriverInfo = false;
  final Map<String, BitmapDescriptor> markerCache = {};
  final Map<String, Uint8List> fuelImageBytesCache = {};
  final Map<String, BitmapDescriptor> fuelImageCache = {};
  
  // ============================================================
  // NAVIGATION STATE GUARD
  // ============================================================
  bool _navigationInitialized = false;
  bool _hasAnnouncedStartingNavigation = false;
  bool _isInitializingNavigation = false;
  
  // ============================================================
  // ✅ ADDED: Arrival listener timer to stop route refreshing
  // ============================================================
  Timer? _arrivalCheckTimer;
  
  // ============================================================
  // GPS FILTERING
  // ============================================================
  LatLng? _filteredGpsPosition;
  double _gpsFilterAlpha = 0.3;
  double _minGpsFilterAlpha = 0.15;
  double _maxGpsFilterAlpha = 0.5;
  LatLng? _lastRawPosition;
  List<LatLng> _recentGpsPositions = [];
  static const int _maxGpsHistory = 5;
  double _currentGpsAccuracy = 10.0;
  Timer? _gpsAccuracyTimer;
  
  // ============================================================
  // ENVIRONMENT DETECTION
  // ============================================================
  bool _isUrbanEnvironment = true;
  double _averageBuildingDensity = 0.0;
  int _roadCount = 0;
  double _lastKnownLat = 0.0;
  double _lastKnownLng = 0.0;
  Timer? _environmentDetectionTimer;
  
  // ============================================================
  // ROAD SNAPPING
  // ============================================================
  LatLng? _snappedRoadPosition;
  Timer? _roadSnappingTimer;
  bool _isSnappingToRoad = false;
  double _roadSnapDistance = 30.0;
  double _minRoadSnapDistance = 15.0;
  double _maxRoadSnapDistance = 50.0;
  
  // ============================================================
  // DRIVER TRACKING
  // ============================================================
  LatLng? previousDriverPosition;
  double currentDriverBearing = 0;
  double filteredBearing = 0;
  Timer? driverMovementTimer;
  bool isDriverTurning = false;
  String turnDirection = 'straight';
  
  LatLng? interpolatedDriverPosition;
  Timer? interpolationTimer;
  double interpolationProgress = 1.0;
  LatLng? previousInterpolatedPosition;
  LatLng? targetInterpolatedPosition;
  DateTime? interpolationStartTime;
  static const Duration interpolationDuration = Duration(milliseconds: 400);
  
  LatLng? lastPredictedPosition;
  double predictedSpeed = 0;
  double predictedBearing = 0;
  DateTime? lastPredictionTime;
  LatLng? renderedPosition;
  
  // ============================================================
  // ENHANCED TURN DETECTION
  // ============================================================
  List<double> _turnAngleHistory = [];
  static const int _maxTurnHistory = 10;
  double _cumulativeTurnAngle = 0;
  bool _isInTurn = false;
  double _turnStartTime = 0;
  double _turnThreshold = 15.0;
  double _sharpTurnThreshold = 45.0;
  double _turnDurationThreshold = 5.0;
  
  // ============================================================
  // ROUTE STEP PROGRESS TRACKING
  // ============================================================
  double _stepProgress = 0.0;
  int _closestPointIndex = 0;
  List<double> _stepDistances = [];
  
  // ============================================================
  // CAMERA FOLLOWING
  // ============================================================
  Timer? cameraFollowTimer;
  bool isCameraFollowing = true;
  bool isMapRotating = true;
  LatLng? cameraTargetPosition;
  double cameraBearing = 0;
  double cameraZoom = 16.0;
  static const double baseZoom = 16.0;
  double minZoom = 14.0;
  double maxZoom = 18.0;
  
  double _smoothZoom = 16.0;
  double _zoomVelocity = 0.0;
  static const double zoomSmoothFactor = 0.15;
  static const double zoomSmoothDamping = 0.85;
  
  double _zoomAtSpeed = 16.0;
  double _zoomAtJunction = 16.0;
  double _zoomAtArrival = 16.0;
  bool _wasNearJunction = false;
  
  LatLng? lastKnownPosition;
  bool isDriverMoving = false;
  Timer? movementCheckTimer;
  static const double movementThreshold = 0.5;
  
  // ============================================================
  // MAP PADDING
  // ============================================================
  EdgeInsets mapPadding = const EdgeInsets.only(
    top: 40,
    bottom: 180,
    left: 10,
    right: 10,
  );
  static const double driverOffsetY = 0.7;
  double screenHeight = 0;
  double screenWidth = 0;

  // ============================================================
  // CAR SIZE
  // ============================================================
  double carMarkerWidth = 80.0;
  double carMarkerHeight = 120.0;

  // ============================================================
  // FUEL OPTIONS
  // ============================================================
  final List<Map<String, dynamic>> fuelOptions = [
    {'id': 'petrol', 'name': 'Petrol', 'image': 'assets/petrol.jpg', 'subtitle': 'Premium unleaded', 'color': Colors.green, 'fuelType': 'Petrol'},
    {'id': 'diesel', 'name': 'Diesel', 'image': 'assets/diesel.jpg', 'subtitle': 'For trucks', 'color': Colors.blue, 'fuelType': 'Diesel'},
    {'id': 'kerosene', 'name': 'Kerosene', 'image': 'assets/kerosin.jpg', 'subtitle': 'For cooking', 'color': Colors.orange, 'fuelType': 'Kerosene'},
    {'id': 'vpower', 'name': 'V-Power', 'image': 'assets/vpower.jpg', 'subtitle': 'Premium fuel', 'color': Colors.purple, 'fuelType': 'V-Power'},
  ];

  final Map<String, Map<String, dynamic>> fuelTypes = {
    'Petrol': {'price': 185.0, 'image': 'assets/petrol.jpg', 'color': Colors.green},
    'Diesel': {'price': 172.0, 'image': 'assets/diesel.jpg', 'color': Colors.blue},
    'Kerosene': {'price': 140.0, 'image': 'assets/kerosin.jpg', 'color': Colors.orange},
    'V-Power': {'price': 205.0, 'image': 'assets/vpower.jpg', 'color': Colors.purple},
  };

  String selectedFuelType = 'Petrol';
  double selectedLitres = 20;
  double maxAvailableLitres = 0;
  bool isLitresValid = true;
  String litresErrorMessage = '';
  bool showUseAvailableButton = false;
  bool isFuelSelectorExpanded = false;
  bool isAutoSelecting = false;
  Map<String, dynamic>? selectedDriver;
  bool showConfirmButton = false;
  bool hasUserSelectedFuel = false;
  bool hasUserAdjustedLitres = false;
  bool hasUserSelectedDriver = false;
  final Set<String> cancelledDriverIds = {};
  bool showCallDriverButton = false;

  // ============================================================
  // ROUTE & NAVIGATION
  // ============================================================
  List<LatLng> currentRoutePoints = [];
  LatLng? lastRouteOrigin;
  LatLng? lastRouteDestination;
  Timer? routeRecalculationTimer;
  bool isRecalculatingRoute = false;
  double routeRecalculationThreshold = 50.0;
  
  Duration? actualTravelDuration;
  Duration? normalTravelDuration;
  String? travelDurationText;
  bool useActualEta = false;

  // ============================================================
  // ENHANCED TURN-BY-TURN
  // ============================================================
  List<NavigationStep> routeSteps = [];
  int currentStepIndex = 0;
  bool isNavigating = false;
  String nextInstruction = '';
  String nextManeuver = '';
  double nextStepDistance = 0;
  Timer? turnAlertTimer;
  bool hasAnnouncedCurrentStep = false;
  bool hasAnnouncedPrepare = false;
  bool hasAnnouncedNow = false;
  
  double? currentRoadHeading;
  double? nextRoadHeading;
  double turnAngle = 0;
  List<double> headingHistory = [];
  static const int maxHeadingHistory = 5;

  // ============================================================
  // NAVIGATION BANNER
  // ============================================================
  bool showNavigationBanner = false;
  String bannerInstruction = '';
  String bannerManeuver = '';
  String bannerDistance = '';
  String bannerNextRoad = '';
  String bannerCurrentRoad = '';
  double bannerProgress = 0.0;
  String bannerSubInstruction = '';
  
  // ============================================================
  // JUNCTION VIEW
  // ============================================================
  bool isNearJunction = false;
  bool showJunctionOverlay = false;
  String junctionRoadName = '';
  String junctionManeuver = '';
  double junctionDistance = 0;
  List<LaneInfo> laneGuidance = [];
  String laneGuidanceText = '';

  // ============================================================
  // DRIVER STATUS
  // ============================================================
  double currentSpeed = 0.0;
  double currentHeading = 0.0;
  double previousHeading = 0.0;
  double headingSmooth = 0.0;
  String driverStatusText = 'En Route';
  String driverActionText = '';
  int stepsCompleted = 0;
  int totalSteps = 0;
  
  // ============================================================
  // DISTANCE & ETA
  // ============================================================
  double distanceToDestination = 0.0;
  String destinationDistanceText = '';
  int destinationEtaMinutes = 0;
  bool hasArrived = false;
  
  // ============================================================
  // SPEED LIMIT
  // ============================================================
  int speedLimit = 0;
  bool isSpeeding = false;
  Timer? speedCheckTimer;

  // ============================================================
  // TRAFFIC
  // ============================================================
  Timer? trafficRerouteTimer;
  bool isCheckingTraffic = false;
  Color currentTrafficColor = const Color(0xFF1A73E8);
  List<Map<String, dynamic>> trafficSegments = [];
  Map<String, dynamic>? currentTrafficData;

  // ============================================================
  // MARKERS
  // ============================================================
  List<Marker> navigationArrowMarkers = [];
  BitmapDescriptor? cachedArrowIcon;
  final Map<String, String> roadShields = {};

  // ============================================================
  // STREAMS
  // ============================================================
  StreamSubscription<QuerySnapshot>? driverStreamSubscription;
  final List<double> lastBearings = [];
  BuildContext? _context;

  // ============================================================
  // TTS (Text-to-Speech)
  // ============================================================
  FlutterTts? _tts;
  bool isVoiceEnabled = true;
  String lastSpokenInstruction = '';
  Timer? voiceDebounceTimer;
  Timer? voiceAnnouncementTimer;
  List<String> announcementQueue = [];

  // ============================================================
  // BACKGROUND LOCATION UPDATES
  // ============================================================
  Timer? _backgroundUpdateTimer;
  bool isBackgroundUpdatesRunning = false;
  static const Duration backgroundUpdateInterval = Duration(seconds: 10);
  bool _backgroundPermissionGranted = false;

  // ============================================================
  // DELIVERY PROGRESS TRACKING
  // ============================================================
  DateTime? orderAcceptedTime;
  DateTime? driverArrivalTime;
  bool hasDriverArrived = false;

  // ============================================================
  // ERROR HANDLING
  // ============================================================
  int _routeFetchRetryCount = 0;
  static const int _maxRouteFetchRetries = 3;
  bool _isRouteFetching = false;
  String _lastRouteError = '';
  Timer? _errorRetryTimer;
  bool _isOfflineMode = false;

  // ============================================================
  // PERFORMANCE OPTIMIZATION
  // ============================================================
  bool _isAppBackgrounded = false;
  Timer? _performanceTimer;
  static const int _interpolationIntervalMs = 16;
  static const int _movementUpdateIntervalMs = 50;
  
  // ============================================================
  // CONSTRUCTOR
  // ============================================================
  HomeMapController() {
    _init();
    _initTTS();
    _startRoadSnapping();
    _checkConnectivity();
    _startGpsAccuracyMonitoring();
    _startEnvironmentDetection();
    _setupPerformanceOptimization();
  }

  void setContext(BuildContext context) {
    _context = context;
  }

  // ============================================================
  // TTS Initialization
  // ============================================================
  void _initTTS() {
    _tts = FlutterTts();
    _tts?.setLanguage('en-US');
    _tts?.setSpeechRate(0.5);
    _tts?.setPitch(1.0);
    _tts?.setVolume(1.0);
  }

  void speak(String text) {
    if (!isVoiceEnabled) return;
    if (text == lastSpokenInstruction) return;
    
    if (voiceAnnouncementTimer != null && voiceAnnouncementTimer!.isActive) {
      announcementQueue.add(text);
      return;
    }
    
    _speakImmediately(text);
  }

  void _speakImmediately(String text) {
    voiceDebounceTimer?.cancel();
    voiceDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      lastSpokenInstruction = text;
      _tts?.speak(text);
      print('🔊 VOICE: $text');
    });
    
    voiceAnnouncementTimer?.cancel();
    voiceAnnouncementTimer = Timer(const Duration(seconds: 2), () {
      if (announcementQueue.isNotEmpty) {
        final nextText = announcementQueue.removeAt(0);
        _speakImmediately(nextText);
      }
    });
  }

  void setVoiceEnabled(bool enabled) {
    isVoiceEnabled = enabled;
    notifyListeners();
  }

  // ============================================================
  // GPS ACCURACY MONITORING
  // ============================================================
  void _startGpsAccuracyMonitoring() {
    _gpsAccuracyTimer?.cancel();
    _gpsAccuracyTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (currentPosition != null) {
        _currentGpsAccuracy = currentPosition!.accuracy;
        if (_currentGpsAccuracy < 5) {
          _gpsFilterAlpha = max(_gpsFilterAlpha * 0.8, _minGpsFilterAlpha);
        } else if (_currentGpsAccuracy > 20) {
          _gpsFilterAlpha = min(_gpsFilterAlpha * 1.3, _maxGpsFilterAlpha);
        }
      }
    });
  }

  // ============================================================
  // ENVIRONMENT DETECTION
  // ============================================================
  void _startEnvironmentDetection() {
    _environmentDetectionTimer?.cancel();
    _environmentDetectionTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _detectEnvironment();
    });
  }

  void _detectEnvironment() {
    if (renderedPosition == null) return;
    
    final lat = renderedPosition!.latitude;
    final lng = renderedPosition!.longitude;
    
    if (_lastKnownLat != 0 && _lastKnownLng != 0) {
      final distance = Geolocator.distanceBetween(
        _lastKnownLat, _lastKnownLng,
        lat, lng,
      );
      if (distance < 100) return;
    }
    
    _lastKnownLat = lat;
    _lastKnownLng = lng;
    
    if (currentSpeed < 30 && _turnAngleHistory.length > 5) {
      _isUrbanEnvironment = true;
      _roadSnapDistance = _minRoadSnapDistance;
    } else if (currentSpeed > 50 && _turnAngleHistory.length < 3) {
      _isUrbanEnvironment = false;
      _roadSnapDistance = _maxRoadSnapDistance;
    } else {
      _isUrbanEnvironment = currentSpeed < 40;
      _roadSnapDistance = (_minRoadSnapDistance + _maxRoadSnapDistance) / 2;
    }
  }

  // ============================================================
  // PERFORMANCE OPTIMIZATION
  // ============================================================
  void _setupPerformanceOptimization() {
    _performanceTimer?.cancel();
    _performanceTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isAppBackgrounded) {
        driverMovementTimer?.cancel();
        driverMovementTimer = Timer.periodic(
          const Duration(milliseconds: 200),
          (_) => _trackDriverMovement(),
        );
      } else {
        driverMovementTimer?.cancel();
        driverMovementTimer = Timer.periodic(
          const Duration(milliseconds: _movementUpdateIntervalMs),
          (_) => _trackDriverMovement(),
        );
      }
    });
  }

  void setAppBackgrounded(bool backgrounded) {
    _isAppBackgrounded = backgrounded;
    if (backgrounded) {
      interpolationTimer?.cancel();
    } else {
      if (interpolatedDriverPosition != null) {
        startInterpolation(interpolatedDriverPosition!);
      }
    }
    notifyListeners();
  }

  // ============================================================
  // Connectivity Check
  // ============================================================
  void _checkConnectivity() {
    Timer.periodic(const Duration(seconds: 30), (timer) {
      _testGoogleMapsAPI();
    });
  }

  // ============================================================
  // Background Location Permission
  // ============================================================
  Future<bool> requestBackgroundLocationPermission() async {
    try {
      bool isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        await Geolocator.openLocationSettings();
        return false;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (_context != null) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            const SnackBar(
              content: Text('Please enable location permissions in settings for tracking to work.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        _backgroundPermissionGranted = false;
        return false;
      }
      
      _backgroundPermissionGranted = true;
      return true;
    } catch (e) {
      print('Error requesting background permission: $e');
      _backgroundPermissionGranted = false;
      return false;
    }
  }

  // ============================================================
  // Background Location Updates
  // ============================================================
  void startBackgroundLocationUpdates() {
    if (isBackgroundUpdatesRunning) return;
    
    requestBackgroundLocationPermission().then((granted) {
      if (!granted) {
        print('⚠️ Background location permission denied');
        return;
      }
      
      isBackgroundUpdatesRunning = true;
      _backgroundUpdateTimer = Timer.periodic(backgroundUpdateInterval, (timer) {
        _sendCustomerLocationToFirestore();
      });
      print('📍 Background location updates started');
    });
  }

  void stopBackgroundLocationUpdates() {
    _backgroundUpdateTimer?.cancel();
    _backgroundUpdateTimer = null;
    isBackgroundUpdatesRunning = false;
    print('📍 Background location updates stopped');
  }

  Future<void> _sendCustomerLocationToFirestore() async {
    if (currentPosition == null) return;
    if (activeOrderId == null && !hasActiveOrder) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('customers')
          .doc(user.uid)
          .set({
            'lat': currentPosition!.latitude,
            'lng': currentPosition!.longitude,
            'lastUpdated': FieldValue.serverTimestamp(),
            'activeOrderId': activeOrderId,
            'hasActiveOrder': hasActiveOrder,
            'isTracking': true,
          }, SetOptions(merge: true));
      
      if (activeOrderId != null) {
        await FirebaseFirestore.instance
            .collection('orders')
            .doc(activeOrderId)
            .update({
              'customerLat': currentPosition!.latitude,
              'customerLng': currentPosition!.longitude,
              'customerLocationUpdated': FieldValue.serverTimestamp(),
            });
      }
    } catch (e) {
      print('Error sending customer location: $e');
    }
  }

  // ============================================================
  // Delivery Progress Tracking
  // ============================================================
  double getDeliveryProgress() {
    if (distanceToDriver == null) return 0.0;
    final totalDistance = distanceToDriver!;
    
    const double initialDistance = 10000.0;
    
    if (totalDistance >= initialDistance) return 0.0;
    if (totalDistance < 100) return 0.95;
    if (totalDistance < 500) return 0.75;
    if (totalDistance < 1000) return 0.50;
    if (totalDistance < 2000) return 0.25;
    if (totalDistance < 5000) return 0.10;
    return 0.0;
  }

  String getDeliveryStatus() {
    final progress = getDeliveryProgress();
    
    if (hasArrived) return '✅ Delivered!';
    if (progress >= 0.95) return '📍 Almost There!';
    if (progress >= 0.75) return '🚗 Very Close!';
    if (progress >= 0.50) return '🛣️ En Route';
    if (progress >= 0.25) return '🚚 On The Way';
    if (progress >= 0.10) return '⏳ Heading Your Way';
    return '⏳ Waiting for Driver';
  }

  Color getDeliveryStatusColor() {
    final progress = getDeliveryProgress();
    
    if (hasArrived) return Colors.green;
    if (progress >= 0.95) return Colors.green;
    if (progress >= 0.75) return Colors.blue;
    if (progress >= 0.50) return Colors.orange;
    if (progress >= 0.25) return Colors.orange.shade700;
    return Colors.red;
  }

  String getEstimatedArrivalTime() {
    if (estimatedMinutes == null) return 'Calculating...';
    if (estimatedMinutes! <= 2) return 'Arriving now';
    
    final arrival = DateTime.now().add(Duration(minutes: estimatedMinutes!));
    final period = arrival.hour >= 12 ? 'PM' : 'AM';
    final hour = arrival.hour > 12 ? arrival.hour - 12 : arrival.hour;
    return '${hour}:${arrival.minute.toString().padLeft(2, '0')} $period';
  }

  Color getETAColor() {
    if (estimatedMinutes == null) return Colors.green;
    if (estimatedMinutes! < 5) return Colors.green;
    if (estimatedMinutes! < 15) return Colors.orange;
    if (estimatedMinutes! < 30) return Colors.orange.shade700;
    return Colors.red;
  }

  String getTimeElapsedSinceOrder() {
    if (orderAcceptedTime == null) return 'Just now';
    
    final elapsed = DateTime.now().difference(orderAcceptedTime!);
    if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}s ago';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    return '${elapsed.inHours}h ${elapsed.inMinutes % 60}m ago';
  }

  // ============================================================
  // Price Calculations
  // ============================================================
  String getTotalPriceDisplay() {
    if (selectedDriver == null) return 'KES 0.00';
    final price = fuelTypes[selectedFuelType]!['price'] as double;
    final total = price * selectedLitres;
    return 'KES ${total.toStringAsFixed(2)}';
  }

  String getPriceBreakdown() {
    final price = fuelTypes[selectedFuelType]!['price'] as double;
    return '${selectedFuelType} @ KES ${price.toStringAsFixed(2)}/L × ${selectedLitres.toStringAsFixed(1)}L';
  }

  double getTotalPrice() {
    final price = fuelTypes[selectedFuelType]!['price'] as double;
    return price * selectedLitres;
  }

  String getFormattedPrice(double amount) {
    return 'KES ${amount.toStringAsFixed(2)}';
  }

  // ============================================================
  // Voice Announcements for Navigation - ENHANCED
  // ============================================================
  void announceTurn(String maneuver, double distance) {
    if (!isVoiceEnabled) return;
    
    final maneuverText = _getManeuverText(maneuver);
    String announcement;
    
    if (distance < 30) {
      announcement = '$maneuverText now!';
    } else if (distance < 50) {
      announcement = 'In 50 meters, $maneuverText';
    } else if (distance < 100) {
      announcement = 'In 100 meters, $maneuverText';
    } else if (distance < 200) {
      announcement = 'In 200 meters, $maneuverText';
    } else if (distance < 500) {
      announcement = 'In 500 meters, $maneuverText';
    } else if (distance < 1000) {
      announcement = 'In 1 kilometer, $maneuverText';
    } else {
      announcement = 'In ${_formatDistance(distance)}, $maneuverText';
    }
    
    speak(announcement);
  }

  String _getManeuverText(String maneuver) {
    switch (maneuver) {
      case 'turn-left': return 'turn left';
      case 'turn-right': return 'turn right';
      case 'turn-sharp-left': return 'make a sharp left turn';
      case 'turn-sharp-right': return 'make a sharp right turn';
      case 'turn-slight-left': return 'bear left';
      case 'turn-slight-right': return 'bear right';
      case 'straight': return 'continue straight';
      case 'continue': return 'continue';
      case 'merge': return 'merge';
      case 'fork-left': return 'stay left at the fork';
      case 'fork-right': return 'stay right at the fork';
      case 'roundabout': return 'enter the roundabout';
      default: return 'continue';
    }
  }

  // ============================================================
  // ENHANCED GPS FILTERING WITH DYNAMIC ALPHA
  // ============================================================
  LatLng _filterGpsSignal(LatLng rawPosition) {
    _lastRawPosition = rawPosition;
    _recentGpsPositions.add(rawPosition);
    if (_recentGpsPositions.length > _maxGpsHistory) {
      _recentGpsPositions.removeAt(0);
    }
    
    double dynamicAlpha = _gpsFilterAlpha;
    
    if (currentSpeed > 30) {
      dynamicAlpha = min(_gpsFilterAlpha * 1.5, _maxGpsFilterAlpha);
    } else if (currentSpeed < 10) {
      dynamicAlpha = max(_gpsFilterAlpha * 0.7, _minGpsFilterAlpha);
    }
    
    if (_currentGpsAccuracy < 5) {
      dynamicAlpha = max(dynamicAlpha * 0.8, _minGpsFilterAlpha);
    } else if (_currentGpsAccuracy > 20) {
      dynamicAlpha = min(dynamicAlpha * 1.3, _maxGpsFilterAlpha);
    }
    
    if (_filteredGpsPosition == null) {
      _filteredGpsPosition = rawPosition;
      return rawPosition;
    }
    
    final distance = Geolocator.distanceBetween(
      _filteredGpsPosition!.latitude,
      _filteredGpsPosition!.longitude,
      rawPosition.latitude,
      rawPosition.longitude,
    );
    
    if (distance < 3.0) {
      final smoothed = LatLng(
        _filteredGpsPosition!.latitude + (rawPosition.latitude - _filteredGpsPosition!.latitude) * 0.3,
        _filteredGpsPosition!.longitude + (rawPosition.longitude - _filteredGpsPosition!.longitude) * 0.3,
      );
      _filteredGpsPosition = smoothed;
      return smoothed;
    }
    
    if (_recentGpsPositions.length >= 3) {
      double avgLat = 0;
      double avgLng = 0;
      double totalWeight = 0;
      
      for (int i = 0; i < _recentGpsPositions.length; i++) {
        final weight = (i + 1).toDouble() / _recentGpsPositions.length;
        avgLat += _recentGpsPositions[i].latitude * weight;
        avgLng += _recentGpsPositions[i].longitude * weight;
        totalWeight += weight;
      }
      
      avgLat /= totalWeight;
      avgLng /= totalWeight;
      
      final smoothed = LatLng(
        _filteredGpsPosition!.latitude + (avgLat - _filteredGpsPosition!.latitude) * dynamicAlpha,
        _filteredGpsPosition!.longitude + (avgLng - _filteredGpsPosition!.longitude) * dynamicAlpha,
      );
      _filteredGpsPosition = smoothed;
      return smoothed;
    }
    
    final smoothed = LatLng(
      _filteredGpsPosition!.latitude + dynamicAlpha * (rawPosition.latitude - _filteredGpsPosition!.latitude),
      _filteredGpsPosition!.longitude + dynamicAlpha * (rawPosition.longitude - _filteredGpsPosition!.longitude),
    );
    _filteredGpsPosition = smoothed;
    return smoothed;
  }

  // ============================================================
  // ENHANCED ROAD SNAPPING
  // ============================================================
  void _startRoadSnapping() {
    _roadSnappingTimer?.cancel();
    _roadSnappingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (renderedPosition != null && currentSpeed > 5) {
        _snapToRoad(renderedPosition!);
      }
    });
  }

  Future<void> _snapToRoad(LatLng position) async {
    if (_isSnappingToRoad) return;
    _isSnappingToRoad = true;
    
    try {
      double snapDistance = _isUrbanEnvironment ? _minRoadSnapDistance : _maxRoadSnapDistance;
      
      final String path = '${position.latitude},${position.longitude}';
      final String url = 'https://roads.googleapis.com/v1/snapToRoads?path=$path&interpolate=true&key=$googleAPIKey';
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⚠️ Road snapping timeout');
          _isSnappingToRoad = false;
          return http.Response('', 408);
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['snappedPoints'] != null && data['snappedPoints'].isNotEmpty) {
          final snapped = data['snappedPoints'][0];
          final snappedLat = snapped['location']['latitude'] as double;
          final snappedLng = snapped['location']['longitude'] as double;
          final snappedPos = LatLng(snappedLat, snappedLng);
          
          final distance = Geolocator.distanceBetween(
            position.latitude, position.longitude,
            snappedLat, snappedLng,
          );
          
          if (distance < snapDistance) {
            _snappedRoadPosition = snappedPos;
            if (interpolatedDriverPosition != null) {
              final distToSnapped = Geolocator.distanceBetween(
                interpolatedDriverPosition!.latitude,
                interpolatedDriverPosition!.longitude,
                snappedLat, snappedLng,
              );
              if (distToSnapped < snapDistance) {
                renderedPosition = snappedPos;
                _updateDriverMarkerWithInterpolation();
              }
            }
          }
        }
      }
    } catch (e) {
      // Silent fail
    }
    _isSnappingToRoad = false;
  }

  // ============================================================
  // ENHANCED TURN DETECTION
  // ============================================================
  void _detectTurnEnhanced(double currentBearing) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    
    lastBearings.add(currentBearing);
    if (lastBearings.length > 5) lastBearings.removeAt(0);
    if (lastBearings.length < 3) return;
    
    double diff = (lastBearings.last - lastBearings.first).abs();
    if (diff > 180) diff = 360 - diff;
    
    _turnAngleHistory.add(diff);
    if (_turnAngleHistory.length > _maxTurnHistory) {
      _turnAngleHistory.removeAt(0);
    }
    
    _cumulativeTurnAngle = _turnAngleHistory.fold(0.0, (sum, angle) => sum + angle);
    
    if (diff > _turnThreshold && !_isInTurn) {
      _isInTurn = true;
      _turnStartTime = now;
      isDriverTurning = true;
    }
    
    if (_isInTurn) {
      final turnDuration = now - _turnStartTime;
      final bool angleDecreasing = diff < _turnThreshold * 0.5;
      final bool timeExceeded = turnDuration > _turnDurationThreshold;
      
      if (angleDecreasing || timeExceeded) {
        _isInTurn = false;
        isDriverTurning = false;
        
        if (_cumulativeTurnAngle > _sharpTurnThreshold * 2) {
          turnDirection = 'sharp';
        } else if (_cumulativeTurnAngle > _sharpTurnThreshold) {
          turnDirection = 'gentle';
        } else {
          turnDirection = 'straight';
        }
        
        _cumulativeTurnAngle = 0;
        _turnAngleHistory.clear();
        notifyListeners();
      }
    }
    
    if (isDriverTurning) {
      turnDirection = diff > _sharpTurnThreshold ? 'sharp' : 'gentle';
    }
    notifyListeners();
  }

  // ============================================================
  // ROUTE STEP PROGRESS TRACKING
  // ============================================================
  void _updateStepProgress(LatLng currentPosition) {
    if (currentStepIndex >= routeSteps.length) return;
    
    final step = routeSteps[currentStepIndex];
    final points = step.points;
    if (points.length < 2) return;
    
    double minDist = double.infinity;
    int closestIdx = 0;
    
    for (int i = 0; i < points.length; i++) {
      final dist = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        points[i].latitude,
        points[i].longitude,
      );
      if (dist < minDist) {
        minDist = dist;
        closestIdx = i;
      }
    }
    
    _closestPointIndex = closestIdx;
    
    final totalStepLength = _calculateTotalDistance(points);
    if (totalStepLength > 0) {
      double traveled = 0;
      for (int i = 0; i < closestIdx && i < points.length - 1; i++) {
        traveled += Geolocator.distanceBetween(
          points[i].latitude, points[i].longitude,
          points[i+1].latitude, points[i+1].longitude,
        );
      }
      _stepProgress = (traveled / totalStepLength).clamp(0.0, 1.0);
    }
    
    bannerProgress = (currentStepIndex + _stepProgress) / routeSteps.length;
    notifyListeners();
  }

  // ============================================================
  // ENHANCED ERROR HANDLING
  // ============================================================
  void _handleRouteFetchError(dynamic error, {bool retry = true}) {
    _lastRouteError = error.toString();
    print('⚠️ Route fetch error: $error');
    
    if (error.toString().contains('No route points found')) {
      _isOfflineMode = true;
    }
    
    if (retry && _routeFetchRetryCount < _maxRouteFetchRetries) {
      _routeFetchRetryCount++;
      _errorRetryTimer?.cancel();
      _errorRetryTimer = Timer(
        Duration(seconds: _routeFetchRetryCount * 2),
        () {
          print('🔄 Retrying route fetch (attempt $_routeFetchRetryCount)');
          if (renderedPosition != null && currentPosition != null) {
            drawDriverRoute(
              renderedPosition!.latitude,
              renderedPosition!.longitude,
            );
          }
        },
      );
    } else {
      _routeFetchRetryCount = 0;
      _showRouteErrorNotification();
    }
  }

  void _showRouteErrorNotification() {
    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Expanded(
                child: Text(
                  '⚠️ Navigation error: ${_lastRouteError.length > 40 ? _lastRouteError.substring(0, 40) + '...' : _lastRouteError}',
                ),
              ),
              TextButton(
                onPressed: () {
                  if (renderedPosition != null && currentPosition != null) {
                    drawDriverRoute(
                      renderedPosition!.latitude,
                      renderedPosition!.longitude,
                    );
                  }
                },
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ============================================================
  // INITIALIZATION - FIXED: Added missing _getCurrentLocation call
  // ============================================================
  void _init() {
    _getCurrentLocation();
    _checkActiveOrder();
    _listenToDriversRealtime();
    
    refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (isMapReady && !showFuelSelector) _loadNearbyDrivers();
      if (activeOrderId == null) _checkActiveOrder();
    });
    
    driverMovementTimer = Timer.periodic(
      const Duration(milliseconds: _movementUpdateIntervalMs),
      (_) => _trackDriverMovement(),
    );
    Timer.periodic(
      const Duration(milliseconds: _interpolationIntervalMs),
      (_) => _predictMovement(),
    );
    
    _testGoogleMapsAPI();
  }

  void dispose() {
    refreshTimer?.cancel();
    orderStatusSubscription?.cancel();
    driverLocationSubscription?.cancel();
    driverStreamSubscription?.cancel();
    driverMovementTimer?.cancel();
    interpolationTimer?.cancel();
    routeRecalculationTimer?.cancel();
    turnAlertTimer?.cancel();
    cameraFollowTimer?.cancel();
    movementCheckTimer?.cancel();
    trafficRerouteTimer?.cancel();
    speedCheckTimer?.cancel();
    _backgroundUpdateTimer?.cancel();
    voiceDebounceTimer?.cancel();
    voiceAnnouncementTimer?.cancel();
    _roadSnappingTimer?.cancel();
    _errorRetryTimer?.cancel();
    _gpsAccuracyTimer?.cancel();
    _environmentDetectionTimer?.cancel();
    _performanceTimer?.cancel();
    // ✅ Cancel arrival listener on dispose
    _arrivalCheckTimer?.cancel();
    _arrivalCheckTimer = null;
    mapController?.dispose();
    _tts?.stop();
  }

  // ============================================================
  // UPDATE MAP PADDING - 70% RULE (UBER STYLE)
  // ============================================================
  void _updateMapPadding() {
    if (_context != null) {
      final mediaQuery = MediaQuery.of(_context!);
      screenHeight = mediaQuery.size.height;
      screenWidth = mediaQuery.size.width;
    } else {
      screenHeight = 800;
      screenWidth = 400;
    }

    mapPadding = EdgeInsets.only(
      top: screenHeight * 0.08,
      bottom: screenHeight * 0.30,
      left: screenWidth * 0.02,
      right: screenWidth * 0.02,
    );
  }

  // ============================================================
  // ENHANCED CAMERA FOLLOWING WITH DYNAMIC ZOOM
  // ============================================================
  void startUberCameraFollowing() {
    cameraFollowTimer?.cancel();
    
    if (renderedPosition != null) {
      cameraTargetPosition = renderedPosition;
      cameraBearing = filteredBearing;
      cameraZoom = baseZoom;
      _smoothZoom = baseZoom;
    }
    
    movementCheckTimer?.cancel();
    movementCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _checkDriverMovement();
    });
    
    cameraFollowTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _updateUberCameraPosition();
    });
  }
  
  void _checkDriverMovement() {
    if (renderedPosition == null) return;
    
    if (lastKnownPosition == null) {
      lastKnownPosition = renderedPosition;
      isDriverMoving = false;
      return;
    }
    
    final distance = Geolocator.distanceBetween(
      lastKnownPosition!.latitude,
      lastKnownPosition!.longitude,
      renderedPosition!.latitude,
      renderedPosition!.longitude,
    );
    
    isDriverMoving = distance > movementThreshold;
    
    if (isDriverMoving) {
      lastKnownPosition = renderedPosition;
    }
  }
  
  // ============================================================
  // ENHANCED ZOOM CALCULATION - SMOOTH & DYNAMIC
  // ============================================================
  double _calculateUberZoom() {
    double targetZoom = baseZoom;
    
    // 1. Speed-based zoom
    if (currentSpeed < 5) {
      _zoomAtSpeed = 17.5;
    } else if (currentSpeed < 10) {
      _zoomAtSpeed = 17.0;
    } else if (currentSpeed < 20) {
      _zoomAtSpeed = 16.5;
    } else if (currentSpeed < 35) {
      _zoomAtSpeed = 16.0;
    } else if (currentSpeed < 50) {
      _zoomAtSpeed = 15.5;
    } else if (currentSpeed < 70) {
      _zoomAtSpeed = 15.0;
    } else {
      _zoomAtSpeed = 14.5;
    }
    
    // 2. Junction proximity zoom
    if (isNearJunction && junctionDistance < 100) {
      _zoomAtJunction = 18.0;
    } else if (isNearJunction && junctionDistance < 200) {
      _zoomAtJunction = 17.5;
    } else {
      _zoomAtJunction = _zoomAtSpeed;
    }
    
    // 3. Arrival zoom
    if (hasArrived || (distanceToDriver != null && distanceToDriver! < 100)) {
      _zoomAtArrival = 18.5;
    } else if (distanceToDriver != null && distanceToDriver! < 500) {
      _zoomAtArrival = 18.0;
    } else {
      _zoomAtArrival = _zoomAtJunction;
    }
    
    // 4. Combine zoom factors with priority
    if (hasArrived || (distanceToDriver != null && distanceToDriver! < 100)) {
      targetZoom = _zoomAtArrival;
    } else if (isNearJunction) {
      targetZoom = _zoomAtJunction;
    } else {
      targetZoom = _zoomAtSpeed;
    }
    
    // 5. Clamp to safe range
    targetZoom = targetZoom.clamp(minZoom, maxZoom);
    
    // 6. Smooth zoom transition using damping
    final zoomDiff = targetZoom - _smoothZoom;
    _zoomVelocity = _zoomVelocity * zoomSmoothDamping + zoomDiff * zoomSmoothFactor;
    _smoothZoom = _smoothZoom + _zoomVelocity;
    
    _smoothZoom = _smoothZoom.clamp(minZoom, maxZoom);
    
    return _smoothZoom;
  }
  
  void _updateUberCameraPosition() {
    if (!isCameraFollowing || mapController == null || renderedPosition == null) return;
    
    if (!isDriverMoving && cameraTargetPosition != null) {
      return;
    }
    
    final targetLat = renderedPosition!.latitude;
    final targetLng = renderedPosition!.longitude;
    
    if (cameraTargetPosition == null) {
      cameraTargetPosition = renderedPosition;
    }
    
    final deltaLat = targetLat - cameraTargetPosition!.latitude;
    final deltaLng = targetLng - cameraTargetPosition!.longitude;
    
    if (deltaLat.abs() > 0.00001 || deltaLng.abs() > 0.00001) {
      cameraTargetPosition = LatLng(
        cameraTargetPosition!.latitude + deltaLat * 0.3,
        cameraTargetPosition!.longitude + deltaLng * 0.3,
      );
    }
    
    double targetBearing = isMapRotating ? filteredBearing : 0;
    double bearingDiff = targetBearing - cameraBearing;
    if (bearingDiff > 180) bearingDiff -= 360;
    if (bearingDiff < -180) bearingDiff += 360;
    cameraBearing += bearingDiff * 0.2;
    
    double targetZoom = _calculateUberZoom();
    cameraZoom = targetZoom;
    
    _updateMapPadding();
    
    mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: cameraTargetPosition!,
          zoom: cameraZoom,
          bearing: cameraBearing,
          tilt: 65.0,
        ),
      ),
    );
  }

  // ============================================================
  // SMOOTH DRIVER MOVEMENT
  // ============================================================
  void _trackDriverMovement() {
    if (activeDriverLocation == null || previousDriverPosition == null) {
      if (activeDriverLocation != null) {
        previousDriverPosition = LatLng(
          activeDriverLocation!['lat'] ?? 0, 
          activeDriverLocation!['lng'] ?? 0
        );
      }
      return;
    }
    
    final currentLat = activeDriverLocation!['lat'] ?? 0;
    final currentLng = activeDriverLocation!['lng'] ?? 0;
    final currentPos = LatLng(currentLat, currentLng);
    
    final bearing = _calculateBearing(previousDriverPosition!, currentPos);
    final distance = Geolocator.distanceBetween(
      previousDriverPosition!.latitude, 
      previousDriverPosition!.longitude, 
      currentLat, 
      currentLng
    );
    
    if (distance > 1) {
      if (filteredBearing == 0) {
        filteredBearing = bearing;
      } else {
        filteredBearing = filteredBearing * 0.7 + bearing * 0.3;
      }
      currentDriverBearing = bearing;
      previousDriverPosition = currentPos;
      _detectTurnEnhanced(bearing);
      _updateDriverMarkerWithBearing();
    }
  }
  
  String _getTurnText() {
    switch (turnDirection) {
      case 'sharp': return '🔄 Making sharp turn';
      case 'gentle': return '↪️ Turning';
      default: return '⬆️ Moving straight';
    }
  }

  // ============================================================
  // SMOOTH INTERPOLATION
  // ============================================================
  void startInterpolation(LatLng newPosition) async {
    final filteredPosition = _filterGpsSignal(newPosition);
    final targetPosition = filteredPosition;
    
    if (interpolatedDriverPosition == null) {
      interpolatedDriverPosition = targetPosition;
      previousInterpolatedPosition = targetPosition;
      targetInterpolatedPosition = targetPosition;
      interpolationProgress = 1.0;
      renderedPosition = targetPosition;
      return;
    }
    
    final distance = Geolocator.distanceBetween(
      interpolatedDriverPosition!.latitude,
      interpolatedDriverPosition!.longitude,
      targetPosition.latitude,
      targetPosition.longitude,
    );
    
    if (distance < 0.5) {
      interpolatedDriverPosition = targetPosition;
      previousInterpolatedPosition = targetPosition;
      targetInterpolatedPosition = targetPosition;
      interpolationProgress = 1.0;
      renderedPosition = targetPosition;
      return;
    }
    
    previousInterpolatedPosition = interpolatedDriverPosition;
    targetInterpolatedPosition = targetPosition;
    interpolationProgress = 0.0;
    interpolationStartTime = DateTime.now();
    
    interpolationTimer?.cancel();
    
    final controlPoint1 = LatLng(
      previousInterpolatedPosition!.latitude + (targetInterpolatedPosition!.latitude - previousInterpolatedPosition!.latitude) * 0.25,
      previousInterpolatedPosition!.longitude + (targetInterpolatedPosition!.longitude - previousInterpolatedPosition!.longitude) * 0.25,
    );
    final controlPoint2 = LatLng(
      previousInterpolatedPosition!.latitude + (targetInterpolatedPosition!.latitude - previousInterpolatedPosition!.latitude) * 0.75,
      previousInterpolatedPosition!.longitude + (targetInterpolatedPosition!.longitude - previousInterpolatedPosition!.longitude) * 0.75,
    );
    
    interpolationTimer = Timer.periodic(
      const Duration(milliseconds: _interpolationIntervalMs),
      (timer) {
        if (interpolationStartTime == null || previousInterpolatedPosition == null || targetInterpolatedPosition == null) {
          timer.cancel();
          return;
        }
        
        final elapsed = DateTime.now().difference(interpolationStartTime!);
        final progress = (elapsed.inMilliseconds / interpolationDuration.inMilliseconds).clamp(0.0, 1.0);
        
        final easedProgress = progress < 0.5 
            ? 4 * progress * progress * progress 
            : 1 - pow(-2 * progress + 2, 3) / 2;
        
        interpolationProgress = easedProgress;
        
        final t = easedProgress;
        final mt = 1 - t;
        final lat = mt * mt * mt * previousInterpolatedPosition!.latitude +
                      3 * mt * mt * t * controlPoint1.latitude +
                      3 * mt * t * t * controlPoint2.latitude +
                      t * t * t * targetInterpolatedPosition!.latitude;
        final lng = mt * mt * mt * previousInterpolatedPosition!.longitude +
                      3 * mt * mt * t * controlPoint1.longitude +
                      3 * mt * t * t * controlPoint2.longitude +
                      t * t * t * targetInterpolatedPosition!.longitude;
        
        interpolatedDriverPosition = LatLng(lat, lng);
        renderedPosition = interpolatedDriverPosition;
        
        if (currentRoutePoints.isNotEmpty) {
          _updateStepProgress(renderedPosition!);
        }
        
        _updateDriverMarkerWithInterpolation();
        
        if (progress >= 1.0) {
          timer.cancel();
          interpolatedDriverPosition = targetInterpolatedPosition;
          interpolationProgress = 1.0;
          renderedPosition = targetInterpolatedPosition;
          _updateStepProgress(renderedPosition!);
          _updateDriverMarkerWithInterpolation();
        }
      },
    );
  }

  // ============================================================
  // PREDICTIVE MOVEMENT
  // ============================================================
  void _predictMovement() {
    if (interpolatedDriverPosition == null) return;
    
    final now = DateTime.now();
    if (lastPredictionTime == null) {
      lastPredictionTime = now;
      lastPredictedPosition = interpolatedDriverPosition;
      renderedPosition = interpolatedDriverPosition;
      return;
    }
    
    final elapsed = now.difference(lastPredictionTime!).inMilliseconds / 1000.0;
    if (elapsed < 0.1) {
      renderedPosition = lastPredictedPosition ?? interpolatedDriverPosition;
      return;
    }
    
    final speedMps = currentSpeed / 3.6;
    final distance = speedMps * elapsed;
    
    final bearingRad = filteredBearing * pi / 180;
    
    if (speedMps > 0.5 && filteredBearing != 0) {
      final latOffset = (distance * cos(bearingRad)) / 111000;
      final lngOffset = (distance * sin(bearingRad)) / (111000 * cos(interpolatedDriverPosition!.latitude * pi / 180));
      
      final predictedLat = interpolatedDriverPosition!.latitude + latOffset;
      final predictedLng = interpolatedDriverPosition!.longitude + lngOffset;
      
      lastPredictedPosition = LatLng(predictedLat, predictedLng);
      renderedPosition = lastPredictedPosition;
    } else {
      renderedPosition = interpolatedDriverPosition;
      lastPredictedPosition = interpolatedDriverPosition;
    }
    
    lastPredictionTime = now;
  }

  // ============================================================
  // VEHICLE MARKER
  // ============================================================
  Future<BitmapDescriptor> getVehicleMarker(String vehicleType, {double bearing = 0}) async {
    final int width = carMarkerWidth.toInt();
    final int height = carMarkerHeight.toInt();
    
    if (bearing != 0) {
      final String key = 'car_${vehicleType}_${bearing.round()}_${width}_${height}';
      if (markerCache.containsKey(key)) return markerCache[key]!;
      
      try {
        final ByteData? data = await rootBundle.load('assets/car3.png');
        if (data == null) return await _createEmojiFallback(vehicleType);
        
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        final originalImage = frame.image;
        
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        
        canvas.drawImageRect(
          originalImage,
          Rect.fromLTWH(0, 0, originalImage.width.toDouble(), originalImage.height.toDouble()),
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint(),
        );
        
        final stretchedImage = await recorder.endRecording().toImage(width, height);
        
        final rotateRecorder = ui.PictureRecorder();
        final rotateCanvas = Canvas(rotateRecorder);
        
        rotateCanvas.save();
        rotateCanvas.translate(width / 2, height / 2);
        rotateCanvas.rotate(bearing * pi / 180);
        rotateCanvas.translate(-width / 2, -height / 2);
        rotateCanvas.drawImage(stretchedImage, Offset(0, 0), Paint());
        rotateCanvas.restore();
        
        final rotated = await rotateRecorder.endRecording().toImage(width, height);
        final ByteData? rotatedData = await rotated.toByteData(format: ui.ImageByteFormat.png);
        if (rotatedData == null) return await _createEmojiFallback(vehicleType);
        
        final marker = BitmapDescriptor.fromBytes(rotatedData.buffer.asUint8List());
        markerCache[key] = marker;
        return marker;
      } catch (e) {
        return await _createEmojiFallback(vehicleType);
      }
    }
    
    const String defaultKey = 'default_car_60_60';
    if (markerCache.containsKey(defaultKey)) return markerCache[defaultKey]!;
    
    try {
      final ByteData? data = await rootBundle.load('assets/car3.png');
      if (data == null) return await _createEmojiFallback(vehicleType);
      
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: width,
        targetHeight: height,
      );
      final frame = await codec.getNextFrame();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(frame.image, Offset(0, 0), Paint());
      final image = await recorder.endRecording().toImage(width, height);
      final ByteData? imageData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (imageData == null) return await _createEmojiFallback(vehicleType);
      
      final marker = BitmapDescriptor.fromBytes(imageData.buffer.asUint8List());
      markerCache[defaultKey] = marker;
      return marker;
    } catch (e) {
      return await _createEmojiFallback(vehicleType);
    }
  }

  Future<BitmapDescriptor> _createEmojiFallback(String vehicleType) async {
    final String key = 'emoji_$vehicleType';
    if (markerCache.containsKey(key)) return markerCache[key]!;
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    Color color;
    switch (vehicleType.toLowerCase()) {
      case 'small': color = Colors.orange; break;
      case 'medium': color = Colors.blue; break;
      case 'big': color = Colors.green; break;
      default: color = Colors.green;
    }
    canvas.drawCircle(const Offset(30, 30), 28, Paint()..color = color);
    canvas.drawCircle(const Offset(30, 30), 28, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
    
    final emoji = _getVehicleIcon(vehicleType);
    final painter = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: 30, color: Colors.white, fontWeight: FontWeight.bold)), 
      textDirection: TextDirection.ltr
    );
    painter.layout();
    painter.paint(canvas, Offset(30 - painter.width / 2, 30 - painter.height / 2));
    
    final img = await recorder.endRecording().toImage(60, 60);
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    final marker = BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
    markerCache[key] = marker;
    return marker;
  }

  String _getVehicleIcon(String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case 'small': return '🚗';
      case 'medium': return '🚚';
      case 'big': return '🚛';
      default: return '🚚';
    }
  }

  // ============================================================
  // UPDATE DRIVER MARKER WITH ROTATION
  // ============================================================
  void _updateDriverMarkerWithInterpolation() {
    if (activeDriverId == null || activeDriverLocation == null || renderedPosition == null) return;
    
    final lat = renderedPosition!.latitude;
    final lng = renderedPosition!.longitude;
    
    driverMarkers.removeWhere((marker) => marker.markerId.value == activeDriverId);
    
    final displayBearing = filteredBearing;
    
    getVehicleMarker(activeDriverLocation!['vehicleType'] ?? 'medium', bearing: displayBearing).then((marker) {
      driverMarkers.add(Marker(
        markerId: MarkerId(activeDriverId!),
        position: LatLng(lat, lng),
        icon: marker,
        rotation: displayBearing,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        infoWindow: InfoWindow(
          title: '⛽ Fuel Truck En Route',
          snippet: '${isDriverTurning ? _getTurnText() : 'Moving straight'} • ${(distanceToDriver ?? 0) ~/ 1000}km away • ${currentSpeed.toStringAsFixed(0)} km/h',
        ),
      ));
      notifyListeners();
    });
  }

  void _updateDriverMarkerWithBearing() {
    if (activeDriverId == null || activeDriverLocation == null) return;
    
    final pos = renderedPosition ?? LatLng(
      activeDriverLocation!['lat'] ?? 0,
      activeDriverLocation!['lng'] ?? 0,
    );
    
    driverMarkers.removeWhere((marker) => marker.markerId.value == activeDriverId);
    
    final displayBearing = filteredBearing;
    
    getVehicleMarker(activeDriverLocation!['vehicleType'] ?? 'medium', bearing: displayBearing).then((marker) {
      driverMarkers.add(Marker(
        markerId: MarkerId(activeDriverId!),
        position: pos,
        icon: marker,
        rotation: displayBearing,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        infoWindow: InfoWindow(
          title: '⛽ Fuel Truck En Route',
          snippet: '${isDriverTurning ? _getTurnText() : 'Moving straight'} • ${(distanceToDriver ?? 0) ~/ 1000}km away • ${currentSpeed.toStringAsFixed(0)} km/h',
        ),
      ));
      notifyListeners();
    });
  }

  // ============================================================
  // DRIVER LOCATION LISTENING
  // ============================================================
  void _listenToDriverLocation() {
    driverLocationSubscription?.cancel();
    
    if (activeDriverId == null || currentPosition == null || !isOrderAccepted) {
      print('⛔ Waiting for driver to confirm order...');
      return;
    }

    print('📍 Driver confirmed! Starting Uber-style tracking...');
    
    startBackgroundLocationUpdates();
    
    driverLocationSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(activeDriverId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) {
            print('⚠️ Driver document does not exist: $activeDriverId');
            return;
          }
          
          final data = snapshot.data() as Map<String, dynamic>;
          double lat = (data['lat'] ?? 0).toDouble();
          double lng = (data['lng'] ?? 0).toDouble();
          
          if (lat == 0 && lng == 0) {
            print('⚠️ Driver position is 0,0 - waiting for valid location');
            return;
          }

          final newPosition = LatLng(lat, lng);
          
          startInterpolation(newPosition);
          
          final speed = (data['speed'] ?? 0.0).toDouble();
          currentSpeed = speed;
          
          activeDriverLocation = {
            'lat': lat, 
            'lng': lng, 
            'name': data['name'] ?? 'Driver',
            'vehicleType': data['vehicleType'] ?? 'medium',
            'numberPlate': data['numberPlate'] ?? 'N/A',
            'photoUrl': data['photoUrl'] ?? '', 
            'phone': data['phone'] ?? 'N/A',
          };
          driverPhotoUrl = data['photoUrl'] ?? '';
          driverPhoneNumber = data['phone'] ?? 'N/A';
          notifyListeners();

          if (previousDriverPosition != null) {
            final bearing = _calculateBearing(previousDriverPosition!, newPosition);
            final distance = Geolocator.distanceBetween(
              previousDriverPosition!.latitude, 
              previousDriverPosition!.longitude, 
              lat, 
              lng
            );
            if (distance > 1) {
              if (filteredBearing == 0) {
                filteredBearing = bearing;
              } else {
                filteredBearing = filteredBearing * 0.7 + bearing * 0.3;
              }
              currentDriverBearing = bearing;
              _detectTurnEnhanced(bearing);
            }
          }
          previousDriverPosition = newPosition;

          if (currentPosition != null) {
            double distanceInMeters = Geolocator.distanceBetween(
              currentPosition!.latitude, 
              currentPosition!.longitude, 
              lat, 
              lng
            );
            
            _recalculateRouteIfNeeded(newPosition);
            
            distanceToDriver = distanceInMeters;
            distanceToDestination = distanceInMeters;
            
            if (!useActualEta) {
              double speedFactor = distanceInMeters < 500 ? 0.8 : 
                                   distanceInMeters < 2000 ? 1.0 : 
                                   distanceInMeters < 5000 ? 1.2 : 1.5;
              double minutes = (distanceInMeters / 1000) / (driverSpeedKmh * speedFactor) * 60;
              estimatedMinutes = minutes.ceil().clamp(1, 60);
              destinationEtaMinutes = estimatedMinutes!;
              destinationDistanceText = _formatDistance(distanceInMeters);
            }
            
            if (distanceInMeters < 200) {
              driverStatusText = '📍 Almost There!';
              if (!hasDriverArrived) {
                hasDriverArrived = true;
                driverArrivalTime = DateTime.now();
                speak('Your driver is almost there!');
              }
            } else if (distanceInMeters < 500) {
              driverStatusText = '🚗 Very Close!';
              hasDriverArrived = false;
            } else if (distanceInMeters < 1000) {
              driverStatusText = '🛣️ Getting Close';
              hasDriverArrived = false;
            } else {
              driverStatusText = '🚚 En Route';
              hasDriverArrived = false;
            }
            notifyListeners();
            
            if (currentRoutePoints.isEmpty || lastRouteDestination == null || 
                lastRouteDestination!.latitude != currentPosition!.latitude ||
                lastRouteDestination!.longitude != currentPosition!.longitude) {
              print('📍 Drawing driver route...');
              drawDriverRoute(lat, lng);
            }
          }
        }, onError: (error) => print('⚠️ Driver location listener error: $error'));
  }

  // ============================================================
  // DRAW ROUTE WITH POLYLINE - ENHANCED WITH ARRIVAL CHECK
  // ============================================================
  Future<void> drawDriverRoute(double driverLat, double driverLng) async {
    if (currentPosition == null) return;
    if (_isRouteFetching) {
      print('⚠️ Route fetch already in progress, skipping...');
      return;
    }

    // ✅ If arrived, don't draw new route
    if (hasArrived) {
      print('✅ Already arrived - skipping route draw');
      return;
    }

    _isRouteFetching = true;
    _routeFetchRetryCount = 0;

    try {
      final origin = LatLng(driverLat, driverLng);
      final destination = LatLng(currentPosition!.latitude, currentPosition!.longitude);

      final result = await getRouteWithDetails(origin, destination);
      final routePoints = result['points'] as List<LatLng>;
      final duration = result['duration'] as Duration?;
      final normalDuration = result['normalDuration'] as Duration?;
      final durationText = result['durationText'] as String?;
      final steps = result['steps'] as List<NavigationStep>;

      if (routePoints.isEmpty) {
        _handleRouteFetchError('No route points found', retry: true);
        _isRouteFetching = false;
        return;
      }

      currentRoutePoints = routePoints;
      lastRouteOrigin = origin;
      lastRouteDestination = destination;
      actualTravelDuration = duration;
      normalTravelDuration = normalDuration;
      travelDurationText = durationText;
      useActualEta = duration != null;
      
      if (currentRoutePoints.isNotEmpty) {
        polylines = _buildPolylines(currentRoutePoints);
      } else {
        polylines = _buildPolylines([origin, destination]);
      }
      
      if (duration != null) {
        estimatedMinutes = duration.inMinutes > 0 ? duration.inMinutes : 1;
        destinationEtaMinutes = duration.inMinutes;
        destinationDistanceText = _formatDistance(_calculateTotalDistance(currentRoutePoints));
      } else {
        if (distanceToDriver != null) {
          double distanceKm = distanceToDriver! / 1000;
          double speed = distanceKm < 1 ? 20 : distanceKm < 3 ? 25 : distanceKm < 5 ? 30 : distanceKm < 10 ? 35 : 40;
          estimatedMinutes = (distanceKm / speed * 60).ceil().clamp(1, 60);
        }
      }
      notifyListeners();

      if (steps.isNotEmpty) {
        routeSteps = steps;
        initializeTurnByTurnNavigation();
        startTrafficMonitoring();
        startSpeedMonitoring();
      }

      _updateMapPadding();
      startUberCameraFollowing();
      _isRouteFetching = false;
      
      // ✅ Start arrival listener after route is drawn
      _startArrivalListener();
      
    } catch (e) {
      _handleRouteFetchError(e);
      _isRouteFetching = false;
    }
  }

  // ============================================================
  // ✅ ADDED: Arrival Listener to stop route refresh
  // ============================================================
  void _startArrivalListener() {
    // Cancel any existing timer
    _arrivalCheckTimer?.cancel();
    
    // Start periodic check for arrival
    _arrivalCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      // If already arrived, stop checking
      if (hasArrived) {
        timer.cancel();
        _arrivalCheckTimer = null;
        print('✅ Arrival detected - stopping route refresh listener');
        return;
      }
      
      // Check if driver has arrived at destination
      if (currentPosition != null && activeDriverLocation != null) {
        final driverLat = activeDriverLocation!['lat'] ?? 0;
        final driverLng = activeDriverLocation!['lng'] ?? 0;
        final distance = Geolocator.distanceBetween(
          currentPosition!.latitude,
          currentPosition!.longitude,
          driverLat,
          driverLng,
        );
        
        // If within 100 meters, consider arrived
        if (distance < 100) {
          print('📍 Driver is within 100m of destination - triggering arrival');
          // Cancel the timer immediately
          timer.cancel();
          _arrivalCheckTimer = null;
          // Mark as arrived to stop all route refreshes
          hasArrived = true;
          // Stop all route recalculation
          routeRecalculationTimer?.cancel();
          routeRecalculationTimer = null;
          isRecalculatingRoute = false;
          // Update UI
          notifyListeners();
          print('✅ Route refresh stopped - destination reached');
        }
      }
    });
  }

  // ============================================================
  // POLYLINES BUILDING
  // ============================================================
  Set<Polyline> _buildPolylines(List<LatLng> points) {
    final polylines = <Polyline>{};
    
    polylines.add(
      Polyline(
        polylineId: const PolylineId('driver_route_shadow'),
        points: points,
        color: Colors.black.withOpacity(0.3),
        width: 24,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    );
    
    polylines.add(
      Polyline(
        polylineId: const PolylineId('driver_route'),
        points: points,
        color: currentTrafficColor,
        width: 16,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    );
    
    polylines.add(
      Polyline(
        polylineId: const PolylineId('driver_route_border'),
        points: points,
        color: Colors.white.withOpacity(0.3),
        width: 20,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    );
    
    return polylines;
  }

  // ============================================================
  // GOOGLE DIRECTIONS API - FIXED: onTimeout returns proper Response
  // ============================================================
  Future<Map<String, dynamic>> getRouteWithDetails(LatLng origin, LatLng destination) async {
    try {
      final String url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&key=$googleAPIKey'
          '&departure_time=now'
          '&traffic_model=best_guess';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('⏰ Route request timeout');
          return http.Response('{"status":"TIMEOUT"}', 408);
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK') {
          final route = data['routes'][0];
          final overviewPolyline = route['overview_polyline']['points'];
          final points = _decodePolyline(overviewPolyline);
          
          Duration? travelDuration;
          Duration? normalDuration;
          String? durationText;
          List<NavigationStep> steps = [];
          
          if (route['legs'] != null && route['legs'].isNotEmpty) {
            final leg = route['legs'][0];
            
            if (leg['duration'] != null) {
              final seconds = leg['duration']['value'] as int;
              normalDuration = Duration(seconds: seconds);
            }
            
            if (leg['duration_in_traffic'] != null) {
              final seconds = leg['duration_in_traffic']['value'] as int;
              travelDuration = Duration(seconds: seconds);
              durationText = leg['duration_in_traffic']['text'] as String?;
            } else if (leg['duration'] != null) {
              final seconds = leg['duration']['value'] as int;
              travelDuration = Duration(seconds: seconds);
              durationText = leg['duration']['text'] as String?;
            }
            
            if (leg['steps'] != null) {
              for (int i = 0; i < leg['steps'].length; i++) {
                final step = leg['steps'][i];
                final stepPoints = _decodePolyline(step['polyline']['points']);
                final instruction = step['html_instructions'] ?? step['instructions'] ?? 'Continue';
                
                String roadName = '';
                final matches = RegExp(r'onto\s+([^<]+)').firstMatch(instruction);
                if (matches != null && matches.group(1) != null) {
                  roadName = matches.group(1)!.trim();
                } else {
                  final parts = instruction.split(' ');
                  if (parts.length > 2) {
                    roadName = parts.sublist(2).join(' ').replaceAll('<b>', '').replaceAll('</b>', '');
                  }
                }
                
                String roadShield = '';
                final shieldMatches = RegExp(r'([A-Z]\d{1,4})').firstMatch(roadName);
                if (shieldMatches != null) {
                  roadShield = shieldMatches.group(1)!;
                }
                
                String maneuver = step['maneuver'] ?? 'straight';
                
                double startHeading = 0;
                double endHeading = 0;
                if (stepPoints.length >= 2) {
                  startHeading = _calculateBearing(stepPoints[0], stepPoints[min(1, stepPoints.length - 1)]);
                  endHeading = _calculateBearing(
                    stepPoints[max(0, stepPoints.length - 2)], 
                    stepPoints.last
                  );
                }
                
                if (i < leg['steps'].length - 1) {
                  final nextStep = leg['steps'][i + 1];
                  final nextStepPoints = _decodePolyline(nextStep['polyline']['points']);
                  double nextStartHeading = 0;
                  if (nextStepPoints.length >= 2) {
                    nextStartHeading = _calculateBearing(nextStepPoints[0], nextStepPoints[min(1, nextStepPoints.length - 1)]);
                  }
                  
                  double turnAngle = (nextStartHeading - endHeading).abs() % 360;
                  if (turnAngle > 180) turnAngle = 360 - turnAngle;
                  
                  if (turnAngle > 30 && turnAngle < 80) {
                    final cross = _crossProduct(
                      stepPoints.last, 
                      stepPoints[max(0, stepPoints.length - 2)],
                      nextStepPoints[min(1, nextStepPoints.length - 1)]
                    );
                    maneuver = cross > 0 ? 'turn-left' : 'turn-right';
                  } else if (turnAngle >= 80) {
                    final cross = _crossProduct(
                      stepPoints.last, 
                      stepPoints[max(0, stepPoints.length - 2)],
                      nextStepPoints[min(1, nextStepPoints.length - 1)]
                    );
                    maneuver = cross > 0 ? 'turn-sharp-left' : 'turn-sharp-right';
                  } else if (turnAngle > 5 && turnAngle <= 30) {
                    final cross = _crossProduct(
                      stepPoints.last, 
                      stepPoints[max(0, stepPoints.length - 2)],
                      nextStepPoints[min(1, nextStepPoints.length - 1)]
                    );
                    maneuver = cross > 0 ? 'turn-slight-left' : 'turn-slight-right';
                  }
                }
                
                if (instruction.toLowerCase().contains('turn left') || instruction.toLowerCase().contains('turn-left')) {
                  maneuver = 'turn-left';
                } else if (instruction.toLowerCase().contains('turn right') || instruction.toLowerCase().contains('turn-right')) {
                  maneuver = 'turn-right';
                }
                
                List<LaneInfo> lanes = _getLaneInfo(maneuver);
                
                steps.add(NavigationStep(
                  instruction: instruction.replaceAll(RegExp(r'<[^>]*>'), ''),
                  maneuver: maneuver,
                  distance: (step['distance']['value'] as int).toDouble(),
                  distanceText: step['distance']['text'] ?? '',
                  duration: Duration(seconds: step['duration']['value'] as int),
                  durationText: step['duration']['text'] ?? '',
                  startLocation: LatLng(
                    step['start_location']['lat'] as double,
                    step['start_location']['lng'] as double,
                  ),
                  endLocation: LatLng(
                    step['end_location']['lat'] as double,
                    step['end_location']['lng'] as double,
                  ),
                  points: stepPoints,
                  roadName: roadName,
                  roadShield: roadShield,
                  lanes: lanes,
                  startHeading: startHeading,
                  endHeading: endHeading,
                ));
              }
            }
          }
          
          return {
            'points': points,
            'duration': travelDuration,
            'normalDuration': normalDuration,
            'durationText': durationText,
            'steps': steps,
          };
        } else if (data['status'] == 'OVER_QUERY_LIMIT') {
          print('⚠️ Google Maps API query limit exceeded');
          _handleRouteFetchError('API query limit exceeded', retry: false);
        } else if (data['status'] == 'REQUEST_DENIED') {
          print('⚠️ Google Maps API request denied - check API key');
          _handleRouteFetchError('API request denied', retry: false);
        }
      }
    } catch (e) {
      print('Error fetching route: $e');
      _handleRouteFetchError(e);
    }
    return {
      'points': [],
      'duration': null,
      'normalDuration': null,
      'durationText': null,
      'steps': [],
    };
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================
  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final dLng = (to.longitude - from.longitude) * pi / 180;
    
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _crossProduct(LatLng a, LatLng b, LatLng c) {
    final v1x = b.latitude - a.latitude;
    final v1y = b.longitude - a.longitude;
    final v2x = c.latitude - b.latitude;
    final v2y = c.longitude - b.longitude;
    return v1x * v2y - v1y * v2x;
  }

  List<LaneInfo> _getLaneInfo(String maneuver) {
    switch (maneuver) {
      case 'turn-left':
        return [
          LaneInfo(left: true, straight: false, right: false, recommended: true, label: '←'),
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
        ];
      case 'turn-right':
        return [
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
          LaneInfo(left: false, straight: false, right: true, recommended: true, label: '→'),
        ];
      default:
        return [
          LaneInfo(left: false, straight: true, right: false, recommended: true, label: '↑'),
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
        ];
    }
  }

  double _calculateTotalDistance(List<LatLng> points) {
    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += Geolocator.distanceBetween(
        points[i-1].latitude, points[i-1].longitude,
        points[i].latitude, points[i].longitude,
      );
    }
    return total;
  }

  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  // ============================================================
  // TURN-BY-TURN NAVIGATION WITH INITIALIZATION GUARD
  // ============================================================
  void initializeTurnByTurnNavigation() {
    if (_navigationInitialized && isNavigating) {
      print('⚠️ Navigation already initialized, skipping duplicate init');
      _updateCurrentStepInfo();
      notifyListeners();
      return;
    }
    
    if (_isInitializingNavigation) {
      print('⚠️ Navigation initialization already in progress, skipping...');
      return;
    }

    if (routeSteps.isEmpty) {
      print('⚠️ No route steps available, cannot initialize navigation');
      return;
    }

    _isInitializingNavigation = true;
    _navigationInitialized = true;
    _hasAnnouncedStartingNavigation = true;

    currentStepIndex = 0;
    isNavigating = routeSteps.isNotEmpty;
    hasAnnouncedCurrentStep = false;
    hasAnnouncedPrepare = false;
    hasAnnouncedNow = false;
    totalSteps = routeSteps.length;
    stepsCompleted = 0;
    showNavigationBanner = routeSteps.isNotEmpty;
    hasArrived = false;
    
    if (routeSteps.isNotEmpty) {
      _updateCurrentStepInfo();
      final firstStep = routeSteps[0];
      _updateBannerWithStep(firstStep);
      
      if (!_hasAnnouncedStartingNavigation) {
        _hasAnnouncedStartingNavigation = true;
        speak('Starting navigation. ${firstStep.instruction}');
        print('✅ "Starting navigation" spoken once');
      } else {
        speak(firstStep.instruction);
      }
    }
    
    notifyListeners();
    
    turnAlertTimer?.cancel();
    turnAlertTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkTurnAlerts();
    });
    
    _isInitializingNavigation = false;
    print('✅ Navigation initialization complete');
  }

  // ============================================================
  // RESET NAVIGATION STATE
  // ============================================================
  void resetNavigationState() {
    _navigationInitialized = false;
    _hasAnnouncedStartingNavigation = false;
    _isInitializingNavigation = false;
    isNavigating = false;
    hasArrived = false;
    currentStepIndex = 0;
    routeSteps = [];
    showNavigationBanner = false;
    turnAlertTimer?.cancel();
    // ✅ Cancel arrival listener on reset
    _arrivalCheckTimer?.cancel();
    _arrivalCheckTimer = null;
    print('🔄 Navigation state reset');
    notifyListeners();
  }

  void _updateBannerWithStep(NavigationStep step) {
    bannerInstruction = step.instruction;
    bannerManeuver = _getManeuverIcon(step.maneuver);
    bannerDistance = step.distanceText;
    bannerNextRoad = step.roadShield.isNotEmpty ? step.roadShield : step.roadName;
    bannerCurrentRoad = currentStepIndex > 0 ? routeSteps[currentStepIndex - 1].roadName : '';
    bannerSubInstruction = '${step.durationText} • ${step.roadName.isNotEmpty ? step.roadName : 'Current road'}';
    bannerProgress = currentStepIndex / (routeSteps.length > 0 ? routeSteps.length : 1);
    notifyListeners();
  }

  void _updateCurrentStepInfo() {
    if (currentStepIndex < routeSteps.length) {
      final step = routeSteps[currentStepIndex];
      laneGuidance = step.lanes;
      laneGuidanceText = laneGuidance.map((l) => l.displayChar).join(' ');
      nextInstruction = step.instruction;
      nextManeuver = step.maneuver;
      nextStepDistance = step.distance;
      nextRoadHeading = step.startHeading;
      
      bannerInstruction = step.instruction;
      bannerManeuver = _getManeuverIcon(step.maneuver);
      bannerDistance = step.distanceText;
      bannerProgress = currentStepIndex / (routeSteps.length > 0 ? routeSteps.length : 1);
      notifyListeners();
    }
  }

  void _checkTurnAlerts() {
    // ✅ If arrived, skip turn alerts
    if (hasArrived) return;
    
    if (currentPosition == null || routeSteps.isEmpty || currentStepIndex >= routeSteps.length) return;
    
    final currentStep = routeSteps[currentStepIndex];
    final distanceToStepEnd = Geolocator.distanceBetween(
      currentPosition!.latitude,
      currentPosition!.longitude,
      currentStep.endLocation.latitude,
      currentStep.endLocation.longitude,
    );
    
    _updateCurrentRoadHeading();
    
    if (currentRoadHeading != null && nextRoadHeading != null && currentStepIndex < routeSteps.length - 1) {
      final nextStep = routeSteps[currentStepIndex + 1];
      final nextStepHeading = nextStep.startHeading;
      
      double turnAngle = (nextStepHeading - currentRoadHeading!).abs() % 360;
      if (turnAngle > 180) turnAngle = 360 - turnAngle;
      
      if (turnAngle > 30) {
        final cross = _crossProduct(
          LatLng(currentPosition!.latitude, currentPosition!.longitude),
          _getPointAhead(LatLng(currentPosition!.latitude, currentPosition!.longitude), currentRoadHeading!, 10),
          _getPointAhead(currentStep.endLocation, nextStepHeading, 10)
        );
        final actualManeuver = cross > 0 ? 'turn-left' : 'turn-right';
        if (actualManeuver != nextManeuver) {
          nextManeuver = actualManeuver;
        }
      }
    }
    
    _checkJunctionProximity(distanceToStepEnd, currentStep.roadName, currentStep.maneuver);
    
    bannerDistance = _formatDistance(distanceToStepEnd);
    notifyListeners();
    
    if (isNavigating && _navigationInitialized) {
      if (distanceToStepEnd < 30 && distanceToStepEnd > 20) {
        announceTurn(currentStep.maneuver, distanceToStepEnd);
      } else if (distanceToStepEnd < 50 && distanceToStepEnd > 40) {
        announceTurn(currentStep.maneuver, distanceToStepEnd);
      } else if (distanceToStepEnd < 100 && distanceToStepEnd > 90) {
        announceTurn(currentStep.maneuver, distanceToStepEnd);
      } else if (distanceToStepEnd < 200 && distanceToStepEnd > 190) {
        announceTurn(currentStep.maneuver, distanceToStepEnd);
      } else if (distanceToStepEnd < 500 && distanceToStepEnd > 490) {
        announceTurn(currentStep.maneuver, distanceToStepEnd);
      } else if (distanceToStepEnd < 1000 && distanceToStepEnd > 990) {
        announceTurn(currentStep.maneuver, distanceToStepEnd);
      }
    }
    
    if (distanceToStepEnd < 20 && currentStepIndex < routeSteps.length - 1) {
      _completeStep();
    }
    
    if (distanceToStepEnd < 50 && currentStepIndex >= routeSteps.length - 1) {
      _handleArrival();
    }
  }

  LatLng _getPointAhead(LatLng from, double bearing, double distanceMeters) {
    const double R = 6371000;
    final lat = from.latitude * pi / 180;
    final lng = from.longitude * pi / 180;
    final brng = bearing * pi / 180;
    
    final newLat = asin(sin(lat) * cos(distanceMeters / R) + 
                         cos(lat) * sin(distanceMeters / R) * cos(brng));
    final newLng = lng + atan2(sin(brng) * sin(distanceMeters / R) * cos(lat),
                                cos(distanceMeters / R) - sin(lat) * sin(newLat));
    
    return LatLng(newLat * 180 / pi, newLng * 180 / pi);
  }

  void _updateCurrentRoadHeading() {
    if (currentRoutePoints.isEmpty || currentPosition == null) return;
    
    double minDist = double.infinity;
    int nearestIndex = 0;
    for (int i = 0; i < currentRoutePoints.length; i++) {
      final dist = Geolocator.distanceBetween(
        currentPosition!.latitude,
        currentPosition!.longitude,
        currentRoutePoints[i].latitude,
        currentRoutePoints[i].longitude,
      );
      if (dist < minDist) {
        minDist = dist;
        nearestIndex = i;
      }
    }
    
    if (nearestIndex < currentRoutePoints.length - 1) {
      currentRoadHeading = _calculateBearing(
        currentRoutePoints[nearestIndex],
        currentRoutePoints[min(nearestIndex + 1, currentRoutePoints.length - 1)]
      );
    }
  }

  void _completeStep() {
    if (hasArrived) return;
    
    currentStepIndex++;
    stepsCompleted = currentStepIndex;
    
    if (currentStepIndex < routeSteps.length) {
      _updateCurrentStepInfo();
      final nextStep = routeSteps[currentStepIndex];
      _updateBannerWithStep(nextStep);
      
      if (isNavigating && _navigationInitialized) {
        speak(nextStep.instruction);
      }
    }
  }

  void _handleArrival() {
    if (!hasArrived) {
      hasArrived = true;
      driverStatusText = '✅ You have arrived!';
      showNavigationBanner = false;
      notifyListeners();
      
      speak('You have arrived at your destination!');
      
      stopBackgroundLocationUpdates();
      resetNavigationState();
      
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text('✅ You have arrived at your destination!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _checkJunctionProximity(double distanceToStepEnd, String roadName, String maneuver) {
    final bool wasNearJunction = isNearJunction;
    isNearJunction = distanceToStepEnd < 200;
    junctionDistance = distanceToStepEnd;
    junctionRoadName = roadName;
    junctionManeuver = maneuver;
    showJunctionOverlay = isNearJunction;
    
    if (isNearJunction != wasNearJunction && mapController != null && renderedPosition != null) {
      _updateUberCameraPosition();
    }
    notifyListeners();
  }

  // ============================================================
  // GET MANEUVER ICON - PUBLIC
  // ============================================================
  String getManeuverIcon(String maneuver) {
    return _getManeuverIcon(maneuver);
  }

  String _getManeuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn-left': return '⬅️';
      case 'turn-right': return '➡️';
      case 'turn-sharp-left': return '↰';
      case 'turn-sharp-right': return '↱';
      case 'turn-slight-left': return '◀️';
      case 'turn-slight-right': return '▶️';
      case 'straight': return '⬆️';
      case 'continue': return '⬆️';
      case 'merge': return '🔀';
      case 'fork-left': return '⬅️↗️';
      case 'fork-right': return '➡️↖️';
      case 'ferry': return '⛴️';
      case 'roundabout': return '🔄';
      default: return '⬆️';
    }
  }

  // ============================================================
  // OFF-ROUTE DETECTION & RECALCULATION
  // ============================================================
  bool _isDriverOffRoute(LatLng driverPosition, List<LatLng> routePoints) {
    // ✅ If arrived, don't check off-route
    if (hasArrived) return false;
    
    if (routePoints.isEmpty) return false;
    
    double minDistance = double.infinity;
    int nearestIndex = 0;
    for (int i = 0; i < routePoints.length; i++) {
      final distance = Geolocator.distanceBetween(
        driverPosition.latitude,
        driverPosition.longitude,
        routePoints[i].latitude,
        routePoints[i].longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    
    bool headingMismatch = false;
    if (currentRoadHeading != null && nearestIndex < routePoints.length - 1) {
      final routeHeading = _calculateBearing(
        routePoints[nearestIndex],
        routePoints[min(nearestIndex + 1, routePoints.length - 1)]
      );
      final headingDiff = (currentRoadHeading! - routeHeading).abs() % 360;
      if (headingDiff > 90 && headingDiff < 270) {
        headingMismatch = true;
      }
    }
    
    return minDistance > routeRecalculationThreshold || headingMismatch;
  }

  void _recalculateRouteIfNeeded(LatLng driverPosition) {
    // ✅ If arrived, skip recalculation
    if (hasArrived) {
      print('✅ Already arrived - skipping route recalculation');
      return;
    }
    
    if (routeRecalculationTimer != null && routeRecalculationTimer!.isActive) return;
    if (isRecalculatingRoute) return;
    if (hasArrived) return;
    
    if (currentRoutePoints.isNotEmpty && _isDriverOffRoute(driverPosition, currentRoutePoints)) {
      print('🔄 Driver is off-route, recalculating...');
      isRecalculatingRoute = true;
      
      routeRecalculationTimer = Timer(const Duration(seconds: 3), () async {
        // ✅ Double-check arrival before recalculation
        if (hasArrived) {
          isRecalculatingRoute = false;
          print('⏹️ Skip recalculation - already arrived');
          return;
        }
        
        if (activeDriverLocation != null && currentPosition != null) {
          final lat = activeDriverLocation!['lat'] ?? 0;
          final lng = activeDriverLocation!['lng'] ?? 0;
          final origin = LatLng(lat, lng);
          final destination = LatLng(currentPosition!.latitude, currentPosition!.longitude);
          
          final result = await getRouteWithDetails(origin, destination);
          final points = result['points'] as List<LatLng>;
          final duration = result['duration'] as Duration?;
          final normalDuration = result['normalDuration'] as Duration?;
          final durationText = result['durationText'] as String?;
          final steps = result['steps'] as List<NavigationStep>;
          
          if (points.isNotEmpty) {
            currentRoutePoints = points;
            lastRouteOrigin = origin;
            lastRouteDestination = destination;
            actualTravelDuration = duration;
            normalTravelDuration = normalDuration;
            travelDurationText = durationText;
            useActualEta = duration != null;
            polylines = _buildPolylines(currentRoutePoints);
            isRecalculatingRoute = false;
            notifyListeners();
            
            if (steps.isNotEmpty && !hasArrived) {
              routeSteps = steps;
              if (!_navigationInitialized) {
                initializeTurnByTurnNavigation();
              } else {
                _updateCurrentStepInfo();
              }
            }
            
            if (duration != null) {
              estimatedMinutes = duration.inMinutes > 0 ? duration.inMinutes : 1;
              destinationEtaMinutes = estimatedMinutes!;
              notifyListeners();
            }
          } else {
            isRecalculatingRoute = false;
            notifyListeners();
          }
        } else {
          isRecalculatingRoute = false;
          notifyListeners();
        }
      });
    }
  }

  // ============================================================
  // TRAFFIC MONITORING
  // ============================================================
  void startTrafficMonitoring() {
    trafficRerouteTimer?.cancel();
    trafficRerouteTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkTrafficAndUpdateETA();
    });
  }

  Future<void> _checkTrafficAndUpdateETA() async {
    // ✅ If arrived, skip traffic check
    if (hasArrived) return;
    
    if (isCheckingTraffic || currentRoutePoints.isEmpty || renderedPosition == null) return;
    if (hasArrived) return;
    
    isCheckingTraffic = true;
    
    try {
      final origin = renderedPosition!;
      final destination = lastRouteDestination ?? 
          LatLng(currentPosition!.latitude, currentPosition!.longitude);
      
      final result = await getRouteWithDetails(origin, destination);
      final newDuration = result['duration'] as Duration?;
      final newNormalDuration = result['normalDuration'] as Duration?;
      
      if (newDuration != null && newNormalDuration != null) {
        final delayInSeconds = newDuration.inSeconds - newNormalDuration.inSeconds;
        
        Color trafficColor;
        String trafficLevel;
        if (delayInSeconds < 60) {
          trafficColor = Colors.green;
          trafficLevel = 'LIGHT';
        } else if (delayInSeconds < 300) {
          trafficColor = Colors.orange;
          trafficLevel = 'MODERATE';
        } else {
          trafficColor = Colors.red;
          trafficLevel = 'HEAVY';
        }
        
        currentTrafficColor = trafficColor;
        currentTrafficData = {'level': trafficLevel, 'delay': delayInSeconds};
        estimatedMinutes = newDuration.inMinutes > 0 ? newDuration.inMinutes : 1;
        destinationEtaMinutes = estimatedMinutes!;
        notifyListeners();
      }
    } catch (e) {
      print('Traffic check error: $e');
    }
    
    isCheckingTraffic = false;
  }

  // ============================================================
  // SPEED LIMIT MONITORING
  // ============================================================
  void startSpeedMonitoring() {
    speedCheckTimer?.cancel();
    speedCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkSpeedLimit();
    });
  }

  void _checkSpeedLimit() async {
    // ✅ If arrived, skip speed limit check
    if (hasArrived) return;
    
    if (currentSpeed > 0 && interpolatedDriverPosition != null) {
      final limit = await _getSpeedLimitFromAPI(interpolatedDriverPosition!);
      speedLimit = limit;
      isSpeeding = currentSpeed > speedLimit * 1.1 && speedLimit > 0;
      notifyListeners();
      
      if (isSpeeding) {
        speak('⚠️ Speed limit exceeded. Please slow down to $speedLimit km/h.');
      }
    }
  }

  Future<int> _getSpeedLimitFromAPI(LatLng position) async {
    try {
      final String url =
          'https://roads.googleapis.com/v1/speedLimits?path=${position.latitude},${position.longitude}'
          '&key=$googleAPIKey';

      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['speedLimits'] != null && data['speedLimits'].isNotEmpty) {
          return data['speedLimits'][0]['speedLimit'] as int;
        }
      }
    } catch (e) {
      print('Error getting speed limit: $e');
    }
    return _estimateSpeedLimit();
  }

  int _estimateSpeedLimit() {
    if (currentSpeed < 10) return 30;
    if (currentSpeed < 30) return 50;
    if (currentSpeed < 50) return 80;
    return 100;
  }

  // ============================================================
  // LOCATION & DRIVER METHODS
  // ============================================================
  Future<void> _getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
        isLoading = false;
        notifyListeners();
        return;
      }
      
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever) {
        isLoading = false;
        notifyListeners();
        return;
      }
      
      currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      print('📍 Location acquired: ${currentPosition!.latitude}, ${currentPosition!.longitude}');
      isLoading = false;
      notifyListeners();
      
      if (mapController != null && currentPosition != null) {
        _updateMapPadding();
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(currentPosition!.latitude, currentPosition!.longitude),
              zoom: 16,
            ),
          ),
        );
      }
      
      if (!showFuelSelector) _loadNearbyDrivers();
      
    } catch (e) {
      print('⚠️ Error getting location: $e');
      isLoading = false;
      notifyListeners();
    }
  }

  void _loadNearbyDrivers() {
    if (currentPosition == null) return;
    FirebaseFirestore.instance
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .get()
        .then((drivers) {
          if (drivers.docs.isEmpty) {
            noDriversFound = true;
            nearbyDrivers = [];
            driverMarkers = {};
            maxAvailableLitres = 0;
            showUseAvailableButton = false;
            showConfirmButton = false;
            selectedDriver = null;
            notifyListeners();
            return;
          }
          noDriversFound = false;
          notifyListeners();
          _updateDriverMarkers(drivers.docs);
        })
        .catchError((e) => print('Error loading drivers: $e'));
  }

  void _updateDriverMarkers(List<QueryDocumentSnapshot> drivers) {
    if (currentPosition == null) return;
    
    Set<Marker> markers = {};
    List<Map<String, dynamic>> nearby = [];
    double maxLitres = 0;
    int driversWithin10km = 0;

    for (var doc in drivers) {
      final data = doc.data() as Map<String, dynamic>;
      double lat = (data['lat'] ?? 0).toDouble();
      double lng = (data['lng'] ?? 0).toDouble();
      if (lat == 0 && lng == 0) continue;

      double distance = Geolocator.distanceBetween(
        currentPosition!.latitude, currentPosition!.longitude, lat, lng
      ) / 1000;
      if (distance > 10) continue;

      driversWithin10km++;
      final remainingFuel = data['remainingFuel'] ?? {};
      final fuelAvailable = (remainingFuel[selectedFuelType] ?? 0).toDouble();
      bool hasEnoughFuel = fuelAvailable >= selectedLitres;
      String vehicleType = data['vehicleType'] ?? 'medium';

      if (fuelAvailable > maxLitres) maxLitres = fuelAvailable;
      
      if (distance <= 10 && hasEnoughFuel && !cancelledDriverIds.contains(doc.id)) {
        nearby.add({
          'id': doc.id, 'data': data, 'distance': distance,
          'fuelType': selectedFuelType,
          'price': fuelTypes[selectedFuelType]!['price'] as double,
          'remainingFuel': fuelAvailable, 'vehicleType': vehicleType,
          'photoUrl': data['photoUrl'] ?? '', 'phone': data['phone'] ?? 'N/A',
        });
      }

      getVehicleMarker(vehicleType).then((customMarker) {
        markers.add(Marker(
          markerId: MarkerId(doc.id),
          position: LatLng(lat, lng),
          icon: customMarker,
          infoWindow: InfoWindow(
            title: '⛽ Fuel Truck',
            snippet: '${data['remainingFuel']?[selectedFuelType] ?? 0}L available',
          ),
        ));
        notifyListeners();
      });
    }

    driverMarkers = markers;
    nearbyDrivers = nearby;
    maxAvailableLitres = maxLitres;
    _validateLitres();
    noDriversFound = driversWithin10km == 0 && drivers.isNotEmpty;
    notifyListeners();
  }

  void _listenToDriversRealtime() {
    driverStreamSubscription?.cancel();
    driverStreamSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isEmpty) {
            noDriversFound = true;
            driverMarkers = {};
            nearbyDrivers = [];
            selectedDriver = null;
            showConfirmButton = false;
            notifyListeners();
          } else {
            noDriversFound = false;
            notifyListeners();
            _updateDriverMarkers(snapshot.docs);
          }
        }, onError: (error) => print('Error listening to drivers: $error'));
  }

  // ============================================================
  // ORDER MANAGEMENT
  // ============================================================
  Future<void> _checkActiveOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final orders = await FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: user.uid)
          .where('status', whereIn: ['pending', 'accepted'])
          .get();

      if (orders.docs.isNotEmpty) {
        final order = orders.docs.first;
        final data = order.data();
        final status = data['status'] ?? 'pending';
        
        if (activeOrderId != order.id) {
          hasActiveOrder = true;
          activeOrderId = order.id;
          activeDriverId = data['driverId'];
          activeOrderDetails = data;
          showVehicleSelector = false;
          showFuelSelector = false;
          isOrderAccepted = status == 'accepted';
          driverPhoneNumber = data['driverPhone'] ?? 'N/A';
          showConfirmButton = false;
          selectedDriver = null;
          isFuelSelectorExpanded = false;
          
          if (status == 'accepted') {
            orderAcceptedTime = DateTime.now();
          }
          
          if (status == 'pending') isWaitingForDrivers = true;
          notifyListeners();
          _listenToOrderStatus();
          if (activeDriverId != null && isOrderAccepted) _listenToDriverLocation();
        } else {
          activeOrderDetails = data;
          isOrderAccepted = status == 'accepted';
          driverPhoneNumber = data['driverPhone'] ?? 'N/A';
          isWaitingForDrivers = status == 'pending';
          notifyListeners();
        }
      } else if (hasActiveOrder) {
        _cancelDriverListener();
        hasActiveOrder = false;
        activeOrderId = null;
        activeDriverId = null;
        activeOrderDetails = null;
        activeDriverLocation = null;
        distanceToDriver = null;
        estimatedMinutes = null;
        polylines = {};
        showVehicleSelector = true;
        showFuelSelector = true;
        driverPhotoUrl = null;
        isOrderAccepted = false;
        isWaitingForDrivers = false;
        driverPhoneNumber = null;
        showDriverInfo = false;
        showConfirmButton = false;
        selectedDriver = null;
        isFuelSelectorExpanded = false;
        hasUserSelectedFuel = false;
        hasUserAdjustedLitres = false;
        hasUserSelectedDriver = false;
        showCallDriverButton = false;
        currentRoutePoints = [];
        useActualEta = false;
        actualTravelDuration = null;
        travelDurationText = null;
        routeSteps = [];
        isNavigating = false;
        currentStepIndex = 0;
        showNavigationBanner = false;
        hasArrived = false;
        orderAcceptedTime = null;
        hasDriverArrived = false;
        driverArrivalTime = null;
        stopBackgroundLocationUpdates();
        resetNavigationState();
        notifyListeners();
        orderStatusSubscription?.cancel();
      }
    } catch (e) {
      print('Error checking active order: $e');
    }
  }

  void _listenToOrderStatus() {
    orderStatusSubscription?.cancel();
    if (activeOrderId == null) return;

    orderStatusSubscription = FirebaseFirestore.instance
        .collection('orders')
        .doc(activeOrderId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) return;
          final data = snapshot.data();
          final status = data?['status'] ?? 'pending';
          
          if (status == 'accepted' && !isOrderAccepted) {
            isOrderAccepted = true;
            activeOrderDetails = data;
            isWaitingForDrivers = false;
            driverPhoneNumber = data?['driverPhone'] ?? 'N/A';
            showDriverInfo = true;
            showConfirmButton = false;
            isFuelSelectorExpanded = false;
            selectedDriver = null;
            showCallDriverButton = true;
            orderAcceptedTime = DateTime.now();
            notifyListeners();
            
            speak('Driver has been assigned to your order.');
            
            if (_context != null) {
              ScaffoldMessenger.of(_context!).showSnackBar(
                const SnackBar(content: Text('✅ Driver assigned! Tracking started.'), backgroundColor: Colors.green),
              );
            }
            if (activeDriverId != null) _listenToDriverLocation();
          } else if (status == 'cancelled' || status == 'completed') {
            _clearOrder(status == 'completed');
          }
        }, onError: (error) => print('Order status listener error: $error'));
  }

  void _clearOrder(bool isCompleted) {
    _cancelDriverListener();
    hasActiveOrder = false;
    activeOrderId = null;
    activeDriverId = null;
    activeOrderDetails = null;
    activeDriverLocation = null;
    distanceToDriver = null;
    estimatedMinutes = null;
    polylines = {};
    showVehicleSelector = true;
    showFuelSelector = true;
    driverPhotoUrl = null;
    isOrderAccepted = false;
    isWaitingForDrivers = false;
    driverPhoneNumber = null;
    showDriverInfo = false;
    showConfirmButton = false;
    selectedDriver = null;
    isFuelSelectorExpanded = false;
    hasUserSelectedFuel = false;
    hasUserAdjustedLitres = false;
    hasUserSelectedDriver = false;
    showCallDriverButton = false;
    currentRoutePoints = [];
    useActualEta = false;
    actualTravelDuration = null;
    travelDurationText = null;
    interpolatedDriverPosition = null;
    routeSteps = [];
    isNavigating = false;
    currentStepIndex = 0;
    driverStatusText = 'En Route';
    driverActionText = '';
    showNavigationBanner = false;
    hasArrived = false;
    orderAcceptedTime = null;
    hasDriverArrived = false;
    driverArrivalTime = null;
    stopBackgroundLocationUpdates();
    resetNavigationState();
    notifyListeners();
    
    if (isCompleted) {
      speak('Your fuel has been delivered. Thank you for using our service!');
    }
    
    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(isCompleted ? '✅ Fuel delivered successfully!' : 'Order was cancelled'),
          backgroundColor: isCompleted ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  void _cancelDriverListener() {
    driverLocationSubscription?.cancel();
    driverLocationSubscription = null;
    interpolationTimer?.cancel();
    routeRecalculationTimer?.cancel();
    turnAlertTimer?.cancel();
    cameraFollowTimer?.cancel();
    trafficRerouteTimer?.cancel();
    speedCheckTimer?.cancel();
    stopBackgroundLocationUpdates();
  }

  // ============================================================
  // CALL DRIVER
  // ============================================================
  Future<void> callDriver(String name, String phone) async {
    if (phone.isEmpty || phone == 'N/A') {
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(content: Text('Driver phone number not available'), backgroundColor: Colors.red)
        );
      }
      return;
    }
    if (_context != null) {
      showDialog(
        context: _context!,
        builder: (context) => AlertDialog(
          title: const Row(children: [Icon(Icons.phone, color: Colors.green), SizedBox(width: 8), Text('Call Driver', style: TextStyle(fontWeight: FontWeight.bold))]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Do you want to call $name?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [Icon(Icons.phone, color: Colors.green, size: 16), const SizedBox(width: 8), Text('Phone: $phone', style: TextStyle(fontSize: 14, color: Colors.green.shade700, fontWeight: FontWeight.w600))]),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold))),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                Navigator.pop(context);
                final uri = Uri(scheme: 'tel', path: phone);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
                else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not launch phone dialer'), backgroundColor: Colors.red)
                  );
                }
              },
              icon: const Icon(Icons.phone, color: Colors.white),
              label: Text('Call $name', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  // ============================================================
  // FUEL SELECTION - FIXED: Added _validateLitres
  // ============================================================
  void selectFuel(String fuelType) {
    selectedFuelType = fuelType;
    showFuelSelector = false;
    showVehicleSelector = true;
    noDriversFound = false;
    selectedLitres = 20;
    isLitresValid = true;
    litresErrorMessage = '';
    showUseAvailableButton = false;
    isFuelSelectorExpanded = false;
    selectedDriver = null;
    showConfirmButton = false;
    hasUserSelectedFuel = true;
    hasUserAdjustedLitres = false;
    hasUserSelectedDriver = false;
    _validateLitres(); // ✅ FIXED: Added validation
    notifyListeners();
    _loadNearbyDrivers();
  }

  void onLitresChanged(double val) {
    selectedLitres = val;
    hasUserAdjustedLitres = true;
    _validateLitres();
    _saveLitresToDatabase(val);
  }

  void _validateLitres() {
    if (selectedLitres > maxAvailableLitres && maxAvailableLitres > 0) {
      isLitresValid = false;
      litresErrorMessage = 'Maximum available: ${maxAvailableLitres.toStringAsFixed(0)}L';
      showUseAvailableButton = true;
    } else if (selectedLitres <= 0) {
      isLitresValid = false;
      litresErrorMessage = 'Please select at least 1L';
      showUseAvailableButton = false;
    } else if (nearbyDrivers.isEmpty) {
      isLitresValid = false;
      litresErrorMessage = 'No drivers available with this fuel type';
      showUseAvailableButton = false;
    } else {
      isLitresValid = true;
      litresErrorMessage = '';
      showUseAvailableButton = false;
    }
    notifyListeners();
  }

  void useAvailableFuel() {
    if (maxAvailableLitres > 0) {
      selectedLitres = maxAvailableLitres;
      hasUserAdjustedLitres = true;
      _validateLitres();
      _saveLitresToDatabase(selectedLitres);
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(content: Text('✅ Adjusted to maximum available: ${maxAvailableLitres.toStringAsFixed(0)}L'), backgroundColor: Colors.green)
        );
      }
    }
  }

  Future<void> _saveLitresToDatabase(double litres) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'selectedFuelType': selectedFuelType, 
        'selectedLitres': litres,
        'lastSelectionUpdate': FieldValue.serverTimestamp(), 
        'maxAvailableLitres': maxAvailableLitres, 
        'litresAdjusted': true,
      }, SetOptions(merge: true));
    } catch (e) { print('Error saving litres to database: $e'); }
  }

  // ============================================================
  // SELECT DRIVER & CONFIRM ORDER
  // ============================================================
  void selectDriver() {
    if (nearbyDrivers.isEmpty) {
      selectedDriver = null;
      showConfirmButton = false;
      hasUserSelectedDriver = false;
      notifyListeners();

      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text('⚠️ No drivers are currently available for the selected fuel type.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final nearest = nearbyDrivers.first;
    final driverData = nearest['data'] as Map<String, dynamic>;
    final remainingFuel = nearest['remainingFuel'] ?? 0;

    if (remainingFuel < selectedLitres) {
      selectedDriver = null;
      showConfirmButton = false;
      hasUserSelectedDriver = false;
      notifyListeners();

      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text('⚠️ This driver does not have enough fuel for your request.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    selectedDriver = {
      'id': nearest['id'],
      'data': driverData,
      'distance': nearest['distance'],
      'remainingFuel': remainingFuel,
      'vehicleType': driverData['vehicleType'] ?? 'medium',
    };
    showConfirmButton = true;
    hasUserSelectedDriver = true;
    hasUserSelectedFuel = true;
    hasUserAdjustedLitres = true;
    isFuelSelectorExpanded = false;
    notifyListeners();

    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        const SnackBar(
          content: Text('✅ Driver selected! Please confirm your order.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> confirmOrder() async {
    if (selectedDriver == null) {
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(content: Text('No driver selected. Please try again.'), backgroundColor: Colors.orange)
        );
      }
      return;
    }
    if (hasActiveOrder) {
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(content: Text('You already have an active order'))
        );
      }
      return;
    }

    isAutoSelecting = true;
    notifyListeners();
    final driverId = selectedDriver!['id'];
    final driverData = selectedDriver!['data'] as Map<String, dynamic>;
    final price = fuelTypes[selectedFuelType]!['price'] as double;

    try {
      final driverDoc = await FirebaseFirestore.instance.collection('drivers').doc(driverId).get();
      if (!driverDoc.exists) {
        if (_context != null) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            const SnackBar(content: Text('Driver is no longer available.'), backgroundColor: Colors.red)
          );
        }
        isAutoSelecting = false;
        selectedDriver = null;
        showConfirmButton = false;
        notifyListeners();
        return;
      }
      final driverDataSnapshot = driverDoc.data() as Map<String, dynamic>;
      if (!(driverDataSnapshot['isOnline'] ?? false)) {
        if (_context != null) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            const SnackBar(content: Text('Driver is currently offline.'), backgroundColor: Colors.red)
          );
        }
        isAutoSelecting = false;
        selectedDriver = null;
        showConfirmButton = false;
        notifyListeners();
        _loadNearbyDrivers();
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (_context != null) {
          ScaffoldMessenger.of(_context!).showSnackBar(const SnackBar(content: Text('Please login first')));
        }
        isAutoSelecting = false;
        notifyListeners();
        return;
      }

      String customerPhone = 'N/A';
      String customerName = user.displayName ?? 'Customer';
      String customerEmail = user.email ?? 'N/A';
      
      try {
        final customerDoc = await FirebaseFirestore.instance
            .collection('customers')
            .doc(user.uid)
            .get();
        
        if (customerDoc.exists) {
          final customerData = customerDoc.data()!;
          customerPhone = customerData['phone'] ?? customerPhone;
          customerName = customerData['name'] ?? customerName;
          customerEmail = customerData['email'] ?? customerEmail;
        }
      } catch (e) {
        print('Error fetching customer data: $e');
      }

      final total = price * selectedLitres;
      
      final orderRef = await FirebaseFirestore.instance.collection('orders').add({
        'driverId': driverId,
        'driverName': driverData['name'] ?? 'Fuel Tanker',
        'driverPhone': driverData['phone'] ?? 'N/A',
        'driverPhoto': driverData['photoUrl'] ?? '',
        'driverPlateNumber': driverData['numberPlate'] ?? 'N/A',
        'driverVehicleType': driverData['vehicleType'] ?? 'medium',
        'fuelType': selectedFuelType,
        'litres': selectedLitres,
        'pricePerLiter': price,
        'totalPrice': total,
        'userId': user.uid,
        'userName': customerName,
        'userPhone': customerPhone,
        'userEmail': customerEmail,
        'userLocation': currentPosition != null ? GeoPoint(currentPosition!.latitude, currentPosition!.longitude) : null,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'customerLat': currentPosition?.latitude ?? 0,
        'customerLng': currentPosition?.longitude ?? 0,
        'customerPhoto': user.photoURL ?? '',
        'customerAddress': 'Customer Location',
        'driverStatus': 'pending',
      });

      final orderId = orderRef.id;
      
      await FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
        'activeOrderId': orderId,
        'orderStartedAt': FieldValue.serverTimestamp(),
        'status': 'busy',
        'lastOrderTime': FieldValue.serverTimestamp(),
      });

      isAutoSelecting = false;
      showConfirmButton = false;
      selectedDriver = null;
      isWaitingForDrivers = true;
      hasActiveOrder = true;
      isFuelSelectorExpanded = false;
      hasUserSelectedFuel = false;
      hasUserAdjustedLitres = false;
      hasUserSelectedDriver = false;
      activeOrderId = orderId;
      activeDriverId = driverId;
      notifyListeners();
      
      _listenToOrderStatus();
      
      startBackgroundLocationUpdates();
      
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text('✅ Order placed! Waiting for driver to accept...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      isAutoSelecting = false;
      notifyListeners();
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(content: Text('Error placing order: $e'))
        );
      }
    }
  }

  // ============================================================
  // CANCEL ORDER
  // ============================================================
  Future<void> cancelOrderWithReason() async {
    if (activeOrderId == null) return;
    final controller = TextEditingController();
    String selectedReason = 'Changed my mind';
    final reasons = ['Changed my mind', 'Found a cheaper option', 'Driver taking too long', 'Ordered wrong fuel type', 'Wrong quantity', 'Emergency', 'Other'];
    final user = FirebaseAuth.instance.currentUser;
    String userName = user?.displayName ?? 'Customer';
    String userPhone = user?.phoneNumber ?? 'N/A';
    String userEmail = user?.email ?? 'N/A';

    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('customers').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          userName = data['name'] ?? userName;
          userPhone = data['phone'] ?? userPhone;
          userEmail = data['email'] ?? userEmail;
        }
      } catch (e) {}
    }

    if (_context != null) {
      showDialog(
        context: _context!,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(children: [Icon(Icons.cancel, color: Colors.red), SizedBox(width: 8), Text('Cancel Order', style: TextStyle(fontWeight: FontWeight.bold))]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order Details:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text('${activeOrderDetails?['fuelType'] ?? 'N/A'} - ${activeOrderDetails?['litres'] ?? 0}L', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Total: KES ${(activeOrderDetails?['totalPrice'] ?? 0).toStringAsFixed(2)}', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Reason for cancellation:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontWeight: FontWeight.w500)))).toList(),
                  onChanged: (v) { if (v != null) selectedReason = v; },
                ),
                if (selectedReason == 'Other') ...[
                  const SizedBox(height: 8),
                  TextField(controller: controller, decoration: const InputDecoration(labelText: 'Please specify', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)), maxLines: 2),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                  child: const Row(children: [Icon(Icons.info_outline, size: 16, color: Colors.orange), SizedBox(width: 8), Expanded(child: Text('Your cancellation reason will be saved for quality improvement.', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w500)))]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () { Navigator.pop(context); controller.dispose(); }, child: const Text('Keep Order', style: TextStyle(fontWeight: FontWeight.bold))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final reason = selectedReason == 'Other' ? controller.text.trim() : selectedReason;
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please provide a reason'), backgroundColor: Colors.orange)
                  );
                  return;
                }
                await _cancelOrderWithDetails(reason, userName, userPhone, userEmail);
                Navigator.pop(context);
                controller.dispose();
              },
              child: const Text('Cancel Order', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _cancelOrderWithDetails(String reason, String userName, String userPhone, String userEmail) async {
    if (activeOrderId == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      
      if (activeDriverId != null) {
        cancelledDriverIds.add(activeDriverId!);
        print('🔒 Driver ${activeDriverId} blocked for this user only');
      }

      await FirebaseFirestore.instance.collection('cancellations').add({
        'orderId': activeOrderId, 'userId': user?.uid ?? 'unknown',
        'userName': userName, 'userPhone': userPhone, 'userEmail': userEmail,
        'fuelType': activeOrderDetails?['fuelType'] ?? 'N/A',
        'litres': activeOrderDetails?['litres'] ?? 0,
        'totalPrice': activeOrderDetails?['totalPrice'] ?? 0,
        'driverId': activeDriverId, 'driverName': activeOrderDetails?['driverName'] ?? 'N/A',
        'reason': reason, 'createdAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('orders').doc(activeOrderId).update({
        'status': 'cancelled', 'cancelledByUser': true, 'cancellationReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
        'userIdAtCancellation': user?.uid ?? 'unknown',
        'cancelledFuelType': activeOrderDetails?['fuelType'] ?? 'N/A',
        'cancelledLitres': activeOrderDetails?['litres'] ?? 0,
        'cancelledTotalPrice': activeOrderDetails?['totalPrice'] ?? 0,
      });
      if (activeDriverId != null) {
        await FirebaseFirestore.instance.collection('drivers').doc(activeDriverId).update({
          'activeOrderId': null, 'orderStartedAt': null,
        });
      }
      _cancelDriverListener();
      hasActiveOrder = false;
      activeOrderId = null;
      activeDriverId = null;
      activeOrderDetails = null;
      activeDriverLocation = null;
      distanceToDriver = null;
      estimatedMinutes = null;
      polylines = {};
      showVehicleSelector = true;
      showFuelSelector = true;
      driverPhotoUrl = null;
      isOrderAccepted = false;
      isWaitingForDrivers = false;
      driverPhoneNumber = null;
      showDriverInfo = false;
      showConfirmButton = false;
      selectedDriver = null;
      isFuelSelectorExpanded = false;
      hasUserSelectedFuel = false;
      hasUserAdjustedLitres = false;
      hasUserSelectedDriver = false;
      showCallDriverButton = false;
      currentRoutePoints = [];
      useActualEta = false;
      actualTravelDuration = null;
      travelDurationText = null;
      interpolatedDriverPosition = null;
      routeSteps = [];
      isNavigating = false;
      currentStepIndex = 0;
      showNavigationBanner = false;
      hasArrived = false;
      orderAcceptedTime = null;
      hasDriverArrived = false;
      driverArrivalTime = null;
      stopBackgroundLocationUpdates();
      resetNavigationState();
      notifyListeners();
      _loadNearbyDrivers();
      
      speak('Your order has been cancelled.');
      
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text('✅ Order cancelled. This driver will not be shown to you.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (_context != null) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          SnackBar(content: Text('Error cancelling order: $e'))
        );
      }
    }
  }

  // ============================================================
  // HELPERS & GETTERS
  // ============================================================
  int calculateEta(double distanceKm) {
    double speed = distanceKm < 1 ? 20 : distanceKm < 3 ? 25 : distanceKm < 5 ? 30 : distanceKm < 10 ? 35 : 40;
    return (distanceKm / speed * 60).ceil().clamp(1, 60);
  }

  String getArrivalTime() {
    if (estimatedMinutes == null) return 'Now';
    final arrival = DateTime.now().add(Duration(minutes: estimatedMinutes!));
    final period = arrival.hour >= 12 ? 'PM' : 'AM';
    final hour = arrival.hour > 12 ? arrival.hour - 12 : arrival.hour;
    return '${hour}:${arrival.minute.toString().padLeft(2, '0')} $period';
  }

  void loadNearbyDrivers() {
    _loadNearbyDrivers();
  }

  void goToUserProfile() {
    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        const SnackBar(content: Text('👤 User Profile'), backgroundColor: Colors.blue),
      );
    }
  }

  void refreshLocation() {
    _getCurrentLocation();
  }

  void startLocationUpdates() {
    if (currentPosition != null) {
      _loadNearbyDrivers();
      _checkActiveOrder();
    }
  }

  // ============================================================
  // TEST GOOGLE MAPS API
  // ============================================================
  void _testGoogleMapsAPI() {
    Timer(const Duration(seconds: 2), () async {
      try {
        final testUrl = 'https://maps.googleapis.com/maps/api/directions/json?origin=-1.286389,36.817223&destination=-1.292066,36.821945&key=$googleAPIKey';
        final response = await http.get(Uri.parse(testUrl));
        print('🌐 API Test Status: ${response.statusCode}');
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print('🌐 API Test Status: ${data['status']}');
          if (data['status'] == 'OK') {
            print('✅ Google Maps API is working!');
          }
        }
      } catch (e) {
        print('⚠️ API Test Error: $e');
      }
    });
  }

  // ============================================================
  // MAP STYLE FOR LARGER FONTS
  // ============================================================
  String getMapStyle() {
    return '''
[
  {
    "featureType": "all",
    "elementType": "labels.text",
    "stylers": [
      { "visibility": "on" },
      { "size": "large" }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text",
    "stylers": [
      { "visibility": "on" },
      { "size": "large" }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text",
    "stylers": [
      { "visibility": "on" },
      { "size": "large" }
    ]
  },
  {
    "featureType": "landscape",
    "elementType": "labels.text",
    "stylers": [
      { "visibility": "on" },
      { "size": "large" }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text",
    "stylers": [
      { "visibility": "on" },
      { "size": "large" }
    ]
  },
  {
    "featureType": "transit",
    "elementType": "labels.text",
    "stylers": [
      { "visibility": "on" },
      { "size": "large" }
    ]
  },
  {
    "featureType": "administrative",
    "elementType": "labels.text",
    "stylers": [
      { "visibility": "on" },
      { "size": "large" }
    ]
  },
  {
    "featureType": "administrative.neighborhood",
    "elementType": "labels.text",
    "stylers": [
      { "visibility": "on" },
      { "size": "large" }
    ]
  }
]
''';
  }

  // ============================================================
  // FUEL IMAGE DATA
  // ============================================================
  Future<Map<String, dynamic>> getFuelImageData(String imagePath) async {
    if (fuelImageCache.containsKey(imagePath)) {
      return {'descriptor': fuelImageCache[imagePath]!, 'bytes': fuelImageBytesCache[imagePath]!};
    }
    
    try {
      final ByteData data = await rootBundle.load(imagePath);
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: 200, targetHeight: 200);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ByteData? resizedData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      
      if (resizedData == null) return await _createFuelEmojiFallback(imagePath);
      
      final Uint8List resizedBytes = resizedData.buffer.asUint8List();
      final marker = BitmapDescriptor.fromBytes(resizedBytes);
      
      fuelImageCache[imagePath] = marker;
      fuelImageBytesCache[imagePath] = resizedBytes;
      return {'descriptor': marker, 'bytes': resizedBytes};
    } catch (e) {
      return await _createFuelEmojiFallback(imagePath);
    }
  }

  Future<Map<String, dynamic>> _createFuelEmojiFallback(String imagePath) async {
    String emoji;
    Color color;
    if (imagePath.contains('petrol')) { emoji = '⛽'; color = Colors.green; }
    else if (imagePath.contains('diesel')) { emoji = '🛢️'; color = Colors.blue; }
    else if (imagePath.contains('kerosin')) { emoji = '🔥'; color = Colors.orange; }
    else if (imagePath.contains('vpower')) { emoji = '⚡'; color = Colors.purple; }
    else { emoji = '⛽'; color = Colors.green; }
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(const Offset(40, 40), 38, Paint()..color = color.withOpacity(0.2));
    canvas.drawCircle(const Offset(40, 40), 38, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);
    
    final painter = TextPainter(text: TextSpan(text: emoji, style: const TextStyle(fontSize: 44)), textDirection: TextDirection.ltr);
    painter.layout();
    painter.paint(canvas, Offset(40 - painter.width / 2, 40 - painter.height / 2));
    
    final img = await recorder.endRecording().toImage(80, 80);
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    final marker = BitmapDescriptor.fromBytes(bytes);
    fuelImageCache[imagePath] = marker;
    fuelImageBytesCache[imagePath] = bytes;
    return {'descriptor': marker, 'bytes': bytes};
  }

  // ============================================================
  // GET MAP PADDING
  // ============================================================
  EdgeInsets getMapPadding() {
    return mapPadding;
  }

  void setMapPadding(EdgeInsets padding) {
    mapPadding = padding;
  }
}