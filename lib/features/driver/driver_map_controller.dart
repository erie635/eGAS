// ============================================================
// FILE: lib/features/driver/driver_map_controller.dart
// COMPLETE - UPDATED WITH ENHANCED ZOOM LOGIC
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/discount_service.dart';

// ============================================================
// CONSTANTS
// ============================================================
const String googleAPIKey = 'AIzaSyATIUosv_VCeiVsQ3q6_LSQhZkrHr0E79o';

// ============================================================
// NAVIGATION SESSION STATE
// ============================================================
enum NavigationSessionState {
  idle,
  navigating,
  paused,
  completed,
  cancelled,
}

// ============================================================
// LANE INFO
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
// NAVIGATION STEP
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
// ANIMATED DRIVER DATA
// ============================================================
class AnimatedDriverData {
  final String id;
  final String vehicleType;
  final String numberPlate;
  final List<LatLng> path;
  final double bearing;
  final double speed;
  final bool isMoving;

  AnimatedDriverData({
    required this.id,
    required this.vehicleType,
    required this.numberPlate,
    required this.path,
    required this.bearing,
    required this.speed,
    this.isMoving = true,
  });
}

// ============================================================
// ENHANCED: Error Log Entry
// ============================================================
class ErrorLogEntry {
  final String message;
  final Map<String, dynamic> details;
  final DateTime timestamp;
  final String level;

  ErrorLogEntry({
    required this.message,
    this.details = const {},
    required this.timestamp,
    this.level = 'error',
  });

  Map<String, dynamic> toJson() => {
    'message': message,
    'details': details,
    'timestamp': timestamp.toIso8601String(),
    'level': level,
  };
}

// ============================================================
// OPTIMIZATION: Firestore Batch Manager - FIXED
// ============================================================
class FirestoreBatchManager {
  final List<Map<String, dynamic>> _batch = [];
  Timer? _batchTimer;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Duration _batchInterval;
  
  FirestoreBatchManager({Duration batchInterval = const Duration(seconds: 3)}) 
      : _batchInterval = batchInterval;
  
  void addUpdate(String path, Map<String, dynamic> data) {
    _batch.add({'path': path, 'data': Map<String, dynamic>.from(data)});
    _scheduleBatch();
  }
  
  void _scheduleBatch() {
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchInterval, () async {
      await _flushBatch();
    });
  }
  
  Future<void> _flushBatch() async {
    if (_batch.isEmpty) return;
    
    try {
      final batch = _firestore.batch();
      for (var item in _batch) {
        final ref = _firestore.doc(item['path']);
        batch.update(ref, item['data']);
      }
      await batch.commit();
      _batch.clear();
    } catch (e) {
      // Keep items for retry
      print('⚠️ Batch update failed, will retry: $e');
    }
  }
  
  Future<void> flush() async {
    _batchTimer?.cancel();
    await _flushBatch();
  }
  
  void dispose() {
    _batchTimer?.cancel();
    _batch.clear();
  }
}

// ============================================================
// OPTIMIZATION: Marker Pool
// ============================================================
class MarkerPool {
  static const int MAX_CACHED_MARKERS = 20;
  final Map<String, Marker> _pool = {};
  final List<String> _lru = [];
  
  Marker getOrCreate(String id, Marker Function() create) {
    if (_pool.containsKey(id)) {
      _lru.remove(id);
      _lru.add(id);
      return _pool[id]!;
    }
    
    final marker = create();
    if (_lru.length >= MAX_CACHED_MARKERS) {
      final oldest = _lru.removeAt(0);
      _pool.remove(oldest);
    }
    _pool[id] = marker;
    _lru.add(id);
    return marker;
  }
  
  void clear() {
    _pool.clear();
    _lru.clear();
  }
  
  int get size => _pool.length;
}

// ============================================================
// OPTIMIZATION: Camera Update Throttler
// ============================================================
class CameraUpdateThrottler {
  Timer? _timer;
  CameraPosition? _pendingPosition;
  final GoogleMapController controller;
  final Duration throttleInterval;
  bool _isDisposed = false;
  
  CameraUpdateThrottler(this.controller, {this.throttleInterval = const Duration(milliseconds: 100)});
  
  void updatePosition(CameraPosition position) {
    if (_isDisposed) return;
    _pendingPosition = position;
    _timer ??= Timer.periodic(throttleInterval, (_) {
      if (!_isDisposed && _pendingPosition != null) {
        try {
          controller.animateCamera(CameraUpdate.newCameraPosition(_pendingPosition!));
        } catch (e) {
          // Ignore - controller may be disposed
        }
        _pendingPosition = null;
      }
    });
  }
  
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
    _pendingPosition = null;
  }
}

// ============================================================
// OPTIMIZATION: Lazy Step Loader - FIXED
// ============================================================
class LazyStepLoader {
  final List<NavigationStep> _steps;
  final Map<int, NavigationStep> _cache = {};
  final int _pageSize;
  
  LazyStepLoader(this._steps, {int pageSize = 5}) 
      : _pageSize = pageSize;
  
  NavigationStep? getStep(int index) {
    if (index >= _steps.length) return null;
    
    if (!_cache.containsKey(index)) {
      // Load surrounding steps in batch
      final start = max(0, index - 2);
      final end = min(_steps.length, index + 3);
      for (int i = start; i < end; i++) {
        if (!_cache.containsKey(i)) {
          _cache[i] = _steps[i];
        }
      }
      
      // Clear old cache
      if (_cache.length > _pageSize * 3) {
        final keysToRemove = _cache.keys
          .where((k) => k < start - 5 || k > end + 5)
          .toList();
        keysToRemove.forEach(_cache.remove);
      }
    }
    
    return _cache[index];
  }
  
  void clear() {
    _cache.clear();
  }
  
  int get length => _steps.length;
}

// ============================================================
// OPTIMIZATION: TTS Manager with Caching
// ============================================================
class TTSManager {
  final Map<String, String> _cache = {};
  final FlutterTts _tts;
  bool _initialized = false;
  
  TTSManager() : _tts = FlutterTts();
  
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _initialized = true;
    } catch (e) {
      print('⚠️ TTS initialization error: $e');
    }
  }
  
  Future<void> speak(String text) async {
    if (!_initialized) await initialize();
    if (text.isEmpty) return;
    
    final key = text.hashCode.toString();
    _cache[key] = text; // Cache for potential future use
    
    try {
      await _tts.speak(text);
    } catch (e) {
      print('⚠️ TTS speak error: $e');
    }
  }
  
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      // Ignore
    }
  }
  
  void clearCache() => _cache.clear();
  
  void dispose() {
    clearCache();
    try {
      _tts.stop();
    } catch (e) {
      // Ignore
    }
  }
}

// ============================================================
// ENHANCED: DRIVER MAP CONTROLLER
// ============================================================
class DriverMapController {
  // ============================================================
  // MAP CONTROLLER & STATE
  // ============================================================
  GoogleMapController? mapController;
  Set<Marker> mapMarkers = {};
  Set<Marker> animatedMarkers = {};
  Set<Polyline> polylines = {};
  LatLng? driverLocation;
  LatLng? customerLocation;
  double? distanceToCustomer;
  int? estimatedMinutes;
  BuildContext? _context;

  // ============================================================
  // FIREBASE
  // ============================================================
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  DocumentReference? driverLocationRef;
  DocumentReference? sessionRef;
  String? driverId;

  // ============================================================
  // OPTIMIZATION: Firestore Batch Manager
  // ============================================================
  final FirestoreBatchManager _batchManager = FirestoreBatchManager();

  // ============================================================
  // NAVIGATION SESSION MANAGEMENT
  // ============================================================
  String? _currentSessionId;
  NavigationSessionState _currentSessionState = NavigationSessionState.idle;
  bool _isSessionActive = false;
  bool _navigationInitialized = false;
  bool _hasAnnouncedStartingNavigation = false;
  bool _hasArrivedAndSessionEnded = false;
  bool _isInitializingNavigation = false;
  StreamSubscription<DocumentSnapshot>? _sessionSubscription;
  Map<String, dynamic> _sessionData = {};
  Timer? _sessionUpdateTimer;

  // ============================================================
  // SESSION CALLBACKS
  // ============================================================
  VoidCallback? onSessionStarted;
  VoidCallback? onSessionCompleted;
  VoidCallback? onSessionCancelled;
  Function(String)? onSessionError;
  Function(Map<String, dynamic>)? onSessionUpdate;

  // ============================================================
  // THROTTLING & DEBOUNCING
  // ============================================================
  LatLng? lastSentPosition;
  double minDistanceThreshold = 15.0;
  Duration minTimeThreshold = const Duration(seconds: 5);
  DateTime? lastFirestoreUpdateTime;
  Timer? firestoreDebounceTimer;
  bool isFirestoreUpdateQueued = false;
  LatLng? queuedPosition;
  double? queuedHeading;
  double? queuedSpeed;

  // ============================================================
  // OPTIMIZATION: Last update timestamps for throttling
  // ============================================================
  DateTime? _lastTurnCheckTime;
  static const Duration _turnCheckInterval = Duration(seconds: 2);
  DateTime? _lastCameraCheckTime;
  static const Duration _cameraCheckInterval = Duration(milliseconds: 100);

  // ============================================================
  // NAVIGATION ENHANCEMENTS
  // ============================================================
  List<LatLng> currentRoutePoints = [];
  Timer? routeRecalculationTimer;
  bool isRecalculatingRoute = false;
  static const double routeRecalculationThreshold = 50.0;
  LatLng? lastRouteOrigin;
  LatLng? lastRouteDestination;
  Duration? actualTravelDuration;
  Duration? normalTravelDuration;
  String? travelDurationText;
  bool useActualEta = false;

  // ============================================================
  // OPTIMIZATION: Lazy Step Loader
  // ============================================================
  LazyStepLoader? _lazyStepLoader;

  // ============================================================
  // SMOOTH INTERPOLATION
  // ============================================================
  LatLng? interpolatedDriverPosition;
  Timer? interpolationTimer;
  double interpolationProgress = 1.0;
  LatLng? previousInterpolatedPosition;
  LatLng? targetInterpolatedPosition;
  DateTime? interpolationStartTime;
  static const Duration interpolationDuration = Duration(milliseconds: 400);

  // ============================================================
  // ENHANCED TURN-BY-TURN NAVIGATION
  // ============================================================
  List<NavigationStep> routeSteps = [];
  int currentStepIndex = 0;
  bool isNavigating = false;
  String nextInstruction = '';
  String nextManeuver = '';
  double nextStepDistance = 0;
  Timer? turnAlertTimer;
  bool hasAnnouncedCurrentStep = false;

  // ============================================================
  // HEADING-BASED TURN VALIDATION
  // ============================================================
  double? lastValidHeading;
  List<double> headingHistory = [];
  static const int maxHeadingHistory = 5;
  double? currentRoadHeading;
  double? nextRoadHeading;
  double turnAngle = 0;

  // ============================================================
  // ENHANCED ZOOM CONTROL - SPEED & CONTEXT AWARE
  // ============================================================
  double currentZoom = 17.0;
  static const double baseZoom = 17.0;
  double minZoom = 14.0;
  double maxZoom = 19.5;
  Timer? zoomSmoothingTimer;
  static const double driverOffsetY = 0.7;
  
  // Smooth zoom transition variables
  double _smoothZoom = 17.0;
  double _zoomVelocity = 0.0;
  static const double zoomSmoothFactor = 0.15;
  static const double zoomSmoothDamping = 0.85;
  
  // Zoom levels for different contexts
  double _zoomAtSpeed = 17.0;
  double _zoomAtJunction = 17.0;
  double _zoomAtArrival = 17.0;
  double _zoomAtRouteStart = 17.0;
  bool _wasNearJunction = false;

  // ============================================================
  // PREDICTIVE CAMERA
  // ============================================================
  bool predictiveCameraEnabled = true;
  LatLng? predictedCameraTarget;
  bool isMapRotating = false; // KEEP NORTH UP - Don't rotate map

  // ============================================================
  // DRIVER SPEED & HEADING
  // ============================================================
  double currentSpeed = 0.0;
  double currentHeading = 0.0;
  double previousHeading = 0.0;
  double headingSmooth = 0.0;
  Timer? headingSmoothingTimer;

  // ============================================================
  // CAMERA FOLLOWING
  // ============================================================
  Timer? cameraFollowTimer;
  bool isCameraFollowing = true;
  LatLng? cameraTargetPosition;
  double cameraBearing = 0; // Always 0 for North-up
  double cameraZoom = 17.0;
  LatLng? lastKnownPosition;
  bool isDriverMoving = false;
  Timer? movementCheckTimer;
  static const double movementThreshold = 0.5;

  // ============================================================
  // OPTIMIZATION: Camera Update Throttler
  // ============================================================
  CameraUpdateThrottler? _cameraThrottler;

  // ============================================================
  // MARKER CACHE
  // ============================================================
  final Map<String, BitmapDescriptor> markerCache = {};
  
  // ============================================================
  // OPTIMIZATION: Marker Pool
  // ============================================================
  final MarkerPool _markerPool = MarkerPool();

  // ============================================================
  // CALLBACKS
  // ============================================================
  VoidCallback? onMapUpdated;
  Function(String, String)? onTurnAlert;

  // ============================================================
  // TRAFFIC FEATURES
  // ============================================================
  bool trafficEnabled = true;
  bool isCheckingTraffic = false;
  Timer? trafficUpdateTimer;
  Color currentTrafficColor = const Color(0xFF1A73E8);
  Map<String, dynamic>? currentTrafficData;
  List<Map<String, dynamic>> trafficSegments = [];

  // ============================================================
  // SPEED LIMIT FEATURES
  // ============================================================
  int currentSpeedLimit = 0;
  bool isSpeeding = false;
  Timer? speedLimitTimer;
  String speedLimitDisplay = '--';

  // ============================================================
  // ALTERNATIVE ROUTES
  // ============================================================
  List<List<LatLng>> alternativeRoutes = [];
  List<Duration> alternativeDurations = [];
  int selectedRouteIndex = 0;

  // ============================================================
  // VOICE NAVIGATION
  // ============================================================
  bool isVoiceEnabled = true;
  String lastSpokenInstruction = '';
  Timer? voiceDebounceTimer;
  Timer? voiceAnnouncementTimer;
  double lastAnnouncementDistance = -1;
  List<String> announcementQueue = [];
  Function(String)? speakCallback;
  
  // ============================================================
  // OPTIMIZATION: TTS Manager
  // ============================================================
  final TTSManager _ttsManager = TTSManager();
  bool _ttsInitialized = false;

  // ============================================================
  // WAKE LOCK
  // ============================================================
  bool _wakeLockEnabled = false;

  // ============================================================
  // ROAD SNAPPING
  // ============================================================
  LatLng? snappedDriverPosition;
  Timer? snappingTimer;
  List<LatLng> recentPositions = [];
  static const int maxRecentPositions = 10;

  // ============================================================
  // LANE GUIDANCE
  // ============================================================
  List<LaneInfo> laneGuidance = [];
  String laneGuidanceText = '';

  // ============================================================
  // JUNCTION VIEW
  // ============================================================
  bool isNearJunction = false;
  bool showJunctionOverlay = false;
  String junctionRoadName = '';
  String junctionManeuver = '';
  double junctionDistance = 0;

  // ============================================================
  // ROAD SHIELDS
  // ============================================================
  Map<String, String> roadShields = {};

  // ============================================================
  // ENHANCED NAVIGATION BANNER
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
  // ARRIVAL ANIMATION
  // ============================================================
  bool hasArrived = false;
  Timer? arrivalAnimationTimer;

  // ============================================================
  // ADDED: Arrival listener timer to stop route refreshing
  // ============================================================
  Timer? _arrivalCheckTimer;

  // ============================================================
  // TRAFFIC COLOR MAP
  // ============================================================
  Map<String, Color> trafficColorMap = {
    'LIGHT': Colors.green,
    'MODERATE': Colors.orange,
    'HEAVY': Colors.red,
    'SEVERE': Colors.red.shade900,
  };

  // ============================================================
  // GPS FILTERING
  // ============================================================
  LatLng? filteredPosition;
  double filterAlpha = 0.7;

  // ============================================================
  // MAP PADDING
  // ============================================================
  EdgeInsets mapPadding = const EdgeInsets.only(
    top: 40,
    bottom: 180,
    left: 10,
    right: 10,
  );
  double screenHeight = 0;
  double screenWidth = 0;

  // ============================================================
  // ROUTE FOLLOWING
  // ============================================================
  bool useRouteFollowing = true;
  double routeSnapDistance = 30.0;

  // ============================================================
  // VEHICLE INFO
  // ============================================================
  double carWidth = 80.0;
  double carHeight = 120.0;
  String? _currentVehicleType;
  String? _currentNumberPlate;

  // ============================================================
  // UI OVERFLOW FIX
  // ============================================================
  bool useScrollableContent = true;

  // ============================================================
  // ANIMATED MARKER TRACKING
  // ============================================================
  final Map<String, AnimatedDriverData> _animatedDrivers = {};
  final Map<String, List<LatLng>> _driverPaths = {};
  final Map<String, Marker> _staticDrivers = {};
  Timer? _animationUpdateTimer;
  Duration animarkerDuration = const Duration(milliseconds: 2000);
  Curve animarkerCurve = Curves.easeInOut;
  bool animarkerUseRotation = true;

  // ============================================================
  // ENHANCED: Configuration options for feature toggles
  // ============================================================
  Map<String, bool> _features = {
    'voiceNavigation': true,
    'routeSnapping': true,
    'wakeLock': true,
    'trafficMonitoring': true,
    'speedLimitMonitoring': true,
    'progressiveRouteClearing': true,
    'predictiveCamera': true,
    'junctionOverlay': true,
    'animatedMarkers': true,
    'alternativeRoutes': true,
  };

  // ============================================================
  // ENHANCED: Error logging system
  // ============================================================
  final List<ErrorLogEntry> _errorLogs = [];
  static const int maxErrorLogs = 100;
  Function(ErrorLogEntry)? onErrorLogged;

  // ============================================================
  // ENHANCED: Performance tracking
  // ============================================================
  Map<String, Stopwatch> _performanceTimers = {};
  Map<String, Duration> _performanceMetrics = {};

  // ============================================================
  // ENHANCED: Retry configuration
  // ============================================================
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  // ============================================================
  // CONSTRUCTOR
  // ============================================================
  DriverMapController({
    BuildContext? context,
    this.driverId,
  }) {
    _context = context;
    if (driverId != null) {
      driverLocationRef = firestore.collection('drivers').doc(driverId);
      _autoCreateDriverController();
    }
    _initTTS();
    _startPerformanceMonitoring();
  }

  void setContext(BuildContext context) {
    _context = context;
  }

  // ============================================================
  // ENHANCED: Feature toggles (dynamic configuration)
  // ============================================================
  void setFeature(String feature, bool enabled) {
    if (_features.containsKey(feature)) {
      _features[feature] = enabled;
      _logInfo('Feature "$feature" set to $enabled', details: {'feature': feature, 'enabled': enabled});
      
      switch (feature) {
        case 'voiceNavigation':
          isVoiceEnabled = enabled;
          if (!enabled) {
            _ttsManager.stop();
          }
          break;
        case 'routeSnapping':
          useRouteFollowing = enabled;
          break;
        case 'wakeLock':
          if (enabled) {
            enableWakeLock();
          } else {
            disableWakeLock();
          }
          break;
        case 'trafficMonitoring':
          if (enabled) {
            startTrafficMonitoring();
          } else {
            trafficUpdateTimer?.cancel();
            trafficUpdateTimer = null;
          }
          break;
        case 'speedLimitMonitoring':
          if (enabled) {
            startSpeedLimitMonitoring();
          } else {
            speedLimitTimer?.cancel();
            speedLimitTimer = null;
          }
          break;
        case 'progressiveRouteClearing':
          break;
        case 'predictiveCamera':
          predictiveCameraEnabled = enabled;
          break;
        case 'junctionOverlay':
          break;
        case 'animatedMarkers':
          if (!enabled) {
            _animationUpdateTimer?.cancel();
            _animationUpdateTimer = null;
          } else {
            initializeAnimationUpdates();
          }
          break;
        case 'alternativeRoutes':
          break;
        default:
          break;
      }
    }
  }

  bool getFeature(String feature) {
    return _features[feature] ?? false;
  }

  Map<String, bool> getAllFeatures() {
    return Map<String, bool>.from(_features);
  }

  // ============================================================
  // ENHANCED: Error logging methods
  // ============================================================
  void _logError(String message, {Map<String, dynamic>? details}) {
    final entry = ErrorLogEntry(
      message: message,
      details: details ?? {},
      timestamp: DateTime.now(),
      level: 'error',
    );
    _errorLogs.add(entry);
    if (_errorLogs.length > maxErrorLogs) {
      _errorLogs.removeAt(0);
    }
    onErrorLogged?.call(entry);
    print('❌ ERROR: $message');
    if (details != null) {
      print('   Details: $details');
    }
  }

  void _logWarning(String message, {Map<String, dynamic>? details}) {
    final entry = ErrorLogEntry(
      message: message,
      details: details ?? {},
      timestamp: DateTime.now(),
      level: 'warning',
    );
    _errorLogs.add(entry);
    if (_errorLogs.length > maxErrorLogs) {
      _errorLogs.removeAt(0);
    }
    print('⚠️ WARNING: $message');
  }

  void _logInfo(String message, {Map<String, dynamic>? details}) {
    if (details != null) {
      print('ℹ️ INFO: $message $details');
    } else {
      print('ℹ️ INFO: $message');
    }
  }

  List<ErrorLogEntry> getErrorLogs() {
    return List<ErrorLogEntry>.from(_errorLogs);
  }

  void clearErrorLogs() {
    _errorLogs.clear();
  }

  // ============================================================
  // ENHANCED: Performance monitoring
  // ============================================================
  void _startPerformanceMonitoring() {
    _performanceTimers['routeRecalculation'] = Stopwatch();
    _performanceTimers['arrivalDetection'] = Stopwatch();
    _performanceTimers['routeParsing'] = Stopwatch();
    _performanceTimers['markerGeneration'] = Stopwatch();
    _performanceTimers['routeDrawing'] = Stopwatch();
  }

  void _startTimer(String name) {
    if (_performanceTimers.containsKey(name)) {
      _performanceTimers[name]!.reset();
      _performanceTimers[name]!.start();
    }
  }

  void _stopTimer(String name) {
    if (_performanceTimers.containsKey(name)) {
      _performanceTimers[name]!.stop();
      _performanceMetrics[name] = _performanceTimers[name]!.elapsed;
      if (_performanceMetrics[name]!.inMilliseconds > 100) {
        _logWarning('Performance: $name took ${_performanceMetrics[name]!.inMilliseconds}ms', 
            details: {'duration': _performanceMetrics[name]!.inMilliseconds});
      }
    }
  }

  Map<String, Duration> getPerformanceMetrics() {
    return Map<String, Duration>.from(_performanceMetrics);
  }

  // ============================================================
  // ENHANCED: Retry logic for Firebase operations
  // ============================================================
  Future<T> _withRetry<T>(Future<T> Function() operation, {String operationName = 'Firebase operation'}) async {
    int attempts = 0;
    while (attempts < _maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempts++;
        if (attempts >= _maxRetries) {
          _logError('$operationName failed after $_maxRetries attempts', details: {'error': e.toString()});
          rethrow;
        }
        _logWarning('$operationName attempt $attempts failed, retrying in ${_retryDelay.inSeconds}s...');
        await Future.delayed(_retryDelay);
      }
    }
    throw Exception('$operationName failed');
  }

  // ============================================================
  // AUTO-CREATE DRIVER CONTROLLER IN FIREBASE
  // ============================================================
  Future<void> _autoCreateDriverController() async {
    if (driverId == null) return;
    try {
      final doc = await firestore.collection('drivers').doc(driverId!).get();
      if (!doc.exists) {
        _logInfo('Auto-creating driver controller in Firebase...');
        await firestore.collection('drivers').doc(driverId!).set({
          'uid': driverId,
          'email': null,
          'name': 'Driver',
          'vehicleType': 'small',
          'numberPlate': 'Unknown',
          'isOnline': false,
          'isAvailable': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'position': {'lat': 0.0, 'lng': 0.0},
          'heading': 0.0,
          'speed': 0.0,
          'rating': 0.0,
          'totalDeliveries': 0,
          'status': 'offline',
          'sessionId': null,
          'sessionState': 'idle',
          'currentOrderId': null,
          'currentCustomerId': null,
          'navigationActive': false,
          'hasArrived': false,
        });
        _logInfo('Driver controller auto-created in Firebase!');
      }
    } catch (e) {
      _logError('Error auto-creating driver controller', details: {'error': e.toString()});
    }
  }

  // ============================================================
  // CREATE DRIVER CONTROLLER WITH CUSTOM DATA
  // ============================================================
  Future<void> createDriverController({
    required String email,
    required String name,
    String vehicleType = 'small',
    String numberPlate = 'Unknown',
  }) async {
    if (driverId == null) return;
    try {
      await firestore.collection('drivers').doc(driverId!).set({
        'uid': driverId,
        'email': email,
        'name': name,
        'vehicleType': vehicleType,
        'numberPlate': numberPlate,
        'isOnline': false,
        'isAvailable': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'position': {'lat': 0.0, 'lng': 0.0},
        'heading': 0.0,
        'speed': 0.0,
        'rating': 0.0,
        'totalDeliveries': 0,
        'status': 'offline',
        'sessionId': null,
        'sessionState': 'idle',
        'currentOrderId': null,
        'currentCustomerId': null,
        'navigationActive': false,
        'hasArrived': false,
      }, SetOptions(merge: true));
      _logInfo('Driver controller created with custom data!');
    } catch (e) {
      _logError('Error creating driver controller', details: {'error': e.toString()});
      throw Exception('Failed to create driver controller: $e');
    }
  }

  // ============================================================
  // UPDATE DRIVER INFORMATION
  // ============================================================
  Future<void> updateDriverInfo({
    String? name,
    String? vehicleType,
    String? numberPlate,
    bool? isOnline,
    bool? isAvailable,
  }) async {
    if (driverId == null) return;
    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (name != null) updates['name'] = name;
      if (vehicleType != null) updates['vehicleType'] = vehicleType;
      if (numberPlate != null) updates['numberPlate'] = numberPlate;
      if (isOnline != null) {
        updates['isOnline'] = isOnline;
        updates['status'] = isOnline ? 'online' : 'offline';
      }
      if (isAvailable != null) updates['isAvailable'] = isAvailable;
      await firestore.collection('drivers').doc(driverId!).update(updates);
      _logInfo('Driver info updated');
    } catch (e) {
      _logError('Error updating driver info', details: {'error': e.toString()});
      throw Exception('Failed to update driver info: $e');
    }
  }

  // ============================================================
  // SET DRIVER ONLINE/OFFLINE
  // ============================================================
  Future<void> setDriverOnline(bool online) async {
    await updateDriverInfo(isOnline: online);
    if (online && getFeature('wakeLock')) {
      await enableWakeLock();
    } else {
      await disableWakeLock();
    }
  }

  // ============================================================
  // GET DRIVER DATA FROM FIREBASE
  // ============================================================
  Future<Map<String, dynamic>?> getDriverData() async {
    if (driverId == null) return null;
    try {
      final doc = await firestore.collection('drivers').doc(driverId!).get();
      if (doc.exists) return doc.data();
      return null;
    } catch (e) {
      _logError('Error getting driver data', details: {'error': e.toString()});
      return null;
    }
  }

  // ============================================================
  // CHECK IF DRIVER CONTROLLER EXISTS
  // ============================================================
  Future<bool> driverControllerExists() async {
    if (driverId == null) return false;
    try {
      final doc = await firestore.collection('drivers').doc(driverId!).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // TTS INITIALIZATION
  // ============================================================
  void _initTTS() {
    if (_ttsInitialized) return;
    try {
      _ttsManager.initialize();
      _ttsInitialized = true;
      _logInfo('TTS initialized successfully');
    } catch (e) {
      _logWarning('TTS initialization error', details: {'error': e.toString()});
    }
  }

  // ============================================================
  // SPEAK METHOD
  // ============================================================
  void speak(String text) {
    if (!isVoiceEnabled || !getFeature('voiceNavigation')) return;
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
      _ttsManager.speak(text);
      if (speakCallback != null) {
        speakCallback!(text);
      }
      _logInfo('VOICE: $text');
    });
    voiceAnnouncementTimer?.cancel();
    voiceAnnouncementTimer = Timer(const Duration(seconds: 2), () {
      if (announcementQueue.isNotEmpty) {
        final nextText = announcementQueue.removeAt(0);
        _speakImmediately(nextText);
      }
    });
  }

  void setSpeakCallback(Function(String) callback) {
    speakCallback = callback;
  }

  // ============================================================
  // WAKE LOCK
  // ============================================================
  Future<void> enableWakeLock() async {
    if (_wakeLockEnabled) return;
    try {
      await WakelockPlus.enable();
      _wakeLockEnabled = true;
      _logInfo('Screen wake lock enabled');
    } catch (e) {
      _logWarning('Wake lock enable error', details: {'error': e.toString()});
    }
  }

  Future<void> disableWakeLock() async {
    if (!_wakeLockEnabled) return;
    try {
      await WakelockPlus.disable();
      _wakeLockEnabled = false;
      _logInfo('Screen wake lock disabled');
    } catch (e) {
      _logWarning('Wake lock disable error', details: {'error': e.toString()});
    }
  }

  Future<void> toggleWakeLock(bool enable) async {
    if (enable) {
      await enableWakeLock();
    } else {
      await disableWakeLock();
    }
  }

  bool isWakeLockEnabled() {
    return _wakeLockEnabled;
  }

  // ============================================================
  // FIREBASE SESSION MANAGEMENT - REAL-TIME CONTROL
  // ============================================================

  Future<String> createNavigationSession({
    required String orderId,
    required String customerId,
    required String customerName,
    required LatLng origin,
    required LatLng destination,
    required String vehicleType,
    required String numberPlate,
  }) async {
    if (driverId == null) {
      throw Exception('Driver ID not set');
    }

    if (_isSessionActive) {
      await endNavigationSession(cancelled: true);
    }

    _navigationInitialized = false;
    _hasAnnouncedStartingNavigation = false;
    _hasArrivedAndSessionEnded = false;
    hasArrived = false;
    _isInitializingNavigation = false;

    _currentSessionId = firestore
        .collection('drivers')
        .doc(driverId)
        .collection('navigation_sessions')
        .doc()
        .id;

    _sessionData = {
      'sessionId': _currentSessionId,
      'driverId': driverId,
      'orderId': orderId,
      'customerId': customerId,
      'customerName': customerName,
      'vehicleType': vehicleType,
      'numberPlate': numberPlate,
      'origin': {
        'lat': origin.latitude,
        'lng': origin.longitude,
      },
      'destination': {
        'lat': destination.latitude,
        'lng': destination.longitude,
      },
      'state': 'idle',
      'createdAt': FieldValue.serverTimestamp(),
      'startedAt': null,
      'completedAt': null,
      'cancelledAt': null,
      'totalDistance': 0.0,
      'totalDuration': 0,
      'currentStepIndex': 0,
      'currentInstruction': '',
      'isRecalculating': false,
      'progress': 0.0,
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    sessionRef = firestore
        .collection('drivers')
        .doc(driverId)
        .collection('navigation_sessions')
        .doc(_currentSessionId);

    await sessionRef!.set(_sessionData);

    await firestore
        .collection('orders')
        .doc(orderId)
        .update({
      'navigationSessionId': _currentSessionId,
      'navigationStatus': 'started',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await firestore
        .collection('drivers')
        .doc(driverId)
        .update({
      'sessionId': _currentSessionId,
      'sessionState': 'idle',
      'currentOrderId': orderId,
      'currentCustomerId': customerId,
      'navigationActive': true,
      'hasArrived': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _isSessionActive = true;
    _currentSessionState = NavigationSessionState.idle;

    _startSessionListener();
    _startSessionUpdateTimer();

    _logInfo('Navigation session created: $_currentSessionId');
    return _currentSessionId!;
  }

  void _startSessionListener() {
    _sessionSubscription?.cancel();
    if (sessionRef == null) return;

    _sessionSubscription = sessionRef!.snapshots().listen(
      (snapshot) {
        if (!snapshot.exists) {
          _logWarning('Session document deleted');
          _handleSessionEnded();
          return;
        }

        final data = snapshot.data() as Map<String, dynamic>;
        _sessionData = data;

        final stateString = data['state'] as String? ?? 'idle';
        final newState = NavigationSessionState.values.firstWhere(
          (e) => e.toString().split('.').last == stateString,
          orElse: () => NavigationSessionState.idle,
        );

        if (newState != _currentSessionState) {
          _logInfo('Session state changed: ${_currentSessionState} → $newState');
          _currentSessionState = newState;
          _handleSessionStateChange(newState, data);
        }

        onSessionUpdate?.call(data);
        _logInfo('Session updated from Firebase: ${data['state']}');
      },
      onError: (error) {
        _logError('Session listener error', details: {'error': error.toString()});
        onSessionError?.call(error.toString());
      },
    );
  }

  void _handleSessionStateChange(NavigationSessionState state, Map<String, dynamic> data) {
    _logInfo('Handling session state change: $state');
    
    switch (state) {
      case NavigationSessionState.idle:
        if (_navigationInitialized && !_hasArrivedAndSessionEnded) {
          _navigationInitialized = false;
          _hasAnnouncedStartingNavigation = false;
          _logInfo('Navigation reset to idle state');
        }
        break;

      case NavigationSessionState.navigating:
        if (!_navigationInitialized && currentRoutePoints.isNotEmpty) {
          _initializeNavigation();
        }
        if (!isNavigating && _navigationInitialized) {
          isNavigating = true;
          _startTurnAlerts();
          speak('Resuming navigation');
        }
        break;

      case NavigationSessionState.paused:
        if (isNavigating) {
          isNavigating = false;
          turnAlertTimer?.cancel();
          speak('Navigation paused');
          _logInfo('Navigation paused from Firebase');
        }
        break;

      case NavigationSessionState.completed:
        if (!_hasArrivedAndSessionEnded) {
          _completeNavigationFromFirebase();
        }
        break;

      case NavigationSessionState.cancelled:
        if (!_hasArrivedAndSessionEnded) {
          _cancelNavigationFromFirebase();
        }
        break;
    }
  }

  Future<void> updateSessionState(NavigationSessionState state) async {
    if (sessionRef == null || !_isSessionActive) {
      _logWarning('Cannot update session: not active');
      return;
    }

    final stateString = state.toString().split('.').last;
    Map<String, dynamic> updates = {
      'state': stateString,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    switch (state) {
      case NavigationSessionState.navigating:
        updates['startedAt'] = FieldValue.serverTimestamp();
        updates['isActive'] = true;
        break;
      case NavigationSessionState.completed:
        updates['completedAt'] = FieldValue.serverTimestamp();
        updates['isActive'] = false;
        break;
      case NavigationSessionState.cancelled:
        updates['cancelledAt'] = FieldValue.serverTimestamp();
        updates['isActive'] = false;
        break;
      default:
        break;
    }

    await sessionRef!.update(updates);
    _currentSessionState = state;
    
    if (driverId != null) {
      // Use batch manager for driver update
      _batchManager.addUpdate(
        'drivers/${driverId!}',
        {
          'sessionState': stateString,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      );
    }
    
    _logInfo('Session state updated to: $stateString');
  }

  Future<void> updateSessionProgress() async {
    if (sessionRef == null || !_isSessionActive) return;

    double progress = 0.0;
    if (routeSteps.isNotEmpty) {
      progress = currentStepIndex / routeSteps.length;
    }

    double totalDistance = 0.0;
    if (currentRoutePoints.isNotEmpty) {
      for (int i = 0; i < currentStepIndex && i < routeSteps.length; i++) {
        totalDistance += routeSteps[i].distance;
      }
      if (currentStepIndex < routeSteps.length && driverLocation != null) {
        final currentStep = routeSteps[currentStepIndex];
        final distanceToEnd = Geolocator.distanceBetween(
          driverLocation!.latitude,
          driverLocation!.longitude,
          currentStep.endLocation.latitude,
          currentStep.endLocation.longitude,
        );
        final stepProgress = 1 - (distanceToEnd / currentStep.distance);
        totalDistance += currentStep.distance * stepProgress.clamp(0.0, 1.0);
      }
    }

    int totalDuration = 0;
    if (_sessionData['startedAt'] != null) {
      final startedAt = (_sessionData['startedAt'] as Timestamp).toDate();
      totalDuration = DateTime.now().difference(startedAt).inSeconds;
    }

    final updates = {
      'totalDistance': totalDistance / 1000,
      'totalDuration': totalDuration,
      'currentStepIndex': currentStepIndex,
      'currentInstruction': nextInstruction,
      'isRecalculating': isRecalculatingRoute,
      'progress': progress,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastLocation': {
        'lat': driverLocation?.latitude ?? 0,
        'lng': driverLocation?.longitude ?? 0,
      },
      'currentSpeed': currentSpeed,
      'currentHeading': currentHeading,
    };

    // Use batch manager for session updates
    if (sessionRef != null) {
      _batchManager.addUpdate(sessionRef!.path, updates);
    }
  }

  void _startSessionUpdateTimer() {
    _sessionUpdateTimer?.cancel();
    _sessionUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) {
        if (_isSessionActive) {
          updateSessionProgress();
        }
      },
    );
  }

  Future<void> endNavigationSession({bool cancelled = false}) async {
    if (!_isSessionActive || sessionRef == null) return;

    final state = cancelled
        ? NavigationSessionState.cancelled
        : NavigationSessionState.completed;

    await updateSessionState(state);

    _isSessionActive = false;
    _navigationInitialized = false;
    _hasAnnouncedStartingNavigation = false;
    _hasArrivedAndSessionEnded = true;
    _isInitializingNavigation = false;
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _sessionUpdateTimer?.cancel();
    _sessionUpdateTimer = null;

    if (driverId != null) {
      await firestore
          .collection('drivers')
          .doc(driverId!)
          .update({
        'sessionId': null,
        'sessionState': 'idle',
        'currentOrderId': null,
        'currentCustomerId': null,
        'navigationActive': false,
        'hasArrived': cancelled ? false : true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (_sessionData.containsKey('orderId')) {
      await firestore
          .collection('orders')
          .doc(_sessionData['orderId'])
          .update({
        'navigationStatus': cancelled ? 'cancelled' : 'completed',
        'navigationSessionId': _currentSessionId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (cancelled) {
      onSessionCancelled?.call();
    } else {
      onSessionCompleted?.call();
    }

    _logInfo('Session ended: ${cancelled ? 'cancelled' : 'completed'}');
  }

  void _handleSessionEnded() {
    _isSessionActive = false;
    _navigationInitialized = false;
    _hasAnnouncedStartingNavigation = false;
    _hasArrivedAndSessionEnded = true;
    _isInitializingNavigation = false;
    _sessionUpdateTimer?.cancel();
    _sessionUpdateTimer = null;
    clearRoute();
    onSessionCompleted?.call();
    _logInfo('Session ended from Firebase');
  }

  void _initializeNavigation() {
    if (_isInitializingNavigation) {
      _logWarning('Navigation initialization already in progress, skipping...');
      return;
    }
    
    if (_navigationInitialized) {
      _logWarning('Navigation already initialized, skipping...');
      return;
    }
    
    if (routeSteps.isEmpty) {
      _logWarning('No route steps available, cannot initialize navigation');
      return;
    }
    
    _isInitializingNavigation = true;
    _navigationInitialized = true;
    _hasAnnouncedStartingNavigation = true;
    
    _logInfo('✅✅✅ NAVIGATION INITIALIZED');
    
    initializeTurnByTurnNavigation();
    updateSessionState(NavigationSessionState.navigating);
    onSessionStarted?.call();
    
    _isInitializingNavigation = false;
    _logInfo('✅ Navigation initialization complete');
  }

  void _completeNavigationFromFirebase() {
    _logInfo('Completing navigation from Firebase');
    _handleArrival();
    _isSessionActive = false;
    _navigationInitialized = false;
    _hasAnnouncedStartingNavigation = false;
    _hasArrivedAndSessionEnded = true;
    _isInitializingNavigation = false;
    _sessionUpdateTimer?.cancel();
    _sessionUpdateTimer = null;
    onSessionCompleted?.call();
    _logInfo('Navigation completed from Firebase');
  }

  void _cancelNavigationFromFirebase() {
    _logInfo('Cancelling navigation from Firebase');
    _isSessionActive = false;
    _navigationInitialized = false;
    _hasAnnouncedStartingNavigation = false;
    _hasArrivedAndSessionEnded = true;
    _isInitializingNavigation = false;
    _sessionUpdateTimer?.cancel();
    _sessionUpdateTimer = null;
    clearRoute();
    onSessionCancelled?.call();
    speak('Navigation cancelled by request');
    _logInfo('Navigation cancelled from Firebase');
  }

  // ============================================================
  // GET SESSION STATUS
  // ============================================================
  Map<String, dynamic> getSessionStatus() {
    return {
      'isActive': _isSessionActive,
      'sessionId': _currentSessionId,
      'state': _currentSessionState.toString().split('.').last,
      'navigationInitialized': _navigationInitialized,
      'hasAnnouncedStartingNavigation': _hasAnnouncedStartingNavigation,
      'hasArrived': hasArrived,
      'hasArrivedAndSessionEnded': _hasArrivedAndSessionEnded,
      'totalDistance': _sessionData['totalDistance'] ?? 0.0,
      'totalDuration': _sessionData['totalDuration'] ?? 0,
      'currentStep': currentStepIndex,
      'totalSteps': routeSteps.length,
      'progress': _sessionData['progress'] ?? 0.0,
      'orderId': _sessionData['orderId'],
      'customerId': _sessionData['customerId'],
      'customerName': _sessionData['customerName'],
    };
  }

  String getDeliveryStatus() {
    if (hasArrived || _hasArrivedAndSessionEnded) return 'Delivered ✅';
    if (!_isSessionActive) return 'Not Started ⏳';
    if (isNavigating) return 'In Transit 🚗';
    if (_currentSessionState == NavigationSessionState.paused) return 'Paused ⏸️';
    if (_currentSessionState == NavigationSessionState.cancelled) return 'Cancelled ❌';
    return 'Pending ⏳';
  }

  Future<void> togglePauseNavigation() async {
    if (!_isSessionActive) {
      _logWarning('No active session to pause');
      return;
    }

    if (_currentSessionState == NavigationSessionState.paused) {
      await updateSessionState(NavigationSessionState.navigating);
      isNavigating = true;
      speak('Resuming navigation');
      _startTurnAlerts();
    } else if (_currentSessionState == NavigationSessionState.navigating) {
      await updateSessionState(NavigationSessionState.paused);
      isNavigating = false;
      turnAlertTimer?.cancel();
      speak('Navigation paused');
    } else {
      _logWarning('Cannot toggle pause in current state: $_currentSessionState');
    }
  }

  void _startTurnAlerts() {
    turnAlertTimer?.cancel();
    turnAlertTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkTurnAlerts();
    });
  }

  Future<void> forceSessionUpdate() async {
    if (_isSessionActive) {
      await updateSessionProgress();
    }
  }

  Map<String, dynamic> getSessionData() {
    return Map<String, dynamic>.from(_sessionData);
  }

  bool isSessionActive() => _isSessionActive;

  Future<void> cancelCurrentSession() async {
    if (_isSessionActive) {
      await endNavigationSession(cancelled: true);
      speak('Navigation cancelled');
    }
  }

  // ============================================================
  // OPTIMIZATION: Route Point Downsampling
  // ============================================================
  List<LatLng> _downsampleRoutePoints(List<LatLng> points, {double tolerance = 0.0001}) {
    if (points.length < 100) return points;
    
    final result = <LatLng>[points.first];
    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];
      
      final distance = _perpendicularDistance(prev, curr, next);
      if (distance > tolerance) {
        result.add(curr);
      }
    }
    result.add(points.last);
    return result;
  }

  double _perpendicularDistance(LatLng p1, LatLng p2, LatLng p3) {
    final x1 = p1.latitude, y1 = p1.longitude;
    final x2 = p2.latitude, y2 = p2.longitude;
    final x3 = p3.latitude, y3 = p3.longitude;
    
    final numerator = ((x2-x1)*(y3-y1) - (y2-y1)*(x3-x1)).abs();
    final denominator = sqrt(pow(x2-x1, 2) + pow(y2-y1, 2));
    return denominator > 0 ? numerator / denominator : 0;
  }

  // ============================================================
  // OPTIMIZATION: Intelligent Route Recalculation Check
  // ============================================================
  bool _shouldRecalculateRoute(LatLng position, List<LatLng> route) {
    if (route.isEmpty) return false;
    
    const double corridorWidth = 50.0;
    double minDistance = double.infinity;
    
    // Sample every 5th point for efficiency
    for (int i = 0; i < route.length; i += 5) {
      final distance = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        route[i].latitude, route[i].longitude
      );
      if (distance < minDistance) minDistance = distance;
      if (minDistance < corridorWidth) return false;
    }
    
    // Check if significantly off-route
    if (minDistance > corridorWidth * 2) {
      return true;
    }
    
    return false;
  }

  // ============================================================
  // DRAW ROUTE TO CUSTOMER - UPDATED WITH HOME_MAP LOGIC
  // ============================================================
  Future<void> drawRouteToCustomer(
    LatLng origin,
    LatLng destination,
    String vehicleType,
    String numberPlate, {
    String? orderId,
    String? customerId,
    String? customerName,
  }) async {
    if (_isSessionActive && _navigationInitialized && isNavigating) {
      _logWarning('Navigation already active, skipping drawRouteToCustomer');
      return;
    }
    
    if (_isInitializingNavigation) {
      _logWarning('Navigation initialization already in progress, skipping...');
      return;
    }

    _logInfo('drawRouteToCustomer called - drawing new route');
    
    customerLocation = destination;
    driverLocation = origin;

    // Reset arrival flag when starting new route
    hasArrived = false;
    _hasArrivedAndSessionEnded = false;

    polylines.clear();
    routeSteps.clear();
    alternativeRoutes.clear();
    alternativeDurations.clear();
    trafficSegments.clear();

    setCustomerMarker(destination);
    await updateDriverMarker(vehicleType, numberPlate);

    _startTimer('routeParsing');
    final result = await _withRetry(
      () => getRouteWithDetails(origin, destination, getAlternatives: true),
      operationName: 'Route fetch',
    );
    final routePoints = result['points'] as List<LatLng>;
    final duration = result['duration'] as Duration?;
    final normalDuration = result['normalDuration'] as Duration?;
    final durationText = result['durationText'] as String?;
    final steps = result['steps'] as List<NavigationStep>;
    final alternatives = result['alternatives'] as List<List<LatLng>>? ?? [];
    final altDurations = result['alternativeDurations'] as List<Duration>? ?? [];
    _stopTimer('routeParsing');

    // OPTIMIZATION: Downsample route points
    currentRoutePoints = _downsampleRoutePoints(routePoints);
    lastRouteOrigin = origin;
    lastRouteDestination = destination;
    actualTravelDuration = duration;
    normalTravelDuration = normalDuration;
    travelDurationText = durationText;
    useActualEta = duration != null;
    alternativeRoutes = alternatives;
    alternativeDurations = altDurations;
    selectedRouteIndex = 0;

    // Initialize lazy step loader
    _lazyStepLoader = LazyStepLoader(steps);

    if (currentRoutePoints.isNotEmpty) {
      polylines = _buildPolylinesWithTraffic(currentRoutePoints);
      polylines.addAll(_buildAlternativePolylines(alternatives));
    } else {
      _logWarning('Route points empty, using fallback route');
      polylines = _buildFallbackRoute(origin, destination);
    }

    distanceToCustomer = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    ) / 1000;

    if (duration != null) {
      estimatedMinutes = duration.inMinutes > 0 ? duration.inMinutes : 1;
    } else {
      estimatedMinutes = ((distanceToCustomer! / 40) * 60).ceil();
    }

    if (steps.isNotEmpty) {
      routeSteps = steps;
      _lazyStepLoader = LazyStepLoader(steps);

      if (orderId != null && customerId != null && driverId != null) {
        try {
          await createNavigationSession(
            orderId: orderId,
            customerId: customerId,
            customerName: customerName ?? 'Customer',
            origin: origin,
            destination: destination,
            vehicleType: vehicleType,
            numberPlate: numberPlate,
          );
          _initializeNavigation();
        } catch (e) {
          _logError('Session creation error', details: {'error': e.toString()});
          onSessionError?.call(e.toString());
          initializeTurnByTurnNavigation();
        }
      } else {
        initializeTurnByTurnNavigation();
      }
    } else {
      _logWarning('No steps available for route');
    }

    _updateMapPadding();
    startCameraFollowing();
    startTrafficMonitoring();
    startSpeedLimitMonitoring();
    initializeAnimationUpdates();

    // Start arrival listener to stop route refreshing when destination reached
    _startArrivalListener();

    onMapUpdated?.call();
  }

  // ============================================================
  // ADDED: Arrival Listener to stop route refresh
  // ============================================================
  void _startArrivalListener() {
    // Cancel any existing timer
    _arrivalCheckTimer?.cancel();
    
    // Start periodic check for arrival
    _arrivalCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      // If already arrived, stop checking
      if (hasArrived || _hasArrivedAndSessionEnded) {
        timer.cancel();
        _arrivalCheckTimer = null;
        _logInfo('✅ Arrival detected - stopping route refresh listener');
        return;
      }
      
      // Check if driver has arrived at destination
      if (driverLocation != null && customerLocation != null) {
        final distance = Geolocator.distanceBetween(
          driverLocation!.latitude,
          driverLocation!.longitude,
          customerLocation!.latitude,
          customerLocation!.longitude,
        );
        
        // If within 100 meters, consider arrived
        if (distance < 100) {
          _logInfo('📍 Driver is within 100m of destination - triggering arrival');
          // Cancel the timer immediately
          timer.cancel();
          _arrivalCheckTimer = null;
          // Mark as arrived to stop all route refreshes
          hasArrived = true;
          _hasArrivedAndSessionEnded = true;
          // Stop all route recalculation
          routeRecalculationTimer?.cancel();
          routeRecalculationTimer = null;
          isRecalculatingRoute = false;
          // Update UI
          onMapUpdated?.call();
          _logInfo('✅ Route refresh stopped - destination reached');
        }
      }
    });
  }

  // ============================================================
  // CLEAR ROUTE - ENHANCED WITH SESSION
  // ============================================================
  void clearRoute() {
    _logInfo('Clearing route');
    polylines.clear();
    currentRoutePoints.clear();
    routeSteps.clear();
    isNavigating = false;
    currentStepIndex = 0;
    alternativeRoutes.clear();
    alternativeDurations.clear();
    selectedRouteIndex = 0;
    trafficSegments.clear();
    
    // Clear lazy step loader
    _lazyStepLoader?.clear();
    _lazyStepLoader = null;
    
    // Cancel arrival listener when route is cleared
    _arrivalCheckTimer?.cancel();
    _arrivalCheckTimer = null;
    
    if (!_isSessionActive) {
      _navigationInitialized = false;
      _hasAnnouncedStartingNavigation = false;
      _isInitializingNavigation = false;
    }
    hasArrived = false;

    if (_isSessionActive) {
      endNavigationSession(cancelled: true);
    }

    onMapUpdated?.call();
  }

  // ============================================================
  // ADDED: Off-route purple route to guide driver back
  // ============================================================
  void _showOffRoutePurpleGuidance(LatLng driverPosition) {
    if (customerLocation == null) return;
    
    // Remove any existing off-route purple polyline
    polylines.removeWhere((polyline) => 
      polyline.polylineId.value == 'off_route_purple_guide'
    );
    
    // Draw a purple route from driver's current position to customer
    // This is a direct route showing the driver how to get back
    polylines.add(
      Polyline(
        polylineId: const PolylineId('off_route_purple_guide'),
        points: [driverPosition, customerLocation!],
        color: Colors.purple,
        width: 8,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        patterns: [PatternItem.dash(15), PatternItem.gap(10)],
      ),
    );
    
    // Add a label polyline with instruction
    polylines.add(
      Polyline(
        polylineId: const PolylineId('off_route_purple_instruction'),
        points: [
          LatLng(
            (driverPosition.latitude + customerLocation!.latitude) / 2,
            (driverPosition.longitude + customerLocation!.longitude) / 2
          ),
          LatLng(
            (driverPosition.latitude + customerLocation!.latitude) / 2 + 0.0001,
            (driverPosition.longitude + customerLocation!.longitude) / 2
          )
        ],
        color: Colors.purple.shade300,
        width: 2,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    );
    
    // Speak guidance
    speak('You are off-route. Follow the purple route to return to your destination.');
    onTurnAlert?.call('🟣 Off-route! Follow purple route back to client', 'warning');
    
    onMapUpdated?.call();
  }

  // ============================================================
  // RECALCULATE ROUTE - ENHANCED WITH ARRIVAL CHECK AND PURPLE GUIDANCE
  // ============================================================
  void recalculateRouteIfNeeded(LatLng driverPosition, String vehicleType, String numberPlate) {
    // If arrived, do NOT recalculate
    if (hasArrived || _hasArrivedAndSessionEnded) {
      return;
    }
    
    if (!_navigationInitialized) {
      return;
    }
    
    if (routeRecalculationTimer != null && routeRecalculationTimer!.isActive) {
      return;
    }
    if (isRecalculatingRoute) return;
    if (currentRoutePoints.isEmpty) return;

    // Check if driver is off-route
    final bool isOffRoute = _shouldRecalculateRoute(driverPosition, currentRoutePoints);
    
    if (isOffRoute) {
      // Show purple guidance route to help driver get back on track
      _showOffRoutePurpleGuidance(driverPosition);
      
      _logInfo('🔄 Driver is off-route, showing purple guidance and recalculating...');
      isRecalculatingRoute = true;
      _startTimer('routeRecalculation');

      if (_isSessionActive) {
        updateSessionProgress();
      }

      routeRecalculationTimer = Timer(const Duration(seconds: 3), () async {
        // Double-check arrival before recalculating
        if (hasArrived || _hasArrivedAndSessionEnded) {
          isRecalculatingRoute = false;
          _logInfo('⏹️ Skip recalculation - already arrived');
          return;
        }
        
        if (driverLocation != null && customerLocation != null) {
          final origin = driverLocation!;
          final destination = customerLocation!;

          final result = await _withRetry(
            () => getRouteWithDetails(origin, destination, getAlternatives: true),
            operationName: 'Route recalculation',
          );
          final points = result['points'] as List<LatLng>;
          final duration = result['duration'] as Duration?;
          final normalDuration = result['normalDuration'] as Duration?;
          final durationText = result['durationText'] as String?;
          final steps = result['steps'] as List<NavigationStep>;
          final alternatives = result['alternatives'] as List<List<LatLng>>? ?? [];
          final altDurations = result['alternativeDurations'] as List<Duration>? ?? [];

          if (points.isNotEmpty) {
            // Remove purple guidance since driver is back on route
            polylines.removeWhere((polyline) => 
              polyline.polylineId.value == 'off_route_purple_guide' ||
              polyline.polylineId.value == 'off_route_purple_instruction'
            );
            
            // Downsample recalculated route
            currentRoutePoints = _downsampleRoutePoints(points);
            lastRouteOrigin = origin;
            lastRouteDestination = destination;
            actualTravelDuration = duration;
            normalTravelDuration = normalDuration;
            travelDurationText = durationText;
            useActualEta = duration != null;
            alternativeRoutes = alternatives;
            alternativeDurations = altDurations;
            selectedRouteIndex = 0;

            polylines = _buildPolylinesWithTraffic(currentRoutePoints);
            polylines.addAll(_buildAlternativePolylines(alternatives));

            if (steps.isNotEmpty) {
              routeSteps = steps;
              _lazyStepLoader = LazyStepLoader(steps);
              if (_isSessionActive && !_navigationInitialized) {
                _initializeNavigation();
                updateSessionState(NavigationSessionState.navigating);
              } else if (!_navigationInitialized) {
                initializeTurnByTurnNavigation();
              } else {
                _updateCurrentStepInfo();
              }
            }

            if (duration != null) {
              estimatedMinutes = duration.inMinutes > 0 ? duration.inMinutes : 1;
            }

            speak('Route recalculated. You are back on track.');
            onMapUpdated?.call();
            _logInfo('✅ Route recalculated successfully');
          } else {
            _logWarning('Route recalculation failed - no points returned');
          }
        }
        isRecalculatingRoute = false;
        _stopTimer('routeRecalculation');
      });
    }
  }

  // ============================================================
  // HANDLE ARRIVAL - PREVENT DUPLICATES
  // ============================================================
  void _handleArrival() {
    if (hasArrived || _hasArrivedAndSessionEnded) {
      _logWarning('Arrival already handled, skipping...');
      return;
    }
    
    _startTimer('arrivalDetection');
    _logInfo('✅ Driver has arrived at destination');
    hasArrived = true;
    _hasArrivedAndSessionEnded = true;
    
    // Cancel arrival listener on arrival
    _arrivalCheckTimer?.cancel();
    _arrivalCheckTimer = null;
    
    speak('You have arrived at your destination.');
    onTurnAlert?.call('📍 You have arrived!', 'success');
    showNavigationBanner = false;
    isCameraFollowing = false;

    if (_isSessionActive) {
      endNavigationSession(cancelled: false);
    }

    if (mapController != null) {
      try {
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: driverLocation ?? customerLocation!,
              zoom: 16,
              tilt: 0,
            ),
          ),
        );
      } catch (e) {
        // Ignore - controller may be disposed
      }
    }

    onMapUpdated?.call();
    _stopTimer('arrivalDetection');
  }

  // ============================================================
  // INITIALIZE TURN-BY-TURN NAVIGATION - PREVENT DUPLICATES
  // ============================================================
  void initializeTurnByTurnNavigation() {
    if (_navigationInitialized && isNavigating) {
      _logWarning('Navigation already initialized, skipping duplicate init');
      _updateCurrentStepInfo();
      return;
    }

    currentStepIndex = 0;
    isNavigating = routeSteps.isNotEmpty;
    hasAnnouncedCurrentStep = false;
    lastAnnouncementDistance = -1;
    announcementQueue.clear();

    // Initialize lazy step loader
    if (routeSteps.isNotEmpty) {
      _lazyStepLoader = LazyStepLoader(routeSteps);
    }

    if (routeSteps.isNotEmpty) {
      _updateCurrentStepInfo();

      if (!_navigationInitialized && !_hasAnnouncedStartingNavigation) {
        _navigationInitialized = true;
        _hasAnnouncedStartingNavigation = true;
        
        final totalDistance = routeSteps.fold(0.0, (sum, step) => sum + step.distance);
        final totalTime = routeSteps.fold(Duration.zero, (sum, step) => sum + step.duration);
        
        if (totalDistance > 10) {
          speak('Starting navigation. Total distance ${_formatDistance(totalDistance)}, approximately ${totalTime.inMinutes} minutes.');
        } else {
          speak('Starting navigation to nearby destination.');
        }

        final firstStep = routeSteps[0];
        _speakInstruction(firstStep);
        _logInfo('"Starting navigation" spoken once');
      } else if (_navigationInitialized && _hasAnnouncedStartingNavigation) {
        final firstStep = routeSteps[0];
        _speakInstruction(firstStep);
      } else {
        _navigationInitialized = true;
        _hasAnnouncedStartingNavigation = true;
        final firstStep = routeSteps[0];
        _speakInstruction(firstStep);
      }
    }

    showNavigationBanner = routeSteps.isNotEmpty;
    bannerProgress = 0.0;

    turnAlertTimer?.cancel();
    turnAlertTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkTurnAlerts();
    });
  }

  // ============================================================
  // ORIGINAL METHODS - PRESERVED
  // ============================================================

  // ============================================================
  // FIREBASE LOCATION METHODS
  // ============================================================
  void initializeFirestoreListener(String driverId) {
    this.driverId = driverId;
    driverLocationRef = firestore.collection('drivers').doc(driverId);
    driverLocationRef!.snapshots(
      includeMetadataChanges: false,
    ).listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>?;
        if (data == null) return;
        if (data['position'] is GeoPoint) {
          final geoPoint = data['position'] as GeoPoint;
          final position = LatLng(geoPoint.latitude, geoPoint.longitude);
          final heading = (data['heading'] as double?) ?? 0.0;
          final speed = (data['speed'] as double?) ?? 0.0;
          _processRemoteLocationUpdate(position, heading, speed);
        } else if (data['position'] is Map) {
          final pos = data['position'] as Map<String, dynamic>;
          final position = LatLng(
            (pos['lat'] as num).toDouble(),
            (pos['lng'] as num).toDouble(),
          );
          final heading = (data['heading'] as double?) ?? 0.0;
          final speed = (data['speed'] as double?) ?? 0.0;
          _processRemoteLocationUpdate(position, heading, speed);
        }
      }
    }, onError: (error) {
      _logError('Firestore listener error', details: {'error': error.toString()});
    });
  }

  void _processRemoteLocationUpdate(LatLng position, double heading, double speed) {
    if (driverId != null && _currentVehicleType != null && _currentNumberPlate != null) {
      bool isMoving = speed > 2.0;
      updateAnimatedDriver(
        driverId: driverId!,
        position: position,
        heading: heading,
        speed: speed,
        vehicleType: _currentVehicleType!,
        numberPlate: _currentNumberPlate!,
        isMoving: isMoving,
      );
    }
    _handleLocationUpdate(position, heading, speed);
  }

  Future<void> sendLocationToFirestore({
    required LatLng position,
    required double heading,
    required double speed,
    bool force = false,
  }) async {
    if (driverLocationRef == null) return;

    final now = DateTime.now();
    if (!force) {
      if (lastSentPosition != null) {
        final distance = Geolocator.distanceBetween(
          lastSentPosition!.latitude,
          lastSentPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        // Skip if moved less than 10 meters
        if (distance < 10.0) return;
      }
      if (lastFirestoreUpdateTime != null) {
        final elapsed = now.difference(lastFirestoreUpdateTime!);
        if (elapsed < minTimeThreshold) {
          _queueFirestoreUpdate(position, heading, speed);
          return;
        }
      }
    }
    await _sendLocationUpdate(position, heading, speed);
  }

  void _queueFirestoreUpdate(LatLng position, double heading, double speed) {
    queuedPosition = position;
    queuedHeading = heading;
    queuedSpeed = speed;
    isFirestoreUpdateQueued = true;
    firestoreDebounceTimer?.cancel();
    firestoreDebounceTimer = Timer(minTimeThreshold, () {
      if (isFirestoreUpdateQueued && queuedPosition != null) {
        _sendLocationUpdate(
          queuedPosition!,
          queuedHeading ?? 0.0,
          queuedSpeed ?? 0.0,
        );
        isFirestoreUpdateQueued = false;
        queuedPosition = null;
        queuedHeading = null;
        queuedSpeed = null;
      }
    });
  }

  Future<void> _sendLocationUpdate(LatLng position, double heading, double speed) async {
    if (driverLocationRef == null) return;
    try {
      final now = DateTime.now();
      // Use batch manager for location updates
      _batchManager.addUpdate(
        driverLocationRef!.path,
        {
          'position': {
            'lat': position.latitude,
            'lng': position.longitude,
          },
          'heading': heading,
          'speed': speed,
          'timestamp': FieldValue.serverTimestamp(),
          'updatedAt': now.toIso8601String(),
        }
      );
      lastSentPosition = position;
      lastFirestoreUpdateTime = now;
      isFirestoreUpdateQueued = false;
      _logInfo('Firestore update queued: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      _logError('Error sending location to Firestore', details: {'error': e.toString()});
    }
  }

  Future<void> forceFirestoreUpdate({
    required LatLng position,
    required double heading,
    required double speed,
  }) async {
    await sendLocationToFirestore(
      position: position,
      heading: heading,
      speed: speed,
      force: true,
    );
  }

  Map<String, dynamic> getFirestoreStats() {
    return {
      'lastSentPosition': lastSentPosition,
      'minDistanceThreshold': minDistanceThreshold,
      'minTimeThreshold': minTimeThreshold.inSeconds,
      'lastUpdateTime': lastFirestoreUpdateTime?.toIso8601String(),
      'isQueued': isFirestoreUpdateQueued,
      'queuedPosition': queuedPosition,
      'batchSize': _batchManager._batch.length,
    };
  }

  // ============================================================
  // UPDATE MAP PADDING
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
  // VEHICLE MARKER - WITH OPTIMIZED CACHING
  // ============================================================
  Future<BitmapDescriptor> _getVehicleMarker(String vehicleType, {double bearing = 0}) async {
    _startTimer('markerGeneration');
    final smoothBearing = _smoothBearing(bearing);
    final String key = 'car_${vehicleType}_${smoothBearing.round()}_${carWidth.round()}_${carHeight.round()}';
    
    if (markerCache.containsKey(key)) {
      _stopTimer('markerGeneration');
      return markerCache[key]!;
    }
    
    try {
      final ByteData? data = await rootBundle.load('assets/car3.png');
      if (data == null) {
        final marker = await _createEmojiFallback(vehicleType);
        markerCache[key] = marker;
        _stopTimer('markerGeneration');
        return marker;
      }
      
      final int width = carWidth.toInt();
      final int height = carHeight.toInt();
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;
      
      final stretchRecorder = ui.PictureRecorder();
      final stretchCanvas = Canvas(stretchRecorder);
      stretchCanvas.drawImageRect(
        originalImage,
        Rect.fromLTWH(0, 0, originalImage.width.toDouble(), originalImage.height.toDouble()),
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint(),
      );
      final stretchedImage = await stretchRecorder.endRecording().toImage(width, height);
      
      final rotateRecorder = ui.PictureRecorder();
      final rotateCanvas = Canvas(rotateRecorder);
      rotateCanvas.save();
      rotateCanvas.translate(width / 2, height / 2);
      rotateCanvas.rotate(smoothBearing * pi / 180);
      rotateCanvas.translate(-width / 2, -height / 2);
      rotateCanvas.drawImage(stretchedImage, Offset(0, 0), Paint());
      rotateCanvas.restore();
      
      final finalImage = await rotateRecorder.endRecording().toImage(width, height);
      final ByteData? imageData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      if (imageData == null) {
        final marker = await _createEmojiFallback(vehicleType);
        markerCache[key] = marker;
        _stopTimer('markerGeneration');
        return marker;
      }
      
      final marker = BitmapDescriptor.fromBytes(imageData.buffer.asUint8List());
      markerCache[key] = marker;
      _stopTimer('markerGeneration');
      return marker;
    } catch (e) {
      _logWarning('Error loading car3.png, using emoji fallback', details: {'error': e.toString()});
      final marker = await _createEmojiFallback(vehicleType);
      markerCache[key] = marker;
      _stopTimer('markerGeneration');
      return marker;
    }
  }

  double _smoothBearing(double bearing) {
    if (headingHistory.isEmpty) {
      headingHistory.add(bearing);
      return bearing;
    }
    headingHistory.add(bearing);
    if (headingHistory.length > maxHeadingHistory) {
      headingHistory.removeAt(0);
    }
    double sum = 0;
    double weight = 1;
    for (int i = headingHistory.length - 1; i >= 0; i--) {
      sum += headingHistory[i] * weight;
      weight *= 0.7;
    }
    final smooth = sum / headingHistory.fold(0, (a, b) => a + 1);
    return smooth % 360;
  }

  Future<BitmapDescriptor> _createEmojiFallback(String vehicleType) async {
    final String key = 'emoji_$vehicleType';
    if (markerCache.containsKey(key)) return markerCache[key]!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    Color color;
    switch (vehicleType.toLowerCase()) {
      case 'small':
        color = Colors.orange;
        break;
      case 'medium':
      case 'fuel truck':
        color = Colors.blue;
        break;
      case 'large':
      case 'big':
        color = Colors.green;
        break;
      default:
        color = Colors.blue;
    }
    canvas.drawCircle(const Offset(40, 40), 36, Paint()..color = color);
    canvas.drawCircle(const Offset(40, 40), 36, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 4);
    final emoji = _getVehicleIcon(vehicleType);
    final painter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold)
      ),
      textDirection: TextDirection.ltr
    );
    painter.layout();
    painter.paint(canvas, Offset(40 - painter.width / 2, 40 - painter.height / 2));
    final img = await recorder.endRecording().toImage(80, 80);
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return BitmapDescriptor.defaultMarker;
    final marker = BitmapDescriptor.fromBytes(data.buffer.asUint8List());
    markerCache[key] = marker;
    return marker;
  }

  String _getVehicleIcon(String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case 'small':
        return '🚗';
      case 'medium':
      case 'fuel truck':
        return '🚚';
      case 'large':
      case 'big':
        return '🚛';
      default:
        return '🚚';
    }
  }

  // ============================================================
  // UPDATE DRIVER MARKER
  // ============================================================
  Future<void> updateDriverMarker(String vehicleType, String numberPlate) async {
    if (driverLocation == null) return;
    _currentVehicleType = vehicleType;
    _currentNumberPlate = numberPlate;
    try {
      final markerIcon = await _getVehicleMarker(
        vehicleType.toLowerCase(),
        bearing: currentHeading
      );
      mapMarkers.removeWhere((marker) => marker.markerId.value == 'driver');
      mapMarkers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverLocation!,
          icon: markerIcon,
          rotation: currentHeading,
          anchor: const Offset(0.5, 0.9),
          flat: true,
          infoWindow: InfoWindow(
            title: '🚗 Your Location',
            snippet: '$vehicleType • $numberPlate • ${currentSpeed.toStringAsFixed(0)} km/h',
          ),
        ),
      );
      if (driverId != null) {
        bool isMoving = currentSpeed > 2.0;
        updateAnimatedDriver(
          driverId: driverId!,
          position: driverLocation!,
          heading: currentHeading,
          speed: currentSpeed,
          vehicleType: vehicleType,
          numberPlate: numberPlate,
          isMoving: isMoving,
        );
      }
      onMapUpdated?.call();
    } catch (e) {
      _logError('Error updating driver marker', details: {'error': e.toString()});
    }
  }

  void updateDriverMarkerWithInterpolation(String vehicleType, String numberPlate) {
    if (driverLocation == null) return;
    _currentVehicleType = vehicleType;
    _currentNumberPlate = numberPlate;
    _getVehicleMarker(vehicleType.toLowerCase(), bearing: currentHeading).then((markerIcon) {
      mapMarkers.removeWhere((marker) => marker.markerId.value == 'driver');
      mapMarkers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverLocation!,
          icon: markerIcon,
          rotation: currentHeading,
          anchor: const Offset(0.5, 0.9),
          flat: true,
          infoWindow: InfoWindow(
            title: '🚗 Your Location',
            snippet: '$vehicleType • $numberPlate • ${currentSpeed.toStringAsFixed(0)} km/h',
          ),
        ),
      );
      if (driverId != null) {
        bool isMoving = currentSpeed > 2.0;
        updateAnimatedDriver(
          driverId: driverId!,
          position: driverLocation!,
          heading: currentHeading,
          speed: currentSpeed,
          vehicleType: vehicleType,
          numberPlate: numberPlate,
          isMoving: isMoving,
        );
      }
      onMapUpdated?.call();
    });
  }

  void forceUpdateMarker(String vehicleType, String numberPlate) {
    if (driverLocation == null) return;
    _currentVehicleType = vehicleType;
    _currentNumberPlate = numberPlate;
    _getVehicleMarker(vehicleType.toLowerCase(), bearing: currentHeading).then((markerIcon) {
      mapMarkers.removeWhere((marker) => marker.markerId.value == 'driver');
      mapMarkers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverLocation!,
          icon: markerIcon,
          rotation: currentHeading,
          anchor: const Offset(0.5, 0.9),
          flat: true,
          infoWindow: InfoWindow(
            title: '🚗 Your Location',
            snippet: '$vehicleType • $numberPlate • ${currentSpeed.toStringAsFixed(0)} km/h',
          ),
        ),
      );
      if (driverId != null) {
        bool isMoving = currentSpeed > 2.0;
        updateAnimatedDriver(
          driverId: driverId!,
          position: driverLocation!,
          heading: currentHeading,
          speed: currentSpeed,
          vehicleType: vehicleType,
          numberPlate: numberPlate,
          isMoving: isMoving,
        );
      }
      onMapUpdated?.call();
    });
    _updateCameraPosition();
  }

  // ============================================================
  // SET CUSTOMER MARKER
  // ============================================================
  void setCustomerMarker(LatLng location) {
    customerLocation = location;
    mapMarkers.removeWhere((marker) => marker.markerId.value == 'customer');
    mapMarkers.add(
      Marker(
        markerId: const MarkerId('customer'),
        position: location,
        infoWindow: const InfoWindow(title: '📍 Customer Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );
    onMapUpdated?.call();
  }

  // ============================================================
  // CLEAR MARKERS
  // ============================================================
  void clearMarkers() {
    mapMarkers.clear();
    animatedMarkers.clear();
    _animatedDrivers.clear();
    _driverPaths.clear();
    _staticDrivers.clear();
    _markerPool.clear();
    onMapUpdated?.call();
  }

  // ============================================================
  // GOOGLE DIRECTIONS API - UPDATED WITH HOME_MAP LOGIC
  // ============================================================
  Future<Map<String, dynamic>> getRouteWithDetails(
    LatLng origin,
    LatLng destination, {
    bool getAlternatives = true
  }) async {
    try {
      String url = 'https://maps.googleapis.com/maps/api/directions/json'
          '?origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&key=$googleAPIKey'
          '&departure_time=now'
          '&traffic_model=best_guess';
      
      if (getAlternatives) {
        url += '&alternatives=true';
      }
      
      _logInfo('Fetching route from: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _logError('Route request timed out');
          return http.Response('{"status":"TIMEOUT"}', 408);
        },
      );
      
      _logInfo('Route response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'OK') {
          _logInfo('Route found!');
          return _parseRouteResponse(data, getAlternatives);
        } else if (data['status'] == 'ZERO_RESULTS') {
          _logWarning('No route found between these points');
          return _emptyRouteResponse();
        } else if (data['status'] == 'OVER_QUERY_LIMIT') {
          _logWarning('API Query Limit Exceeded');
          return _emptyRouteResponse();
        } else if (data['status'] == 'REQUEST_DENIED') {
          _logError('⚠️ API KEY ERROR: ${data['error_message']}');
          _showApiKeyError();
          return _emptyRouteResponse();
        } else {
          _logWarning('API Error: ${data['status']} - ${data['error_message'] ?? 'No message'}');
          return _emptyRouteResponse();
        }
      } else if (response.statusCode == 403) {
        _logError('⚠️ 403 Forbidden - API Key issue or billing not enabled');
        _showApiKeyError();
        return _emptyRouteResponse();
      } else {
        _logWarning('HTTP Error: ${response.statusCode}');
        return _emptyRouteResponse();
      }
    } catch (e) {
      _logError('Route fetch error', details: {'error': e.toString()});
      return _emptyRouteResponse();
    }
  }

  void _showApiKeyError() {
    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Google Maps API Error. Please check API key and billing.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Map<String, dynamic> _parseRouteResponse(Map<String, dynamic> data, bool getAlternatives) {
    try {
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        _logWarning('No routes found in response');
        return _emptyRouteResponse();
      }
      
      final mainRoute = routes[0] as Map<String, dynamic>?;
      if (mainRoute == null) {
        _logWarning('Main route is null');
        return _emptyRouteResponse();
      }
      
      // Safely get overview polyline
      final overviewPolyline = mainRoute['overview_polyline'] as Map<String, dynamic>?;
      if (overviewPolyline == null) {
        _logWarning('No overview polyline found');
        return _emptyRouteResponse();
      }
      
      final polylinePoints = overviewPolyline['points'] as String?;
      if (polylinePoints == null || polylinePoints.isEmpty) {
        _logWarning('No polyline points found');
        return _emptyRouteResponse();
      }
      
      final points = _decodePolyline(polylinePoints);
      if (points.isEmpty) {
        _logWarning('Decoded polyline is empty');
        return _emptyRouteResponse();
      }
      
      Duration? travelDuration;
      Duration? normalDuration;
      String? durationText;
      List<NavigationStep> steps = [];
      
      final legs = mainRoute['legs'] as List?;
      if (legs != null && legs.isNotEmpty) {
        final leg = legs[0] as Map<String, dynamic>?;
        if (leg != null) {
          // Safely get duration
          final duration = leg['duration'] as Map<String, dynamic>?;
          if (duration != null) {
            final seconds = duration['value'] as int?;
            if (seconds != null) {
              normalDuration = Duration(seconds: seconds);
            }
          }
          
          // Safely get duration in traffic
          final durationInTraffic = leg['duration_in_traffic'] as Map<String, dynamic>?;
          if (durationInTraffic != null) {
            final seconds = durationInTraffic['value'] as int?;
            if (seconds != null) {
              travelDuration = Duration(seconds: seconds);
              durationText = durationInTraffic['text'] as String?;
            }
          } else if (duration != null) {
            final seconds = duration['value'] as int?;
            if (seconds != null) {
              travelDuration = Duration(seconds: seconds);
              durationText = duration['text'] as String?;
            }
          }
          
          // Safely parse steps
          final legSteps = leg['steps'] as List?;
          if (legSteps != null) {
            for (int i = 0; i < legSteps.length; i++) {
              final step = legSteps[i] as Map<String, dynamic>?;
              if (step == null) continue;
              
              final stepPolyline = step['polyline'] as Map<String, dynamic>?;
              if (stepPolyline == null) continue;
              
              final stepPointsStr = stepPolyline['points'] as String?;
              if (stepPointsStr == null) continue;
              
              final stepPoints = _decodePolyline(stepPointsStr);
              if (stepPoints.isEmpty) continue;
              
              final instruction = (step['html_instructions'] ?? step['instructions'] ?? 'Continue') as String;
              
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
                startHeading = _calculateBearing(
                  stepPoints[0],
                  stepPoints[min(1, stepPoints.length - 1)]
                );
                endHeading = _calculateBearing(
                  stepPoints[max(0, stepPoints.length - 2)],
                  stepPoints.last
                );
              }
              
              if (i < legSteps.length - 1) {
                final nextStep = legSteps[i + 1] as Map<String, dynamic>?;
                if (nextStep != null) {
                  final nextPolyline = nextStep['polyline'] as Map<String, dynamic>?;
                  if (nextPolyline != null) {
                    final nextPointsStr = nextPolyline['points'] as String?;
                    if (nextPointsStr != null) {
                      final nextStepPoints = _decodePolyline(nextPointsStr);
                      if (nextStepPoints.length >= 2) {
                        double nextStartHeading = _calculateBearing(
                          nextStepPoints[0],
                          nextStepPoints[min(1, nextStepPoints.length - 1)]
                        );
                        
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
                    }
                  }
                }
              }
              
              if (instruction.toLowerCase().contains('turn left') || instruction.toLowerCase().contains('turn-left')) {
                maneuver = 'turn-left';
              } else if (instruction.toLowerCase().contains('turn right') || instruction.toLowerCase().contains('turn-right')) {
                maneuver = 'turn-right';
              }
              
              List<LaneInfo> lanes = _getLaneInfo(maneuver);
              
              final stepDuration = step['duration'] as Map<String, dynamic>?;
              Duration stepDurationObj = Duration.zero;
              String stepDurationText = '';
              if (stepDuration != null) {
                final seconds = stepDuration['value'] as int?;
                if (seconds != null) {
                  stepDurationObj = Duration(seconds: seconds);
                }
                stepDurationText = stepDuration['text'] as String? ?? '';
              }
              
              final stepDistance = step['distance'] as Map<String, dynamic>?;
              double stepDistanceVal = 0;
              String stepDistanceText = '';
              if (stepDistance != null) {
                stepDistanceVal = (stepDistance['value'] as int? ?? 0).toDouble();
                stepDistanceText = stepDistance['text'] as String? ?? '';
              }
              
              steps.add(NavigationStep(
                instruction: instruction.replaceAll(RegExp(r'<[^>]*>'), ''),
                maneuver: maneuver,
                distance: stepDistanceVal,
                distanceText: stepDistanceText,
                duration: stepDurationObj,
                durationText: stepDurationText,
                startLocation: LatLng(
                  step['start_location']['lat'] as double? ?? 0,
                  step['start_location']['lng'] as double? ?? 0,
                ),
                endLocation: LatLng(
                  step['end_location']['lat'] as double? ?? 0,
                  step['end_location']['lng'] as double? ?? 0,
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
      }
      
      List<List<LatLng>> alternatives = [];
      List<Duration> altDurations = [];
      if (getAlternatives && routes.length > 1) {
        for (int i = 1; i < routes.length && i < 3; i++) {
          final route = routes[i] as Map<String, dynamic>?;
          if (route == null) continue;
          
          final altOverview = route['overview_polyline'] as Map<String, dynamic>?;
          if (altOverview == null) continue;
          
          final altPointsStr = altOverview['points'] as String?;
          if (altPointsStr == null) continue;
          
          final altPoints = _decodePolyline(altPointsStr);
          alternatives.add(altPoints);
          
          final altLegs = route['legs'] as List?;
          if (altLegs != null && altLegs.isNotEmpty) {
            final altLeg = altLegs[0] as Map<String, dynamic>?;
            if (altLeg != null) {
              final altDuration = altLeg['duration'] as Map<String, dynamic>?;
              if (altDuration != null) {
                final seconds = altDuration['value'] as int?;
                if (seconds != null) {
                  altDurations.add(Duration(seconds: seconds));
                }
              }
            }
          }
        }
      }
      
      return {
        'points': points,
        'duration': travelDuration,
        'normalDuration': normalDuration,
        'durationText': durationText,
        'steps': steps,
        'alternatives': alternatives,
        'alternativeDurations': altDurations,
      };
    } catch (e) {
      _logError('Error parsing route', details: {'error': e.toString()});
      return _emptyRouteResponse();
    }
  }

  Map<String, dynamic> _emptyRouteResponse() {
    return {
      'points': [],
      'duration': null,
      'normalDuration': null,
      'durationText': null,
      'steps': [],
      'alternatives': [],
      'alternativeDurations': [],
    };
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
  // GET LANE INFO
  // ============================================================
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
      case 'turn-sharp-left':
        return [
          LaneInfo(left: true, straight: false, right: false, recommended: true, label: '←'),
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
        ];
      case 'turn-sharp-right':
        return [
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
          LaneInfo(left: false, straight: false, right: true, recommended: true, label: '→'),
        ];
      case 'turn-slight-left':
        return [
          LaneInfo(left: true, straight: false, right: false, recommended: true, label: '↖'),
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
        ];
      case 'turn-slight-right':
        return [
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
          LaneInfo(left: false, straight: false, right: true, recommended: true, label: '↗'),
        ];
      default:
        return [
          LaneInfo(left: false, straight: true, right: false, recommended: true, label: '↑'),
          LaneInfo(left: false, straight: true, right: false, label: '↑'),
        ];
    }
  }

  // ============================================================
  // OPTIMIZATION: Efficient Polyline Building
  // ============================================================
  Set<Polyline> _buildPolylinesWithTraffic(List<LatLng> points, {Color? trafficColor}) {
    final color = trafficColor ?? currentTrafficColor;
    final polylines = <Polyline>{};
    
    // Simplify points for better performance
    final simplifiedPoints = _downsampleRoutePoints(points, tolerance: 0.00005);
    
    polylines.add(
      Polyline(
        polylineId: const PolylineId('driver_route_shadow'),
        points: simplifiedPoints,
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
        points: simplifiedPoints,
        color: color,
        width: 16,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    );
    polylines.add(
      Polyline(
        polylineId: const PolylineId('driver_route_border'),
        points: simplifiedPoints,
        color: Colors.white.withOpacity(0.3),
        width: 20,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    );
    polylines.add(
      Polyline(
        polylineId: const PolylineId('driver_route_center'),
        points: simplifiedPoints,
        color: Colors.white.withOpacity(0.15),
        width: 3,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        patterns: [PatternItem.dash(20), PatternItem.gap(15)],
      ),
    );
    return polylines;
  }

  Set<Polyline> _buildTrafficSegmentedRoute(
    List<LatLng> points,
    List<Map<String, dynamic>> trafficData
  ) {
    final result = <Polyline>{};
    for (int i = 0; i < trafficData.length; i++) {
      final segment = trafficData[i];
      final segmentPoints = segment['points'] as List<LatLng>;
      // Simplify segment points
      final simplified = _downsampleRoutePoints(segmentPoints, tolerance: 0.00005);
      final color = segment['color'] as Color? ?? Colors.green;
      result.add(
        Polyline(
          polylineId: PolylineId('traffic_segment_$i'),
          points: simplified,
          color: color,
          width: 18,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }
    return result;
  }

  Set<Polyline> _buildPolylines(List<LatLng> points) {
    return _buildPolylinesWithTraffic(points);
  }

  Set<Polyline> _buildFallbackRoute(LatLng origin, LatLng destination) {
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [origin, destination],
        color: const Color(0xFF1A73E8),
        width: 16,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  // ============================================================
  // BUILD ALTERNATIVE POLYLINES - CHANGED GRAY TO BLACK DASHED
  // ============================================================
  Set<Polyline> _buildAlternativePolylines(List<List<LatLng>> alternatives) {
    final result = <Polyline>{};
    for (int i = 0; i < alternatives.length; i++) {
      final altPoints = alternatives[i];
      if (altPoints.isEmpty) continue;
      // Simplify alternative route points
      final simplified = _downsampleRoutePoints(altPoints, tolerance: 0.0001);
      final isSelected = (i == selectedRouteIndex - 1);
      result.add(
        Polyline(
          polylineId: PolylineId('alternative_$i'),
          points: simplified,
          color: isSelected ? const Color(0xFF1A73E8) : Colors.black.withOpacity(0.6),
          width: isSelected ? 14 : 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          patterns: isSelected ? [] : [PatternItem.dash(20), PatternItem.gap(10)],
        ),
      );
    }
    return result;
  }

  // ============================================================
  // SELECT ALTERNATIVE ROUTE - Updated to remove purple guidance
  // ============================================================
  void selectAlternativeRoute(int index) {
    if (!getFeature('alternativeRoutes')) {
      _logWarning('Alternative routes feature is disabled');
      return;
    }
    if (index < 0 || index > alternativeRoutes.length) return;
    selectedRouteIndex = index + 1;
    if (index < alternativeRoutes.length) {
      final altPoints = alternativeRoutes[index];
      if (altPoints.isNotEmpty) {
        // Remove purple guidance when selecting alternative
        polylines.removeWhere((polyline) => 
          polyline.polylineId.value == 'off_route_purple_guide' ||
          polyline.polylineId.value == 'off_route_purple_instruction'
        );
        
        currentRoutePoints = altPoints;
        polylines = _buildPolylinesWithTraffic(altPoints);
        polylines.addAll(_buildAlternativePolylines(alternativeRoutes));
        if (index < alternativeDurations.length) {
          final altDuration = alternativeDurations[index];
          estimatedMinutes = altDuration.inMinutes > 0 ? altDuration.inMinutes : 1;
        }
        onMapUpdated?.call();
        speak('Switched to alternative route.');
      }
    }
  }

  // ============================================================
  // TURN-BY-TURN NAVIGATION HELPERS
  // ============================================================
  void _speakInstruction(NavigationStep step) {
    final maneuverText = _getManeuverText(step.maneuver);
    final roadText = step.roadName.isNotEmpty ? ' on ${step.roadName}' : '';
    final distanceText = _formatDistance(step.distance);
    String voiceText;
    if (step.maneuver == 'straight' || step.maneuver == 'continue') {
      voiceText = 'Continue$roadText for $distanceText';
    } else {
      voiceText = '$maneuverText$roadText, $distanceText';
    }
    speak(voiceText);
    bannerInstruction = step.instruction;
    bannerManeuver = _getManeuverIcon(step.maneuver);
    bannerDistance = step.distanceText;
    bannerNextRoad = step.roadShield.isNotEmpty ? step.roadShield : step.roadName;
    bannerCurrentRoad = currentStepIndex > 0 ? routeSteps[currentStepIndex - 1].roadName : '';
    bannerSubInstruction = '${step.durationText} • ${step.roadName.isNotEmpty ? step.roadName : 'Current road'}';
    bannerProgress = currentStepIndex / (routeSteps.length > 0 ? routeSteps.length : 1);
    onMapUpdated?.call();
  }

  void _updateCurrentStepInfo() {
    if (currentStepIndex < routeSteps.length) {
      final step = routeSteps[currentStepIndex];
      laneGuidance = step.lanes;
      laneGuidanceText = laneGuidance.map((l) => l.displayChar).join(' ');
      if (step.roadShield.isNotEmpty) {
        roadShields[step.roadName] = step.roadShield;
      }
      nextInstruction = step.instruction;
      nextManeuver = step.maneuver;
      nextStepDistance = step.distance;
      nextRoadHeading = step.startHeading;
      bannerCurrentRoad = currentStepIndex > 0 ? routeSteps[currentStepIndex - 1].roadName : '';
      bannerNextRoad = step.roadShield.isNotEmpty ? step.roadShield : step.roadName;
      bannerInstruction = step.instruction;
      bannerManeuver = _getManeuverIcon(step.maneuver);
      bannerDistance = step.distanceText;
      bannerProgress = currentStepIndex / (routeSteps.length > 0 ? routeSteps.length : 1);
      onMapUpdated?.call();
    }
  }

  // ============================================================
  // CHECK TURN ALERTS
  // ============================================================
  void _checkTurnAlerts() {
    if (hasArrived || _hasArrivedAndSessionEnded) {
      return;
    }
    
    if (driverLocation == null || routeSteps.isEmpty || currentStepIndex >= routeSteps.length) {
      return;
    }
    
    // Throttle turn checks
    if (_lastTurnCheckTime != null) {
      final elapsed = DateTime.now().difference(_lastTurnCheckTime!);
      if (elapsed < _turnCheckInterval) return;
    }
    _lastTurnCheckTime = DateTime.now();
    
    final currentStep = routeSteps[currentStepIndex];
    final distanceToStepEnd = Geolocator.distanceBetween(
      driverLocation!.latitude,
      driverLocation!.longitude,
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
          driverLocation!,
          _getPointAhead(driverLocation!, currentRoadHeading!, 10),
          _getPointAhead(currentStep.endLocation, nextStepHeading, 10)
        );
        final actualManeuver = cross > 0 ? 'turn-left' : 'turn-right';
        if (actualManeuver != nextManeuver) {
          _logInfo('Correcting maneuver: $nextManeuver → $actualManeuver');
          nextManeuver = actualManeuver;
        }
      }
    }
    
    _checkJunctionProximity(distanceToStepEnd, currentStep.roadName, currentStep.maneuver);
    bannerDistance = _formatDistance(distanceToStepEnd);
    onMapUpdated?.call();
    
    if (!hasArrived && !_hasArrivedAndSessionEnded) {
      _handleVoiceAnnouncements(distanceToStepEnd, currentStep);
    }
    
    if (distanceToStepEnd < 20 && currentStepIndex < routeSteps.length - 1 && !hasArrived && !_hasArrivedAndSessionEnded) {
      _completeStep();
    }
    
    if (distanceToStepEnd < 50 && currentStepIndex >= routeSteps.length - 1 && !hasArrived && !_hasArrivedAndSessionEnded) {
      _handleArrival();
    }
  }

  LatLng _getPointAhead(LatLng from, double bearing, double distanceMeters) {
    const double R = 6371000;
    final lat = from.latitude * pi / 180;
    final lng = from.longitude * pi / 180;
    final brng = bearing * pi / 180;
    final newLat = asin(sin(lat) * cos(distanceMeters / R) + cos(lat) * sin(distanceMeters / R) * cos(brng));
    final newLng = lng + atan2(sin(brng) * sin(distanceMeters / R) * cos(lat), cos(distanceMeters / R) - sin(lat) * sin(newLat));
    return LatLng(newLat * 180 / pi, newLng * 180 / pi);
  }

  void _updateCurrentRoadHeading() {
    if (currentRoutePoints.isEmpty || driverLocation == null) return;
    double minDist = double.infinity;
    int nearestIndex = 0;
    for (int i = 0; i < currentRoutePoints.length; i++) {
      final dist = Geolocator.distanceBetween(
        driverLocation!.latitude,
        driverLocation!.longitude,
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

  void _handleVoiceAnnouncements(double distanceToStepEnd, NavigationStep currentStep) {
    if (hasArrived || _hasArrivedAndSessionEnded) {
      return;
    }
    
    final bool isTurn = currentStep.maneuver != 'straight' && currentStep.maneuver != 'continue';
    const List<double> thresholds = [2000, 1000, 500, 200, 100, 50];
    
    for (final threshold in thresholds) {
      if (distanceToStepEnd <= threshold && distanceToStepEnd > threshold - 10 && lastAnnouncementDistance != threshold) {
        lastAnnouncementDistance = threshold;
        
        if (isTurn) {
          String voiceText;
          if (threshold == 50) {
            voiceText = '${_getManeuverText(currentStep.maneuver)} now!';
          } else if (threshold == 100) {
            voiceText = 'In 100 meters, ${_getManeuverText(currentStep.maneuver)}';
          } else if (threshold == 200) {
            voiceText = 'In 200 meters, ${_getManeuverText(currentStep.maneuver)}';
          } else {
            voiceText = 'In ${_formatDistance(threshold.toDouble())}, ${_getManeuverText(currentStep.maneuver)} onto ${currentStep.roadName.isNotEmpty ? currentStep.roadName : "the road"}';
          }
          speak(voiceText);
        } else {
          if (threshold == 50) {
            speak('Continue straight');
          } else if (threshold % 1000 == 0) {
            speak('Continue for ${threshold ~/ 1000} kilometers');
          } else {
            speak('Continue for ${_formatDistance(threshold.toDouble())}');
          }
        }
        
        String alertText = isTurn ? '${_getManeuverIcon(currentStep.maneuver)} ${_getManeuverText(currentStep.maneuver)} in ${_formatDistance(threshold.toDouble())}' : '⬆ Continue for ${_formatDistance(threshold.toDouble())}';
        onTurnAlert?.call(alertText, threshold < 100 ? 'danger' : 'info');
      }
    }
  }

  void _completeStep() {
    if (hasArrived || _hasArrivedAndSessionEnded) {
      return;
    }
    
    _logInfo('Completing step ${currentStepIndex + 1}/${routeSteps.length}');
    currentStepIndex++;
    hasAnnouncedCurrentStep = false;
    lastAnnouncementDistance = -1;
    
    if (currentStepIndex < routeSteps.length) {
      _updateCurrentStepInfo();
      final nextStep = routeSteps[currentStepIndex];
      _speakInstruction(nextStep);
      hasAnnouncedCurrentStep = true;
    }
  }

  void _checkJunctionProximity(double distanceToStepEnd, String roadName, String maneuver) {
    if (!getFeature('junctionOverlay')) {
      showJunctionOverlay = false;
      return;
    }
    final bool wasNearJunction = isNearJunction;
    isNearJunction = distanceToStepEnd < 200;
    junctionDistance = distanceToStepEnd;
    junctionRoadName = roadName;
    junctionManeuver = maneuver;
    showJunctionOverlay = isNearJunction;
    if (isNearJunction != wasNearJunction && mapController != null && driverLocation != null) {
      _updateCameraPosition();
    }
    onMapUpdated?.call();
  }

  // ============================================================
  // VOICE NAVIGATION HELPERS
  // ============================================================
  String _getManeuverText(String maneuver) {
    switch (maneuver) {
      case 'turn-left':
        return 'turn left';
      case 'turn-right':
        return 'turn right';
      case 'turn-sharp-left':
        return 'make a sharp left turn';
      case 'turn-sharp-right':
        return 'make a sharp right turn';
      case 'turn-slight-left':
        return 'bear left';
      case 'turn-slight-right':
        return 'bear right';
      case 'straight':
        return 'continue straight';
      case 'continue':
        return 'continue';
      case 'merge':
        return 'merge';
      case 'fork-left':
        return 'stay left at the fork';
      case 'fork-right':
        return 'stay right at the fork';
      case 'roundabout':
        return 'enter the roundabout';
      case 'ferry':
        return 'take the ferry';
      default:
        return 'continue';
    }
  }

  String _getManeuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn-left':
        return '⬅️';
      case 'turn-right':
        return '➡️';
      case 'turn-sharp-left':
        return '↰';
      case 'turn-sharp-right':
        return '↱';
      case 'turn-slight-left':
        return '◀️';
      case 'turn-slight-right':
        return '▶️';
      case 'straight':
        return '⬆️';
      case 'continue':
        return '⬆️';
      case 'merge':
        return '🔀';
      case 'fork-left':
        return '⬅️↗️';
      case 'fork-right':
        return '➡️↖️';
      case 'ferry':
        return '⛴️';
      case 'roundabout':
        return '🔄';
      default:
        return '⬆️';
    }
  }

  String getManeuverIcon(String maneuver) {
    return _getManeuverIcon(maneuver);
  }

  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  // ============================================================
  // OFF-ROUTE DETECTION & RECALCULATION
  // ============================================================
  bool isDriverOffRoute(LatLng driverPosition, List<LatLng> routePoints) {
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

  // ============================================================
  // SMOOTH INTERPOLATION
  // ============================================================
  void _handleLocationUpdate(LatLng newPosition, double heading, double speed) {
    currentSpeed = speed;
    updateHeading(heading);
    startInterpolation(newPosition);
    
    if (isNavigating && !hasArrived && currentRoutePoints.isNotEmpty && getFeature('progressiveRouteClearing')) {
      clearRouteProgressively(newPosition);
    }
  }

  void startInterpolation(LatLng newPosition) {
    if (interpolatedDriverPosition == null) {
      interpolatedDriverPosition = newPosition;
      previousInterpolatedPosition = newPosition;
      targetInterpolatedPosition = newPosition;
      interpolationProgress = 1.0;
      driverLocation = newPosition;
      _updateCameraPosition();
      onMapUpdated?.call();
      return;
    }
    final distance = Geolocator.distanceBetween(
      interpolatedDriverPosition!.latitude,
      interpolatedDriverPosition!.longitude,
      newPosition.latitude,
      newPosition.longitude,
    );
    if (distance < 0.5) {
      interpolatedDriverPosition = newPosition;
      previousInterpolatedPosition = newPosition;
      targetInterpolatedPosition = newPosition;
      interpolationProgress = 1.0;
      driverLocation = newPosition;
      onMapUpdated?.call();
      return;
    }
    previousInterpolatedPosition = interpolatedDriverPosition;
    targetInterpolatedPosition = newPosition;
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
    interpolationTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (interpolationStartTime == null || previousInterpolatedPosition == null || targetInterpolatedPosition == null) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(interpolationStartTime!);
      final progress = (elapsed.inMilliseconds / interpolationDuration.inMilliseconds).clamp(0.0, 1.0);
      final easedProgress = progress < 0.5 ? 4 * progress * progress * progress : 1 - pow(-2 * progress + 2, 3) / 2;
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
      driverLocation = LatLng(lat, lng);
      onMapUpdated?.call();
      if (progress >= 1.0) {
        timer.cancel();
        interpolatedDriverPosition = targetInterpolatedPosition;
        driverLocation = targetInterpolatedPosition;
        interpolationProgress = 1.0;
        onMapUpdated?.call();
        _updateCameraPosition();
      }
    });
  }

  // ============================================================
  // PROGRESSIVE ROUTE CLEARING
  // ============================================================
  void clearRouteProgressively(LatLng driverPosition) {
    if (currentRoutePoints.isEmpty || routeSteps.isEmpty) return;
    if (!getFeature('progressiveRouteClearing')) return;
    
    if (isRecalculatingRoute) {
      _logInfo('Route recalculation in progress, skipping progressive clear');
      return;
    }
    
    try {
      double minDistance = double.infinity;
      int nearestIndex = 0;
      
      for (int i = 0; i < currentRoutePoints.length; i++) {
        final distance = Geolocator.distanceBetween(
          driverPosition.latitude,
          driverPosition.longitude,
          currentRoutePoints[i].latitude,
          currentRoutePoints[i].longitude,
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearestIndex = i;
        }
      }
      
      if (nearestIndex > 10 && nearestIndex < currentRoutePoints.length - 5) {
        final keepAhead = 20;
        final startIndex = (nearestIndex - 5).clamp(0, currentRoutePoints.length - 1);
        
        if (startIndex > 0) {
          final remainingPoints = currentRoutePoints.sublist(startIndex);
          
          if (remainingPoints.length > 5) {
            currentRoutePoints = remainingPoints;
            
            polylines = _buildPolylinesWithTraffic(currentRoutePoints);
            polylines.addAll(_buildAlternativePolylines(alternativeRoutes));
            
            int stepsToRemove = 0;
            for (int i = 0; i < routeSteps.length; i++) {
              final stepEnd = routeSteps[i].endLocation;
              final distToStepEnd = Geolocator.distanceBetween(
                driverPosition.latitude,
                driverPosition.longitude,
                stepEnd.latitude,
                stepEnd.longitude,
              );
              if (distToStepEnd < 50) {
                stepsToRemove = i + 1;
              }
            }
            
            if (stepsToRemove > 0 && stepsToRemove < routeSteps.length) {
              routeSteps = routeSteps.sublist(stepsToRemove);
              _lazyStepLoader = LazyStepLoader(routeSteps);
              currentStepIndex = currentStepIndex - stepsToRemove;
              if (currentStepIndex < 0) currentStepIndex = 0;
              _updateCurrentStepInfo();
            }
            
            if (routeSteps.isNotEmpty) {
              bannerProgress = currentStepIndex / routeSteps.length;
            }
            
            onMapUpdated?.call();
            _logInfo('Route progressively cleared - ${remainingPoints.length} points remaining');
          }
        }
      }
    } catch (e) {
      _logError('Error clearing route progressively', details: {'error': e.toString()});
    }
  }

  // ============================================================
  // ROUTE FOLLOWING
  // ============================================================
  LatLng _snapToRoute(LatLng position) {
    if (!useRouteFollowing || currentRoutePoints.isEmpty) {
      return position;
    }
    double minDistance = double.infinity;
    int nearestIndex = 0;
    for (int i = 0; i < currentRoutePoints.length; i++) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        currentRoutePoints[i].latitude,
        currentRoutePoints[i].longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    if (minDistance > routeSnapDistance) {
      _logInfo('Driver is ${minDistance.toStringAsFixed(0)}m from route - not snapping');
      return position;
    }
    LatLng snappedPoint = currentRoutePoints[nearestIndex];
    if (nearestIndex == currentRoutePoints.length - 1) {
      return snappedPoint;
    }
    LatLng nextPoint = currentRoutePoints[nearestIndex + 1];
    double segmentLength = Geolocator.distanceBetween(
      snappedPoint.latitude,
      snappedPoint.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );
    if (segmentLength < 0.1) {
      return snappedPoint;
    }
    double latDiff = position.latitude - snappedPoint.latitude;
    double lngDiff = position.longitude - snappedPoint.longitude;
    double projectionFactor = (latDiff * (nextPoint.latitude - snappedPoint.latitude) +
        lngDiff * (nextPoint.longitude - snappedPoint.longitude)) / (segmentLength * segmentLength);
    projectionFactor = projectionFactor.clamp(0.0, 1.0);
    LatLng projectedPoint = LatLng(
      snappedPoint.latitude + projectionFactor * (nextPoint.latitude - snappedPoint.latitude),
      snappedPoint.longitude + projectionFactor * (nextPoint.longitude - snappedPoint.longitude),
    );
    double blendFactor = minDistance < 5 ? 1.0 : minDistance / routeSnapDistance;
    blendFactor = blendFactor.clamp(0.0, 1.0);
    return LatLng(
      projectedPoint.latitude * blendFactor + position.latitude * (1 - blendFactor),
      projectedPoint.longitude * blendFactor + position.longitude * (1 - blendFactor),
    );
  }

  double _getRouteHeading(LatLng position) {
    if (currentRoutePoints.length < 2) return currentHeading;
    double minDistance = double.infinity;
    int nearestIndex = 0;
    for (int i = 0; i < currentRoutePoints.length; i++) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        currentRoutePoints[i].latitude,
        currentRoutePoints[i].longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    if (nearestIndex < currentRoutePoints.length - 1) {
      return _calculateBearing(
        currentRoutePoints[nearestIndex],
        currentRoutePoints[nearestIndex + 1]
      );
    } else if (nearestIndex > 0) {
      return _calculateBearing(
        currentRoutePoints[nearestIndex - 1],
        currentRoutePoints[nearestIndex]
      );
    }
    return currentHeading;
  }

  // ============================================================
  // ENHANCED CAMERA FOLLOWING - WITH DYNAMIC ZOOM
  // ============================================================
  void startCameraFollowing() {
    cameraFollowTimer?.cancel();
    if (driverLocation != null) {
      cameraTargetPosition = driverLocation;
      cameraBearing = 0; // Always North-up
      cameraZoom = baseZoom;
      _smoothZoom = baseZoom;
    }
    movementCheckTimer?.cancel();
    movementCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _checkDriverMovement();
    });
    
    // Initialize camera throttler
    if (mapController != null) {
      _cameraThrottler = CameraUpdateThrottler(
        mapController!,
        throttleInterval: const Duration(milliseconds: 100),
      );
    }
    
    cameraFollowTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _updateDynamicCameraPosition();
    });
  }

  void _checkDriverMovement() {
    if (driverLocation == null) return;
    if (lastKnownPosition == null) {
      lastKnownPosition = driverLocation;
      isDriverMoving = false;
      return;
    }
    final distance = Geolocator.distanceBetween(
      lastKnownPosition!.latitude,
      lastKnownPosition!.longitude,
      driverLocation!.latitude,
      driverLocation!.longitude,
    );
    isDriverMoving = distance > movementThreshold;
    if (isDriverMoving) {
      lastKnownPosition = driverLocation;
      _updateCameraPosition();
    }
  }

  // ============================================================
  // ENHANCED DYNAMIC ZOOM CALCULATION - SPEED & CONTEXT AWARE
  // ============================================================
  double _calculateDynamicZoom() {
    double targetZoom = baseZoom;
    
    // 1. Speed-based zoom (Zoom out when faster, zoom in when slower)
    if (currentSpeed < 5) {
      _zoomAtSpeed = 19.5; // Stopped - very close
    } else if (currentSpeed < 10) {
      _zoomAtSpeed = 19.0; // Very slow (traffic)
    } else if (currentSpeed < 20) {
      _zoomAtSpeed = 18.5; // Slow moving
    } else if (currentSpeed < 35) {
      _zoomAtSpeed = 18.0; // Normal city driving
    } else if (currentSpeed < 50) {
      _zoomAtSpeed = 17.5; // Fast city driving
    } else if (currentSpeed < 70) {
      _zoomAtSpeed = 17.0; // Highway
    } else {
      _zoomAtSpeed = 16.5; // Very fast highway
    }
    
    // 2. Junction proximity zoom - get closer at turns
    if (isNearJunction && junctionDistance < 100) {
      _zoomAtJunction = 19.0;
    } else if (isNearJunction && junctionDistance < 200) {
      _zoomAtJunction = 18.5;
    } else {
      _zoomAtJunction = _zoomAtSpeed;
    }
    
    // 3. Arrival zoom - maximum zoom when arriving
    if (hasArrived || (distanceToCustomer != null && distanceToCustomer! < 100)) {
      _zoomAtArrival = 19.5;
    } else if (distanceToCustomer != null && distanceToCustomer! < 500) {
      _zoomAtArrival = 19.0;
    } else {
      _zoomAtArrival = _zoomAtJunction;
    }
    
    // 4. Route start zoom - moderate zoom when starting
    if (currentRoutePoints.length > 10 && !hasArrived && distanceToCustomer != null && distanceToCustomer! > 1000) {
      _zoomAtRouteStart = 17.0;
    } else {
      _zoomAtRouteStart = _zoomAtArrival;
    }
    
    // 5. Combine zoom factors with priority
    if (hasArrived || (distanceToCustomer != null && distanceToCustomer! < 100)) {
      targetZoom = _zoomAtArrival;
    } else if (isNearJunction) {
      targetZoom = _zoomAtJunction;
    } else if (distanceToCustomer != null && distanceToCustomer! > 1000) {
      targetZoom = _zoomAtRouteStart;
    } else {
      targetZoom = _zoomAtSpeed;
    }
    
    // 6. Clamp to safe range
    targetZoom = targetZoom.clamp(minZoom, maxZoom);
    
    // 7. Smooth zoom transition using damping
    final zoomDiff = targetZoom - _smoothZoom;
    _zoomVelocity = _zoomVelocity * zoomSmoothDamping + zoomDiff * zoomSmoothFactor;
    _smoothZoom = _smoothZoom + _zoomVelocity;
    
    _smoothZoom = _smoothZoom.clamp(minZoom, maxZoom);
    
    // 8. Ensure driver is always at bottom of screen (Uber style)
    _updateMapPadding();
    
    return _smoothZoom;
  }

  void _updateDynamicCameraPosition() {
    if (!isCameraFollowing || mapController == null || driverLocation == null) return;
    
    if (!isDriverMoving && cameraTargetPosition != null) {
      return;
    }
    
    final targetLat = driverLocation!.latitude;
    final targetLng = driverLocation!.longitude;
    
    if (cameraTargetPosition == null) {
      cameraTargetPosition = driverLocation;
    }
    
    final deltaLat = targetLat - cameraTargetPosition!.latitude;
    final deltaLng = targetLng - cameraTargetPosition!.longitude;
    
    if (deltaLat.abs() > 0.00001 || deltaLng.abs() > 0.00001) {
      cameraTargetPosition = LatLng(
        cameraTargetPosition!.latitude + deltaLat * 0.3,
        cameraTargetPosition!.longitude + deltaLng * 0.3,
      );
    }
    
    // Keep bearing at 0 (North-up) - never rotate map
    cameraBearing = 0;
    
    double targetZoom = _calculateDynamicZoom();
    cameraZoom = targetZoom;
    
    _updateMapPadding();
    
    // Use throttled camera updates
    if (_cameraThrottler != null) {
      _cameraThrottler!.updatePosition(
        CameraPosition(
          target: cameraTargetPosition!,
          zoom: cameraZoom,
          bearing: 0, // Always North-up
          tilt: 45.0,
        ),
      );
    } else {
      try {
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: cameraTargetPosition!,
              zoom: cameraZoom,
              bearing: 0, // Always North-up
              tilt: 45.0,
            ),
          ),
        );
      } catch (e) {
        // Ignore - controller may be disposed
      }
    }
  }

  // ============================================================
  // UPDATE CAMERA POSITION - Legacy method (kept for compatibility)
  // ============================================================
  void _updateCameraPosition() {
    if (mapController == null || driverLocation == null) return;
    final targetLat = driverLocation!.latitude;
    final targetLng = driverLocation!.longitude;
    if (cameraTargetPosition == null) {
      cameraTargetPosition = driverLocation;
    }
    final deltaLat = targetLat - cameraTargetPosition!.latitude;
    final deltaLng = targetLng - cameraTargetPosition!.longitude;
    if (deltaLat.abs() > 0.00001 || deltaLng.abs() > 0.00001) {
      cameraTargetPosition = LatLng(
        cameraTargetPosition!.latitude + deltaLat * 0.3,
        cameraTargetPosition!.longitude + deltaLng * 0.3,
      );
    }
    // Always keep North-up
    cameraBearing = 0;
    double targetZoom = _calculateDynamicZoom();
    cameraZoom = targetZoom;
    _updateMapPadding();
    
    if (_cameraThrottler != null) {
      _cameraThrottler!.updatePosition(
        CameraPosition(
          target: cameraTargetPosition!,
          zoom: cameraZoom,
          bearing: 0, // Always North-up
          tilt: 45.0,
        ),
      );
    } else {
      try {
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: cameraTargetPosition!,
              zoom: cameraZoom,
              bearing: 0, // Always North-up
              tilt: 45.0,
            ),
          ),
        );
      } catch (e) {
        // Ignore - controller may be disposed
      }
    }
  }

  void updateHeading(double heading) {
    if (headingHistory.isEmpty) {
      headingHistory.add(heading);
      currentHeading = heading;
      previousHeading = heading;
      return;
    }
    double diff = heading - previousHeading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    const double smoothFactor = 0.12;
    final smoothDiff = diff * smoothFactor;
    final newHeading = previousHeading + smoothDiff;
    previousHeading = newHeading;
    currentHeading = ((newHeading % 360) + 360) % 360;
    headingHistory.add(currentHeading);
    if (headingHistory.length > maxHeadingHistory) {
      headingHistory.removeAt(0);
    }
  }

  // ============================================================
  // INITIALIZE MAP
  // ============================================================
  void initializeMap(GoogleMapController controller) {
    mapController = controller;
    if (driverLocation != null) {
      try {
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: driverLocation!,
              zoom: baseZoom,
              tilt: 45.0,
              bearing: 0, // Always North-up
            ),
          ),
        );
      } catch (e) {
        // Ignore
      }
    }
    isMapRotating = false; // Keep North-up always
    isCameraFollowing = true;
    startCameraFollowing();
    initializeAnimationUpdates();
  }

  void fitRouteToBounds() {
    if (mapController == null || currentRoutePoints.isEmpty) return;
    List<LatLng> points = List.from(currentRoutePoints);
    if (customerLocation != null) points.add(customerLocation!);
    if (driverLocation != null) points.add(driverLocation!);
    final bounds = getBoundsFromPoints(points);
    try {
      mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          60,
        ),
      );
    } catch (e) {
      // Ignore
    }
  }

  // ============================================================
  // TRAFFIC MONITORING
  // ============================================================
  void startTrafficMonitoring() {
    if (!getFeature('trafficMonitoring')) return;
    trafficUpdateTimer?.cancel();
    trafficUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkTrafficAndUpdateETA();
    });
  }

  Future<void> _checkTrafficAndUpdateETA() async {
    if (isCheckingTraffic || currentRoutePoints.isEmpty || driverLocation == null || customerLocation == null) return;
    isCheckingTraffic = true;
    try {
      final origin = driverLocation!;
      final destination = customerLocation!;
      final result = await getRouteWithDetails(origin, destination, getAlternatives: false);
      final newDuration = result['duration'] as Duration?;
      final newPoints = result['points'] as List<LatLng>;
      if (newDuration != null && actualTravelDuration != null) {
        final delayInSeconds = newDuration.inSeconds - actualTravelDuration!.inSeconds;
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
        if (delayInSeconds > 120 && newPoints.isNotEmpty) {
          _buildTrafficSegments(newPoints, trafficLevel);
          polylines = _buildTrafficSegmentedRoute(currentRoutePoints, trafficSegments);
          polylines.addAll(_buildAlternativePolylines(alternativeRoutes));
          speak('Traffic update: $trafficLevel traffic ahead.');
        }
        estimatedMinutes = newDuration.inMinutes > 0 ? newDuration.inMinutes : 1;
        onMapUpdated?.call();
      }
    } catch (e) {
      _logError('Traffic check error', details: {'error': e.toString()});
    }
    isCheckingTraffic = false;
  }

  void _buildTrafficSegments(List<LatLng> points, String trafficLevel) {
    trafficSegments.clear();
    const int segmentSize = 20;
    for (int i = 0; i < points.length; i += segmentSize) {
      final end = min(i + segmentSize, points.length);
      final segmentPoints = points.sublist(i, end);
      Color color;
      if (i < points.length * 0.3) {
        color = Colors.green;
      } else if (i < points.length * 0.6) {
        color = trafficLevel == 'HEAVY' ? Colors.red.shade800 : Colors.orange;
      } else {
        color = trafficLevel == 'HEAVY' ? Colors.red : Colors.green;
      }
      trafficSegments.add({
        'points': segmentPoints,
        'color': color,
        'level': trafficLevel,
        'startIndex': i,
        'endIndex': end,
      });
    }
  }

  // ============================================================
  // SPEED LIMIT MONITORING
  // ============================================================
  void startSpeedLimitMonitoring() {
    if (!getFeature('speedLimitMonitoring')) return;
    speedLimitTimer?.cancel();
    speedLimitTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkSpeedLimit();
    });
  }

  Future<void> _checkSpeedLimit() async {
    if (driverLocation == null) return;
    try {
      final speedLimit = await _getSpeedLimitFromAPI(driverLocation!);
      currentSpeedLimit = speedLimit;
      speedLimitDisplay = speedLimit > 0 ? '$speedLimit km/h' : '--';
      final bool wasSpeeding = isSpeeding;
      isSpeeding = currentSpeed > speedLimit * 1.1 && speedLimit > 0;
      if (isSpeeding && !wasSpeeding && speedLimit > 0) {
        speak('⚠️ Speed limit exceeded. Please slow down to $speedLimit km/h.');
        onTurnAlert?.call('⚠️ Speed limit: $speedLimit km/h. You are at ${currentSpeed.toStringAsFixed(0)} km/h', 'danger');
      }
      onMapUpdated?.call();
    } catch (e) {
      _logError('Speed limit check error', details: {'error': e.toString()});
    }
  }

  Future<int> _getSpeedLimitFromAPI(LatLng position) async {
    try {
      String baseUrl = 'https://roads.googleapis.com/v1/speedLimits?path=${position.latitude},${position.longitude}'
          '&key=$googleAPIKey';
      String url = baseUrl;
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['speedLimits'] != null && data['speedLimits'].isNotEmpty) {
          return data['speedLimits'][0]['speedLimit'] as int;
        }
      }
    } catch (e) {
      _logError('Error getting speed limit', details: {'error': e.toString()});
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
  // ROAD SNAPPING
  // ============================================================
  Future<void> snapToRoad(LatLng position) async {
    try {
      recentPositions.add(position);
      if (recentPositions.length > maxRecentPositions) {
        recentPositions.removeAt(0);
      }
      String path = recentPositions.map((p) => '${p.latitude},${p.longitude}').join('|');
      String baseUrl = 'https://roads.googleapis.com/v1/snapToRoads?path=$path'
          '&interpolate=true'
          '&key=$googleAPIKey';
      String url = baseUrl;
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['snappedPoints'] != null && data['snappedPoints'].isNotEmpty) {
          final snapped = data['snappedPoints'].last;
          snappedDriverPosition = LatLng(
            snapped['location']['latitude'] as double,
            snapped['location']['longitude'] as double,
          );
          if (snappedDriverPosition != null) {
            driverLocation = snappedDriverPosition;
            onMapUpdated?.call();
          }
        }
      }
    } catch (e) {
      _logError('Road snapping error', details: {'error': e.toString()});
    }
  }

  // ============================================================
  // GPS FILTERING
  // ============================================================
  LatLng filterGPSSignal(LatLng newPosition) {
    if (filteredPosition == null) {
      filteredPosition = newPosition;
      return newPosition;
    }
    final lat = filteredPosition!.latitude + filterAlpha * (newPosition.latitude - filteredPosition!.latitude);
    final lng = filteredPosition!.longitude + filterAlpha * (newPosition.longitude - filteredPosition!.longitude);
    filteredPosition = LatLng(lat, lng);
    return LatLng(lat, lng);
  }

  // ============================================================
  // GET BOUNDS
  // ============================================================
  LatLngBounds getBoundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    double latPadding = (maxLat - minLat) * 0.1;
    double lngPadding = (maxLng - minLng) * 0.1;
    return LatLngBounds(
      southwest: LatLng(minLat - latPadding, minLng - lngPadding),
      northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
    );
  }

  // ============================================================
  // UPDATE DRIVER POSITION - MAIN ENTRY POINT
  // ============================================================
  void updateDriverPosition(Position position, String vehicleType, String numberPlate) {
    final rawPosition = LatLng(position.latitude, position.longitude);
    final filtered = filterGPSSignal(rawPosition);
    final speed = position.speed * 3.6;
    LatLng finalPosition = filtered;
    if (useRouteFollowing && currentRoutePoints.isNotEmpty) {
      finalPosition = _snapToRoute(filtered);
    }
    if (position.heading != null && position.heading! >= 0) {
      updateHeading(position.heading!);
    } else if (currentSpeed > 1.0 && previousInterpolatedPosition != null) {
      double calculatedHeading;
      if (useRouteFollowing && currentRoutePoints.isNotEmpty) {
        calculatedHeading = _getRouteHeading(finalPosition);
      } else {
        calculatedHeading = _calculateBearing(
          previousInterpolatedPosition!,
          finalPosition
        );
      }
      if (calculatedHeading >= 0) {
        updateHeading(calculatedHeading);
      }
    }
    _handleLocationUpdate(finalPosition, currentHeading, speed);
    snapToRoad(finalPosition);
    recalculateRouteIfNeeded(finalPosition, vehicleType, numberPlate);
    sendLocationToFirestore(
      position: finalPosition,
      heading: currentHeading,
      speed: speed,
    );
    updateDriverMarkerWithInterpolation(vehicleType, numberPlate);
  }

  // ============================================================
  // ZOOM TO ROUTE
  // ============================================================
  void zoomToRoute() {
    if (mapController == null || currentRoutePoints.isEmpty) return;
    try {
      mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          getBoundsFromPoints(currentRoutePoints),
          50,
        ),
      );
    } catch (e) {
      // Ignore
    }
  }

  // ============================================================
  // GETTER METHODS
  // ============================================================
  Map<String, dynamic> getTrafficStatus() {
    return {
      'level': currentTrafficData?['level'] ?? 'LIGHT',
      'delay': currentTrafficData?['delay'] ?? 0,
      'color': currentTrafficColor,
      'hasTraffic': currentTrafficData?['delay'] != null && currentTrafficData?['delay'] > 60,
      'segments': trafficSegments.length,
    };
  }

  Map<String, dynamic> getSpeedLimitStatus() {
    return {
      'limit': currentSpeedLimit,
      'display': speedLimitDisplay,
      'isSpeeding': isSpeeding,
      'currentSpeed': currentSpeed,
    };
  }

  List<LaneInfo> getLaneGuidance() {
    return laneGuidance;
  }

  String getLaneGuidanceText() {
    return laneGuidanceText;
  }

  Map<String, dynamic> getNavigationBannerData() {
    return {
      'show': showNavigationBanner,
      'instruction': bannerInstruction,
      'maneuver': bannerManeuver,
      'distance': bannerDistance,
      'nextRoad': bannerNextRoad,
      'currentRoad': bannerCurrentRoad,
      'subInstruction': bannerSubInstruction,
      'progress': bannerProgress,
      'isNavigating': isNavigating,
      'stepIndex': currentStepIndex,
      'totalSteps': routeSteps.length,
    };
  }

  Map<String, dynamic> getJunctionData() {
    return {
      'isNear': isNearJunction,
      'roadName': junctionRoadName,
      'maneuver': junctionManeuver,
      'distance': _formatDistance(junctionDistance),
      'showOverlay': showJunctionOverlay,
    };
  }

  List<Map<String, dynamic>> getAlternativeRoutesInfo() {
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < alternativeRoutes.length; i++) {
      final duration = i < alternativeDurations.length ? alternativeDurations[i] : Duration.zero;
      result.add({
        'index': i,
        'duration': duration,
        'durationText': '${duration.inMinutes} min',
        'isSelected': selectedRouteIndex == i + 1,
        'points': alternativeRoutes[i],
      });
    }
    return result;
  }

  EdgeInsets getMapPadding() {
    return mapPadding;
  }

  void setMapPadding(EdgeInsets padding) {
    mapPadding = padding;
  }

  void setVoiceEnabled(bool enabled) {
    isVoiceEnabled = enabled;
  }

  void setPredictiveCameraEnabled(bool enabled) {
    predictiveCameraEnabled = enabled;
  }

  void setFilterAlpha(double alpha) {
    filterAlpha = alpha.clamp(0.0, 1.0);
  }

  LatLng? getFilteredPosition() {
    return filteredPosition;
  }

  LatLng? getPredictedCameraTarget() {
    return predictedCameraTarget;
  }

  double getCurrentZoom() {
    return currentZoom;
  }

  String getArrivalTime() {
    if (estimatedMinutes == null) return 'Now';
    final arrival = DateTime.now().add(Duration(minutes: estimatedMinutes!));
    final period = arrival.hour >= 12 ? 'PM' : 'AM';
    final hour = arrival.hour > 12 ? arrival.hour - 12 : arrival.hour;
    return '${hour}:${arrival.minute.toString().padLeft(2, '0')} $period';
  }

  double getHeading() {
    return currentHeading;
  }

  void setMapRotation(bool enabled) {
    isMapRotating = false; // Always keep North-up
  }

  bool isMoving() {
    return isDriverMoving;
  }

  void setRouteFollowing(bool enabled) {
    useRouteFollowing = enabled;
    _logInfo('Route following ${enabled ? 'enabled' : 'disabled'}');
  }

  void setRouteSnapDistance(double meters) {
    routeSnapDistance = meters.clamp(5.0, 100.0);
    _logInfo('Route snap distance set to ${routeSnapDistance.toStringAsFixed(0)}m');
  }

  void setCarSize(double width, double height) {
    carWidth = width.clamp(30.0, 200.0);
    carHeight = height.clamp(30.0, 200.0);
    markerCache.clear();
    _logInfo('Driver car size set to ${carWidth.toStringAsFixed(0)}x${carHeight.toStringAsFixed(0)}');
    if (driverLocation != null) {
      _forceMarkerUpdate();
    }
  }

  Map<String, double> getCarSize() {
    return {
      'width': carWidth,
      'height': carHeight,
    };
  }

  void _forceMarkerUpdate() {
    if (_currentVehicleType != null && _currentNumberPlate != null && driverLocation != null) {
      _getVehicleMarker(_currentVehicleType!.toLowerCase(), bearing: currentHeading).then((markerIcon) {
        mapMarkers.removeWhere((marker) => marker.markerId.value == 'driver');
        mapMarkers.add(
          Marker(
            markerId: const MarkerId('driver'),
            position: driverLocation!,
            icon: markerIcon,
            rotation: currentHeading,
            anchor: const Offset(0.5, 0.9),
            flat: true,
            infoWindow: InfoWindow(
              title: '🚗 Your Location',
              snippet: '$_currentVehicleType • $_currentNumberPlate • ${currentSpeed.toStringAsFixed(0)} km/h',
            ),
          ),
        );
        if (driverId != null) {
          bool isMoving = currentSpeed > 2.0;
          updateAnimatedDriver(
            driverId: driverId!,
            position: driverLocation!,
            heading: currentHeading,
            speed: currentSpeed,
            vehicleType: _currentVehicleType!,
            numberPlate: _currentNumberPlate!,
            isMoving: isMoving,
          );
        }
        onMapUpdated?.call();
      });
    } else {
      onMapUpdated?.call();
    }
  }

  Map<String, dynamic> getCorsConfig() {
    return {
      'useProxy': false, // Now using direct API calls
      'proxyUrl': '', // CORS proxy not used anymore
      'isWeb': const bool.fromEnvironment('dart.library.js_util'),
    };
  }

  void toggleCorsProxy(bool enabled) {
    _logWarning('CORS proxy toggle requires app restart to take effect');
    _logInfo('Set useCorsProxy = $enabled in the code and rebuild');
  }

  // ============================================================
  // ANIMATED DRIVER METHODS
  // ============================================================
  void initializeAnimationUpdates() {
    if (!getFeature('animatedMarkers')) return;
    _animationUpdateTimer?.cancel();
    _animationUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _updateAnimatedMarkers();
    });
  }

  void _updateAnimatedMarkers() {
    if (_animatedDrivers.isEmpty) {
      animatedMarkers.clear();
      onMapUpdated?.call();
      return;
    }
    animatedMarkers.clear();
    _animatedDrivers.forEach((id, data) {
      _getVehicleMarker(data.vehicleType.toLowerCase(), bearing: data.bearing).then((markerIcon) {
        animatedMarkers.add(
          Marker(
            markerId: MarkerId('animated_$id'),
            position: data.path.last,
            icon: markerIcon,
            rotation: data.bearing,
            anchor: const Offset(0.5, 0.9),
            flat: true,
            infoWindow: InfoWindow(
              title: '🚗 Driver $id',
              snippet: '${data.vehicleType} • ${data.numberPlate} • ${data.speed.toStringAsFixed(0)} km/h',
            ),
          ),
        );
        onMapUpdated?.call();
      });
    });
  }

  void updateAnimatedDriver({
    required String driverId,
    required LatLng position,
    required double heading,
    required double speed,
    required String vehicleType,
    required String numberPlate,
    bool isMoving = true,
  }) {
    if (!_driverPaths.containsKey(driverId)) {
      _driverPaths[driverId] = [];
    }
    _driverPaths[driverId]!.add(position);
    if (_driverPaths[driverId]!.length > 100) {
      _driverPaths[driverId]!.removeAt(0);
    }
    _animatedDrivers[driverId] = AnimatedDriverData(
      id: driverId,
      vehicleType: vehicleType,
      numberPlate: numberPlate,
      path: _driverPaths[driverId]!,
      bearing: heading,
      speed: speed,
      isMoving: isMoving,
    );
    if (!isMoving) {
      _addStaticDriver(driverId, position, vehicleType, numberPlate, heading);
      _animatedDrivers.remove(driverId);
    }
    _updateAnimatedMarkers();
  }

  void _addStaticDriver(String driverId, LatLng position, String vehicleType, String numberPlate, double heading) {
    _getVehicleMarker(vehicleType.toLowerCase(), bearing: heading).then((markerIcon) {
      mapMarkers.removeWhere((marker) => marker.markerId.value == 'static_$driverId');
      mapMarkers.add(
        Marker(
          markerId: MarkerId('static_$driverId'),
          position: position,
          icon: markerIcon,
          rotation: heading,
          anchor: const Offset(0.5, 0.9),
          flat: true,
          infoWindow: InfoWindow(
            title: '🚗 Driver $driverId (Idle)',
            snippet: '$vehicleType • $numberPlate',
          ),
        ),
      );
      onMapUpdated?.call();
    });
  }

  void removeAnimatedDriver(String driverId) {
    _animatedDrivers.remove(driverId);
    _driverPaths.remove(driverId);
    mapMarkers.removeWhere((marker) => marker.markerId.value == 'static_$driverId');
    _updateAnimatedMarkers();
  }

  Set<Marker> getAnimatedMarkers() {
    return animatedMarkers;
  }

  Set<Marker> getStaticMarkers() {
    return mapMarkers;
  }

  Map<String, dynamic> getAnimationSettings() {
    return {
      'duration': animarkerDuration,
      'curve': animarkerCurve,
      'useRotation': animarkerUseRotation,
    };
  }

  void setAnimationSettings({
    Duration? duration,
    Curve? curve,
    bool? useRotation,
  }) {
    if (duration != null) animarkerDuration = duration;
    if (curve != null) animarkerCurve = curve;
    if (useRotation != null) animarkerUseRotation = useRotation;
  }

  List<AnimatedDriverData> getAnimatedDrivers() {
    return _animatedDrivers.values.toList();
  }

  List<LatLng> getDriverPath(String driverId) {
    return _driverPaths[driverId] ?? [];
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
  // PERFORMANCE LOGGING
  // ============================================================
  Map<String, dynamic> getPerformanceStats() {
    return {
      'markers': {
        'total': mapMarkers.length + animatedMarkers.length,
        'cached': markerCache.length,
        'poolSize': _markerPool.size,
      },
      'route': {
        'points': currentRoutePoints.length,
        'steps': routeSteps.length,
        'alternatives': alternativeRoutes.length,
      },
      'firestore': {
        'batchSize': _batchManager._batch.length,
        'lastUpdate': lastFirestoreUpdateTime?.toIso8601String(),
        'isQueued': isFirestoreUpdateQueued,
      },
      'performance': _performanceMetrics.map((k, v) => MapEntry(k, '${v.inMilliseconds}ms')),
      'memory': {
        'errorLogs': _errorLogs.length,
        'headingHistory': headingHistory.length,
        'recentPositions': recentPositions.length,
      },
    };
  }

  // ============================================================
  // DISPOSE - Comprehensive cleanup (FIXED: Removed mapController.dispose)
  // ============================================================
  void dispose() {
    _logInfo('Disposing DriverMapController...');
    
    _sessionUpdateTimer?.cancel();
    _sessionUpdateTimer = null;
    movementCheckTimer?.cancel();
    movementCheckTimer = null;
    interpolationTimer?.cancel();
    interpolationTimer = null;
    routeRecalculationTimer?.cancel();
    routeRecalculationTimer = null;
    turnAlertTimer?.cancel();
    turnAlertTimer = null;
    cameraFollowTimer?.cancel();
    cameraFollowTimer = null;
    trafficUpdateTimer?.cancel();
    trafficUpdateTimer = null;
    speedLimitTimer?.cancel();
    speedLimitTimer = null;
    snappingTimer?.cancel();
    snappingTimer = null;
    arrivalAnimationTimer?.cancel();
    arrivalAnimationTimer = null;
    voiceDebounceTimer?.cancel();
    voiceDebounceTimer = null;
    voiceAnnouncementTimer?.cancel();
    voiceAnnouncementTimer = null;
    headingSmoothingTimer?.cancel();
    headingSmoothingTimer = null;
    zoomSmoothingTimer?.cancel();
    zoomSmoothingTimer = null;
    firestoreDebounceTimer?.cancel();
    firestoreDebounceTimer = null;
    _animationUpdateTimer?.cancel();
    _animationUpdateTimer = null;
    
    // Clean up camera throttler
    _cameraThrottler?.dispose();
    _cameraThrottler = null;
    
    // Flush and dispose batch manager
    _batchManager.flush();
    _batchManager.dispose();
    
    // Clear lazy step loader
    _lazyStepLoader?.clear();
    _lazyStepLoader = null;
    
    // Cancel arrival listener on dispose
    _arrivalCheckTimer?.cancel();
    _arrivalCheckTimer = null;

    _sessionSubscription?.cancel();
    _sessionSubscription = null;

    if (_isSessionActive) {
      try {
        endNavigationSession(cancelled: true);
      } catch (e) {
        _logError('Error ending session during dispose', details: {'error': e.toString()});
      }
    }

    onMapUpdated = null;
    onTurnAlert = null;
    speakCallback = null;
    onSessionStarted = null;
    onSessionCompleted = null;
    onSessionCancelled = null;
    onSessionError = null;
    onSessionUpdate = null;
    onErrorLogged = null;

    try {
      disableWakeLock();
    } catch (e) {
      // Ignore
    }

    // Dispose TTS
    _ttsManager.dispose();

    mapMarkers.clear();
    animatedMarkers.clear();
    polylines.clear();
    currentRoutePoints.clear();
    routeSteps.clear();
    alternativeRoutes.clear();
    alternativeDurations.clear();
    recentPositions.clear();
    markerCache.clear();
    roadShields.clear();
    laneGuidance.clear();
    trafficSegments.clear();
    headingHistory.clear();
    announcementQueue.clear();
    _animatedDrivers.clear();
    _driverPaths.clear();
    _staticDrivers.clear();
    _performanceTimers.clear();
    _performanceMetrics.clear();
    _errorLogs.clear();
    _markerPool.clear();

    _isSessionActive = false;
    _navigationInitialized = false;
    _hasAnnouncedStartingNavigation = false;
    _hasArrivedAndSessionEnded = false;
    _isInitializingNavigation = false;
    isNavigating = false;
    hasArrived = false;
    isRecalculatingRoute = false;

    // IMPORTANT: Do NOT call mapController?.dispose()
    // GoogleMapController does not have a dispose method and is managed by the plugin
    // Just set to null to release reference
    mapController = null;

    _logInfo('🗺️ DriverMapController disposed successfully');
  }
}