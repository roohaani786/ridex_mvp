import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/ride_model.dart';
import '../routes/app_routes.dart';
import '../services/location_service.dart';
import '../services/ride_service.dart';
import '../services/user_service.dart';
import '../utilities/location_picker_sheet.dart';

class ActiveRideController extends GetxController {
  late RideModel ride;

  GoogleMapController? mapController;
  final markers         = RxMap<String, Marker>();
  final polylineCoords  = RxList<LatLng>();
  final memberLocations = RxMap<String, MemberLocation>();
  final memberCount     = RxInt(0);

  List<LatLng> _baseRoutePoints = [];

  // ── Add with other observables ─────────────────────────────────────────────
  final polylineVersion = RxInt(0);
  final currentPolylines = RxSet<Polyline>();// plain field, no equality issues
  final allRoutes          = RxList<RouteOption>();
  final selectedRouteIndex = RxInt(0);
  final isPreviewingRoute  = RxBool(false);

  final stops              = RxList<LocationPoint>([]);
  final currentStopIndex   = RxInt(0);   // which stop we're heading to next
  final isCreator          = RxBool(false);

  // ── Add with other observables ─────────────────────────────────────────────
  final hasNavigationStarted = RxBool(false);
  final isStartingNavigation = RxBool(false); // loading state for the button

  // ── Observable nav state ──────────────────────────────────────────────────
  final currentInstruction     = RxString('Getting your location...');
  final currentInstructionIcon = Rx<IconData>(Icons.navigation_rounded);
  final etaText                = RxString('');
  final distanceText           = RxString('');
  final isFollowingMe          = RxBool(true);
  final rideStatus             = Rx<RideStatus>(RideStatus.active);
  final hasIReached            = RxBool(false);
  final isLocationReady        = RxBool(false);
  final currentSpeedKmh        = RxDouble(0.0);

  // ── Navigation internals ──────────────────────────────────────────────────
  List<_NavStep> _steps = [];
  int    _currentStepIndex   = 0;
  int    _apiDurationSeconds = 0;
  LatLng? _lastDirectionsFetchOrigin;
  bool   _isRerouting = false;

  // ── Last accepted position (for displacement & RTDB throttle gates) ───────
  Position? _lastAcceptedPosition;

  // ── Heading smoothing (EMA) ───────────────────────────────────────────────
  double _smoothedHeading = 0.0;
  static const _headingAlpha = 0.25;

  // ─────────────────────────────────────────────────────────────────────────
  // FILTER GATES  — these run FIRST in _onNewPosition and drop noisy fixes
  // before any marker / Firebase / camera update fires.
  // ─────────────────────────────────────────────────────────────────────────

  /// Discard any fix whose reported accuracy is worse than this.
  /// 20 m is the typical "good enough for in-car nav" threshold.
  /// Tighten to 15 m if your test devices consistently achieve that.
  static const _minAccuracyMeters = 20.0;

  /// Minimum physical displacement before we treat a fix as "new".
  /// GPS jitter on a stationary phone is typically 3-10 m.
  /// 8 m avoids false movement while still catching slow parking-lot speeds.
  static const _minDisplacementMeters = 8.0;

  /// Below this speed the rider is considered stationary.
  /// We still accept the position for map snapping but skip the
  /// expensive Firebase RTDB push to avoid wasting bandwidth.
  static const _minMovingSpeedMs = 0.5; // ≈ 1.8 km/h

  // ─────────────────────────────────────────────────────────────────────────
  // NAVIGATION CONSTANTS
  // ─────────────────────────────────────────────────────────────────────────

  static const _rerouteCheckIntervalMeters          = 20.0;
  static const _baseDeviationThresholdMeters        = 35.0;
  static const _highSpeedMs                         = 25.0; // ≈ 90 km/h
  static const _highSpeedDeviationThresholdMeters   = 55.0;
  static const _minRerouteDistanceMeters            = 250.0;
  static const _destinationThresholdMeters          = 50.0;
  static const _stepAdvanceLowSpeedMeters           = 20.0;
  static const _stepAdvanceHighSpeedMeters          = 60.0;
  static const _stepAdvanceSpeedThresholdMs         = 5.5;  // ≈ 20 km/h

  // ── Camera zoom levels ────────────────────────────────────────────────────
  static const _zoomParked  = 18.0;
  static const _zoomCity    = 17.0;
  static const _zoomHighway = 15.5;
  static const _tiltRiding  = 50.0;
  static const _tiltBirdEye = 0.0;

  // ── Misc ──────────────────────────────────────────────────────────────────
  StreamSubscription? _rideWatcher;
  StreamSubscription? _locationWatcher;
  BitmapDescriptor?   _myMarkerIcon;
  BitmapDescriptor?   _partnerMarkerIcon;
  static const _googleMapsApiKey = 'AIzaSyAF-9v8atdEyUpdgmcfvK2HEsxo6ffbYEk';

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  // ── Add with other observables ─────────────────────────────────────────────
  final mapType    = Rx<MapType>(MapType.normal);
  final isDarkMode = RxBool(true);

// ── Map styles (same as LocationPickerController) ─────────────────────────
  static const _darkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#e0e0e0"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a1a2e"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2d2d44"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#3d3d5c"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#1a1a2e"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373755"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#4a4a7a"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#5a5a8a"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#cccccc"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d1b2a"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.text","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.medical","elementType":"geometry","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.medical","elementType":"labels","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.medical","elementType":"labels.text.fill","stylers":[{"color":"#e05252"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0d2137","visibility":"on"}]},
  {"featureType":"poi.park","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]''';

  static const _lightMapStyle = '''[
  {"featureType":"poi","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.text","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.medical","elementType":"geometry","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.medical","elementType":"labels","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.medical","elementType":"labels.text.fill","stylers":[{"color":"#cc0000"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.park","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]''';

// ── Methods ───────────────────────────────────────────────────────────────
  void toggleMapTheme() {
    isDarkMode.value = !isDarkMode.value;
    _applyMapTheme();
  }

  void _applyMapTheme() async {
    try {
      await mapController?.setMapStyle(
        isDarkMode.value ? _darkMapStyle : _lightMapStyle,
      );
    } catch (e) {
      debugPrint('Map style warning: $e');
    }
  }

  void toggleMapType() {
    mapType.value = mapType.value == MapType.normal
        ? MapType.satellite
        : MapType.normal;
    if (mapType.value == MapType.normal) _applyMapTheme();
  }

  void zoomIn()  => mapController?.animateCamera(CameraUpdate.zoomIn());
  void zoomOut() => mapController?.animateCamera(CameraUpdate.zoomOut());

  // ── Update onInit — remove _initLocation() call ────────────────────────────
  @override
  void onInit() {
    super.onInit();
    ride = Get.arguments as RideModel;
    rideStatus.value  = ride.status;
    memberCount.value = ride.members.length;
    _loadMarkerIcons();
    // _initLocation() ← REMOVED, called only on user tap now
    _watchRide();
    _watchMemberLocations();
    currentInstruction.value = 'Tap Start Navigation to begin';
    stops.assignAll(ride.stops);
    isCreator.value = ride.creatorId == UserService.to.userId;
  }

  // ── Add public startNavigation method ─────────────────────────────────────
  Future<void> startNavigation() async {
    if (hasNavigationStarted.value || isStartingNavigation.value) return;
    isStartingNavigation.value = true;
    await _initLocation();
    hasNavigationStarted.value = true;
    isStartingNavigation.value = false;
  }

  // ── Fix _updateDistanceAndETA — stop returning silently, always show something
  void _updateDistanceAndETA(double distanceMeters, double speedMps) {
    final km = distanceMeters / 1000;
    distanceText.value = km >= 1
        ? '${km.toStringAsFixed(1)} km'
        : '${distanceMeters.toStringAsFixed(0)} m';

    if (speedMps > 1.0) {
      // Moving — calculate from live speed
      final etaSeconds = (distanceMeters / speedMps).round();
      final minutes    = (etaSeconds / 60).round();
      final hours      = minutes ~/ 60;
      final mins       = minutes % 60;
      etaText.value    = hours > 0 ? '${hours}h ${mins}m' : '${minutes} min';
    } else if (_apiDurationSeconds > 0) {
      // Stationary — scale API estimate by remaining distance ratio
      final totalDist = Geolocator.distanceBetween(
        ride.startLocation.lat, ride.startLocation.lng,
        ride.endLocation.lat,   ride.endLocation.lng,
      );
      if (totalDist == 0) return;
      final remaining  = distanceMeters / totalDist;
      final etaSeconds = (remaining * _apiDurationSeconds).round();
      final minutes    = (etaSeconds / 60).round();
      final hours      = minutes ~/ 60;
      final mins       = minutes % 60;
      etaText.value    = hours > 0 ? '${hours}h ${mins}m' : '${minutes} min';
    }
    // ← No early return — distanceText is always updated above regardless
  }

  // ─── 1. Location initialisation ───────────────────────────────────────────

  Future<void> _initLocation() async {
    final granted = await LocationService.to.ensurePermissions();
    if (!granted) {
      currentInstruction.value = 'Location permission denied';
      Get.snackbar('Permission Required',
          'Please grant location permission to navigate.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red,
          colorText: Colors.white);
      return;
    }

    isLocationReady.value = true;
    currentInstruction.value = 'Starting navigation...';

    // Warm up GPS — wait for a fix that actually meets our accuracy gate.
    // Retries up to 3 times with increasing timeouts.
    Position? pos;
    for (final timeout in [5, 10, 15]) {
      try {
        final candidate = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: timeout),
        );
        if (candidate.accuracy <= _minAccuracyMeters) {
          pos = candidate;
          break;
        }
        // Fix was too noisy — try again with more time.
      } catch (_) {}
    }

    // If we never got a clean fix, use whatever the last attempt gave us.
    pos ??= await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

    _lastAcceptedPosition   = pos;
    _smoothedHeading        = pos.heading;
    final origin            = LatLng(pos.latitude, pos.longitude);
    _lastDirectionsFetchOrigin = origin;

    await _fetchDirections(from: origin);
    // ── Force 3D perspective immediately on navigation start ──────────────────
// _applyPosition uses speedMs > 1.0 to decide tilt — but at init speed = 0
// so it would stay flat. We override here with the cinematic entry instead.
    await _animateToNavStart(origin, _smoothedHeading);
    _applyPosition(pos, forceRtdbPush: true);

    // LocationService MUST configure its stream with distanceFilter: 5
    // (or you'll still receive sub-metre jitter updates from the OS).
    LocationService.to.startTracking(onPosition: _onNewPosition);
  }

  Future<void> _animateToNavStart(LatLng origin, double heading) async {
    // Step 1 — snap to overhead first (instant context)
    await mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target:  origin,
        zoom:    _zoomCity,
        bearing: 0,
        tilt:    0,
      )),
    );

    // Step 2 — brief pause so the user sees their position
    await Future.delayed(const Duration(milliseconds: 400));

    // Step 3 — cinematic tilt into 3D navigation perspective
    await mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target:  origin,
        zoom:    _zoomCity,
        bearing: heading,      // ← rotate to face direction of travel
        tilt:    _tiltRiding,  // ← 50.0 — full 3D
      )),
    );
  }

  // ─── 2. Position gate — runs before ANYTHING else ─────────────────────────

  /// Called by the LocationService stream for every OS fix.
  /// Drops bad fixes so nothing downstream ever sees GPS noise.
  Future<void> _onNewPosition(Position position) async {

    // ── Gate 1: accuracy ─────────────────────────────────────────────────────
    // If the OS says the fix radius is > _minAccuracyMeters, throw it away.
    // A stationary phone with a weak signal still reports a position every
    // second — accuracy is the only reliable signal that the fix is useless.
    if (position.accuracy > _minAccuracyMeters) return;

    // ── Gate 2: displacement ─────────────────────────────────────────────────
    // If the user hasn't physically moved at least _minDisplacementMeters,
    // the fix is GPS jitter — skip it entirely.
    if (_lastAcceptedPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastAcceptedPosition!.latitude,
        _lastAcceptedPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (moved < _minDisplacementMeters) return;
    }

    // Fix is good — store it and proceed.
    _lastAcceptedPosition = position;
    _applyPosition(position, forceRtdbPush: false);
  }

  // ─── 3. Apply a validated position ────────────────────────────────────────

  Future<void> _applyPosition(Position position,
      {required bool forceRtdbPush}) async {
    final userId  = UserService.to.userId;
    final speedMs = position.speed < 0 ? 0.0 : position.speed;
    currentSpeedKmh.value = speedMs * 3.6;

    _smoothedHeading =
        _lerpAngle(_smoothedHeading, position.heading, _headingAlpha);
    final latLng = LatLng(position.latitude, position.longitude);

    final isMoving = speedMs >= _minMovingSpeedMs;
    if (forceRtdbPush || isMoving) {
      RideService.to.updateMyLocation(
        ride.code,
        MemberLocation(
          userId: userId,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          speed: speedMs,
          heading: position.heading,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    _updateMyMarker(latLng, _smoothedHeading);

    if (isFollowingMe.value) {
      _animateCameraToRider(latLng, _smoothedHeading, speedMs);
    }

    final distToEnd = Geolocator.distanceBetween(
      position.latitude, position.longitude,
      ride.endLocation.lat, ride.endLocation.lng,
    );

    _updateDistanceAndETA(distToEnd, speedMs);
    _updateCurrentStep(latLng, speedMs);

    if (!hasIReached.value) {
      _checkAndReroute(latLng, speedMs);
    }

    // ── Stop arrival check (50m — BDD Scenario 5.2) ──────────────────────────
    if (hasNavigationStarted.value && currentStopIndex.value < stops.length) {
      final nextStop = stops[currentStopIndex.value];
      final distToStop = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        nextStop.lat, nextStop.lng,
      );
      if (distToStop <= 50.0) {
        final stopName = nextStop.address.split(',').first;
        currentStopIndex.value++;
        _updateStopMarkers();
        Get.snackbar(
          '📍 Stop Reached',
          'You have arrived at Stop: $stopName',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFFFF8C00),
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
    }

    // ── End destination arrival (100m — BDD Scenario 5.3) ────────────────────
    if (!hasIReached.value && distToEnd <= _destinationThresholdMeters) {
      hasIReached.value = true;
      currentInstruction.value     = 'You have arrived!';
      currentInstructionIcon.value = Icons.flag_rounded;
      await RideService.to.markReached(ride.code, userId);
      Get.snackbar(
        '🎉 Arrived!',
        'You have reached the destination.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF43A047),
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }

  // ─── 4. Speed-adaptive camera ─────────────────────────────────────────────

  void _animateCameraToRider(LatLng pos, double heading, double speedMs) {
    mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target:  pos,
        zoom:    _speedToZoom(speedMs),
        bearing: heading,
        tilt:    speedMs > 1.0 ? _tiltRiding : _tiltBirdEye,
      )),
    );
  }

  double _speedToZoom(double speedMs) {
    final kmh = speedMs * 3.6;
    if (kmh < 5)  return _zoomParked;
    if (kmh < 90) {
      final t = (kmh - 5) / (90 - 5);
      return _zoomCity + (_zoomHighway - _zoomCity) * t;
    }
    return _zoomHighway;
  }

  // ─── 5. Marker update ─────────────────────────────────────────────────────

  void _updateMyMarker(LatLng latLng, double heading) {
    if (_myMarkerIcon == null) return;
    markers['me'] = Marker(
      markerId: const MarkerId('me'),
      position: latLng,
      icon: _myMarkerIcon!,
      anchor: const Offset(0.5, 0.5),
      rotation: heading,
      flat: true,
      infoWindow:
      InfoWindow(title: UserService.to.userName, snippet: 'You'),
      zIndex: 2,
    );
  }

  // ─── 6. Speed-adaptive turn-by-turn ───────────────────────────────────────

  void _updateCurrentStep(LatLng current, double speedMs) {
    if (_steps.isEmpty || _currentStepIndex >= _steps.length) return;

    final advanceDist = speedMs >= _stepAdvanceSpeedThresholdMs
        ? _stepAdvanceHighSpeedMeters
        : _stepAdvanceLowSpeedMeters;

    final step          = _steps[_currentStepIndex];
    final distToStepEnd = Geolocator.distanceBetween(
      current.latitude, current.longitude,
      step.endLat, step.endLng,
    );

    if (distToStepEnd < advanceDist &&
        _currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
      final next = _steps[_currentStepIndex];
      currentInstruction.value     = next.instruction;
      currentInstructionIcon.value = next.icon;
    } else {
      currentInstruction.value     = step.instruction;
      currentInstructionIcon.value = step.icon;
    }
  }

  Future<void> _fetchDirections({LatLng? from}) async {
    final originLat = from?.latitude  ?? ride.startLocation.lat;
    final originLng = from?.longitude ?? ride.startLocation.lng;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
            '?origin=$originLat,$originLng'
            '&destination=${ride.endLocation.lat},${ride.endLocation.lng}'
            '${_buildWaypointsParam(stops)}'
            '&mode=driving'
            '&alternatives=true'
            '&departure_time=now'
            '&traffic_model=best_guess'
            '&key=$_googleMapsApiKey',
      );

      final response =
      await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') {
        currentInstruction.value =
        'Head to ${ride.endLocation.address.split(',').first}';
        return;
      }

      final routes =
      (data['routes'] as List).cast<Map<String, dynamic>>();
      Map<String, dynamic>? bestRoute;
      int bestDuration = 999999;

      for (final r in routes) {
        final leg = (r['legs'] as List).first as Map<String, dynamic>;
        final dur =
        ((leg['duration_in_traffic'] ?? leg['duration'])['value'] as num)
            .toInt();
        if (dur < bestDuration) {
          bestDuration = dur;
          bestRoute    = r;
        }
      }

      final route = bestRoute ?? routes.first;
      final leg   = (route['legs'] as List).first as Map<String, dynamic>;
      _apiDurationSeconds = bestDuration;

      _steps = (leg['steps'] as List).map((s) {
        final step   = s as Map<String, dynamic>;
        final endLoc = step['end_location'] as Map<String, dynamic>;
        return _NavStep(
          instruction:
          _stripHtml(step['html_instructions'] as String? ?? ''),
          icon: _maneuverIcon(step['maneuver'] as String? ?? ''),
          endLat: (endLoc['lat'] as num).toDouble(),
          endLng: (endLoc['lng'] as num).toDouble(),
          distanceMeters:
          (step['distance']['value'] as num).toDouble(),
        );
      }).toList();

      _currentStepIndex = 0;
      if (_steps.isNotEmpty) {
        currentInstruction.value     = _steps.first.instruction;
        currentInstructionIcon.value = _steps.first.icon;
      }

      polylineCoords.assignAll(
        _decodePolyline(
            route['overview_polyline']['points'] as String),
      );

      if (!markers.containsKey('end')) {
        markers['end'] = Marker(
          markerId: const MarkerId('end'),
          position:
          LatLng(ride.endLocation.lat, ride.endLocation.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
              title: 'Destination',
              snippet: ride.endLocation.address),
        );
      }

      final mins = (_apiDurationSeconds / 60).round();
      final hrs  = mins ~/ 60;
      final m    = mins % 60;
      etaText.value = hrs > 0 ? '${hrs}h ${m}m' : '${m} min';

      final km = (leg['distance']['value'] as num) / 1000;
      distanceText.value = '${km.toStringAsFixed(1)} km';
      // ── In _fetchDirections, replace the catch block ───────────────────────────
    } catch (e) {
      debugPrint('Directions fetch error: $e');
      currentInstruction.value =
      'Head to ${ride.endLocation.address.split(',').first}';
      // Set a fallback so ETA doesn't stay on Calculating
      if (etaText.value.isEmpty) etaText.value = 'Est. unavailable';
    }
  }

  // ─── 9. Speed-adaptive reroute ────────────────────────────────────────────

  double _dynamicDeviation(double speedMs) {
    if (speedMs >= _highSpeedMs)
      return _highSpeedDeviationThresholdMeters;
    final t = speedMs / _highSpeedMs;
    return _baseDeviationThresholdMeters +
        (_highSpeedDeviationThresholdMeters -
            _baseDeviationThresholdMeters) *
            t;
  }

  void _checkAndReroute(LatLng current, double speedMs) {
    if (_isRerouting || polylineCoords.isEmpty) return;
    if (_lastDirectionsFetchOrigin == null) return;

    final movedSinceFetch = Geolocator.distanceBetween(
      _lastDirectionsFetchOrigin!.latitude,
      _lastDirectionsFetchOrigin!.longitude,
      current.latitude,
      current.longitude,
    );
    if (movedSinceFetch < _rerouteCheckIntervalMeters) return;

    final deviation = _distanceToPolyline(current);
    final threshold = _dynamicDeviation(speedMs);

    if (deviation > threshold) {
      if (movedSinceFetch < _minRerouteDistanceMeters) return;

      _isRerouting = true;
      currentInstruction.value     = 'Rerouting...';
      currentInstructionIcon.value = Icons.sync_rounded;

      _lastDirectionsFetchOrigin = current;
      _fetchDirections(from: current)
          .then((_) => _isRerouting = false);
    }
  }

  double _distanceToPolyline(LatLng point) {
    double min = double.infinity;
    for (final p in polylineCoords) {
      final d = Geolocator.distanceBetween(
          point.latitude, point.longitude, p.latitude, p.longitude);
      if (d < min) min = d;
    }
    return min;
  }

  // ─── 10. Partner live locations ───────────────────────────────────────────

  void _watchMemberLocations() {
    _locationWatcher?.cancel();

    _locationWatcher =
        RideService.to.watchLocations(ride.code).listen(
              (locations) {

            memberLocations.assignAll(locations);

            final myId = UserService.to.userId;

            // REMOVE OLD MARKERS
            final validIds = locations.keys.toSet();

            markers.removeWhere((key, value) {
              if (key == 'me' || key == 'end') return false;
              if (key.startsWith('stop_')) return false;  // ← protect stop markers
              return !validIds.contains(key);
            });

            // markers.refresh();

            for (final entry in locations.entries) {
              try {
                if (entry.key == myId) continue;

                final latLng =
                LatLng(entry.value.lat, entry.value.lng);

                RideMember? member;

                try {
                  member = ride.members.values.firstWhere(
                        (m) => m.userId == entry.key,
                  );
                } catch (_) {}

                _updatePartnerMarker(
                  entry.key,
                  latLng,
                  entry.value.heading,
                  member?.name ?? 'Partner',
                );

              } catch (e, s) {
                debugPrint('Location entry error: $e\n$s');
              }
            }
          },
        );
  }

  void _updatePartnerMarker(
      String id, LatLng latLng, double heading, String name) {
    if (_partnerMarkerIcon == null) return;
    markers[id] = Marker(
      markerId: MarkerId(id),
      position: latLng,
      icon: _partnerMarkerIcon!,
      anchor: const Offset(0.5, 0.5),
      rotation: heading,
      flat: true,
      infoWindow: InfoWindow(title: name),
      zIndex: 1,
    );
    // markers.refresh();
  }

  void _updateStopMarkers() {
    // Remove old stop markers
    markers.removeWhere((key, _) => key.startsWith('stop_'));

    for (int i = 0; i < stops.length; i++) {
      final stop   = stops[i];
      final reached = i < currentStopIndex.value;
      markers['stop_$i'] = Marker(
        markerId: MarkerId('stop_$i'),
        position: LatLng(stop.lat, stop.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          reached ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
        ),
        infoWindow: InfoWindow(
          title: 'Stop ${i + 1}',
          snippet: stop.address,
        ),
        zIndex: 1,
      );
    }
  }

  // ── Build waypoints string from stops ─────────────────────────────────────
  String _buildWaypointsParam(List<LocationPoint> stopList) {
    if (stopList.isEmpty) return '';
    final waypoints = stopList
        .map((s) => '${s.lat},${s.lng}')
        .join('|');
    return '&waypoints=optimize:false|$waypoints';
  }

  // ─── 11. Ride watcher ─────────────────────────────────────────────────────

  void _watchRide() {
    _rideWatcher = RideService.to.watchRide(ride.code).listen((updatedRide) {
      if (updatedRide == null) return;
      ride = updatedRide;
      rideStatus.value  = updatedRide.status;
      memberCount.value = updatedRide.members.length;

      // ── Sync stops — rebuilds polyline and markers automatically ──────────
      if (!_listsEqual(stops, updatedRide.stops)) {
        stops.assignAll(updatedRide.stops);
        _updateStopMarkers();
        if (!hasNavigationStarted.value) {
          _previewRoute(); // re-preview with new stops
        }
      }

      if (updatedRide.status == RideStatus.completed) _onRideCompleted();
    });
  }

  bool _listsEqual(List<LocationPoint> a, List<LocationPoint> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].lat != b[i].lat || a[i].lng != b[i].lng) return false;
    }
    return true;
  }

  void _onRideCompleted() {
    Get.defaultDialog(
      title: '🏁 Ride Completed',
      middleText: 'All riders have reached the destination!',
      textConfirm: 'OK',
      confirmTextColor: Colors.white,
      onConfirm: () => Get.offAllNamed(AppRoutes.home),
    );
  }

  // ─── 12. UI actions ───────────────────────────────────────────────────────

  Future<void> _previewRoute() async {
    isPreviewingRoute.value = true;
    try {
      debugPrint('_previewRoute: starting fetch...');

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
            '?origin=${ride.startLocation.lat},${ride.startLocation.lng}'
            '&destination=${ride.endLocation.lat},${ride.endLocation.lng}'
            '${_buildWaypointsParam(stops)}'
            '&mode=driving'
            '&alternatives=true'
            '&key=$_googleMapsApiKey',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));
      debugPrint('_previewRoute: status ${response.statusCode}');
      debugPrint('_previewRoute: body ${response.body}');

      if (response.statusCode != 200) {
        debugPrint('_previewRoute: bad HTTP status, aborting');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('_previewRoute: API status = ${data['status']}');

      if (data['status'] != 'OK') {
        debugPrint('_previewRoute: API error = ${data['error_message']}');
        return;
      }

      final routes = (data['routes'] as List).cast<Map<String, dynamic>>();
      debugPrint('_previewRoute: got ${routes.length} routes');

      final options = <RouteOption>[];
      for (final r in routes) {
        final leg     = (r['legs'] as List).first as Map<String, dynamic>;
        final dur     = (leg['duration']['value'] as num).toInt();
        final dist    = (leg['distance']['value'] as num).toDouble();
        final summary = r['summary'] as String? ?? '';
        final points  = _decodePolyline(
            r['overview_polyline']['points'] as String);

        final mins  = (dur / 60).round();
        final hours = mins ~/ 60;
        final m     = mins % 60;

        options.add(RouteOption(
          points:          points,
          duration:        hours > 0 ? '${hours}h ${m}m' : '$mins min',
          distance:        dist >= 1000
              ? '${(dist / 1000).toStringAsFixed(1)} km'
              : '${dist.toStringAsFixed(0)} m',
          summary:         summary.isNotEmpty
              ? 'via $summary'
              : 'Route ${options.length + 1}',
          durationSeconds: dur,
        ));
      }

      debugPrint('_previewRoute: built ${options.length} route options');

      allRoutes.assignAll(options);
      selectedRouteIndex.value = 0;

      // Cache the clean base route only once, before any stops are added
      if (_baseRoutePoints.isEmpty && options.isNotEmpty) {
        _baseRoutePoints = List.from(options[0].points);
        debugPrint('_previewRoute: cached base route with ${_baseRoutePoints.length} points');
      }

      _rebuildPolylines();
      debugPrint('_previewRoute: polylines rebuilt, count = ${polylineCoords.length}');

      // Destination marker
      markers['end'] = Marker(
        markerId: const MarkerId('end'),
        position: LatLng(ride.endLocation.lat, ride.endLocation.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Destination',
          snippet: ride.endLocation.address,
        ),
      );

      // Stop markers
      _updateStopMarkers();

      // Fit camera to selected route
      await Future.delayed(const Duration(milliseconds: 300));
      _fitRouteOnMap(options[0].points);

    } catch (e, s) {
      debugPrint('_previewRoute ERROR: $e\n$s');
    } finally {
      isPreviewingRoute.value = false;
    }
  }

  void _rebuildPolylines() {
    try {
      final newPolylines = <Polyline>{};

      if (_baseRoutePoints.isNotEmpty && stops.isNotEmpty) {
        newPolylines.add(Polyline(
          polylineId: const PolylineId('base_route'),
          points:     _baseRoutePoints,
          color:      const Color(0xFFBBBBBB),
          width:      3,
          geodesic:   true,
          zIndex:     0,
        ));
      }

      for (int i = 0; i < allRoutes.length; i++) {
        final isSelected = i == selectedRouteIndex.value;
        newPolylines.add(Polyline(
          polylineId: PolylineId('route_$i'),
          points:     allRoutes[i].points,
          color:      isSelected
              ? const Color(0xFF4A90E2)
              : const Color(0xFF9E9E9E),
          width:      isSelected ? 7 : 4,
          startCap:   Cap.roundCap,
          endCap:     Cap.roundCap,
          jointType:  JointType.round,
          geodesic:   true,
          zIndex:     isSelected ? 2 : 1,
        ));
      }

      currentPolylines.assignAll(newPolylines);
      polylineVersion.value++;

      if (allRoutes.isNotEmpty) {
        polylineCoords.assignAll(allRoutes[selectedRouteIndex.value].points);
      }
    } catch (e, s) {
      debugPrint('_rebuildPolylines ERROR: $e\n$s');
    }
  }

  void selectRoute(int index) {
    if (index < 0 || index >= allRoutes.length) return;
    selectedRouteIndex.value = index;
    _rebuildPolylines();
    // refresh();
  }

  void _fitRouteOnMap(List<LatLng> points) {
    if (points.isEmpty) return;
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.005, minLng - 0.005),
        northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
      ),
      80,
    ));
  }

  void onMapCreated(GoogleMapController c) {
    mapController = c;
    _applyMapTheme();
    _previewRoute(); // ← show route before navigation starts
  }

  void toggleFollowMe() {
    isFollowingMe.toggle();
    if (isFollowingMe.value && _lastAcceptedPosition != null) {
      final pos = _lastAcceptedPosition!;
      _animateCameraToRider(
        LatLng(pos.latitude, pos.longitude),
        _smoothedHeading,
        pos.speed < 0 ? 0 : pos.speed,
      );
    }
  }

  void focusOnMember(String userId) {
    RideMember? member;
    try {
      member =
          ride.members.values.firstWhere((m) => m.userId == userId);
    } catch (_) {
      return;
    }
    final loc    = memberLocations[userId];
    final target = loc != null
        ? LatLng(loc.lat, loc.lng)
        : getMemberLatLng(member);

    isFollowingMe.value = false;
    mapController?.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: target, zoom: 17, tilt: 30),
    ));
    final marker = markers[userId];
    if (marker != null)
      mapController?.showMarkerInfoWindow(marker.markerId);
  }

  void fitAllRiders() {
    isFollowingMe.value = false;
    final positions = [
      ...memberLocations.values.map((l) => LatLng(l.lat, l.lng)),
      LatLng(ride.endLocation.lat, ride.endLocation.lng),
    ];
    if (positions.isEmpty) return;

    var minLat = positions.first.latitude;
    var maxLat = positions.first.latitude;
    var minLng = positions.first.longitude;
    var maxLng = positions.first.longitude;

    for (final p in positions) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.002, minLng - 0.002),
        northeast: LatLng(maxLat + 0.002, maxLng + 0.002),
      ),
      80,
    ));
  }

  void onSOS() {
    Get.defaultDialog(
      title: '🆘 SOS',
      middleText: 'This will share your precise location. Proceed?',
      textConfirm: 'Send SOS',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      onConfirm: () {
        Get.back();
        Get.snackbar('SOS Sent', 'Your location has been shared.',
            backgroundColor: Colors.red, colorText: Colors.white);
      },
    );
  }

  void endRide() {
    Get.defaultDialog(
      title: 'End Ride?',
      middleText: 'End this ride for everyone?',
      textConfirm: 'End Ride',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      onConfirm: () async {
        Get.back();
        await RideService.to.endRide(ride.code);
        Get.offAllNamed(AppRoutes.home);
      },
    );
  }

  Future<void> addStop(LocationPoint stop) async {
    if (!isCreator.value) return;
    await RideService.to.addStop(ride.code, stop);
  }

  Future<void> removeStop(int index) async {
    if (!isCreator.value) return;
    await RideService.to.removeStop(ride.code, index);
  }

  Future<void> reorderStops(List<LocationPoint> reordered) async {
    if (!isCreator.value) return;
    await RideService.to.reorderStops(ride.code, reordered);
  }

  // Future<void> pickAndAddStop() async {
  //   final result = await Get.toNamed(AppRoutes.locationPicker);
  //   if (result != null && result is LocationPoint) {
  //     await addStop(result);
  //   }
  // }

  Future<void> pickAndAddStop() async {
    Get.bottomSheet(
      LocationPickerSheet(
        polylines: currentPolylines.toSet(),
        onLocationSelected: (location) async {
          Get.back();
          await addStop(location);
        },
      ),
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
    );
  }


  // ─── Getters ──────────────────────────────────────────────────────────────

  String           get rideCode => ride.code;
  List<RideMember> get members  => ride.members.values.toList();
  String           get myUserId => UserService.to.userId;

  RideMember? get partnerMember => ride.members.values
      .where((m) => m.userId != UserService.to.userId)
      .firstOrNull;

  LatLng getMemberLatLng(RideMember member) {
    final live = memberLocations[member.userId];
    if (live != null) return LatLng(live.lat, live.lng);
    return LatLng(ride.startLocation.lat, ride.startLocation.lng);
  }

  // ─── 13. Marker icon generation ───────────────────────────────────────────

  Future<void> _loadMarkerIcons() async {
    _myMarkerIcon =
    await _createCircleMarker(const Color(0xFF5C6BC0), 'ME');
    _partnerMarkerIcon =
    await _createCircleMarker(const Color(0xFFE91E63), 'A');
  }

  Future<BitmapDescriptor> _createCircleMarker(
      Color color, String text) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    const size     = 80.0;

    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2,
        Paint()..color = color);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 2,
      Paint()
        ..color       = Colors.white
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    if (text.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset((size - tp.width) / 2, (size - tp.height) / 2));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes =
    await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  double _lerpAngle(double current, double target, double alpha) {
    var diff = (target - current) % 360;
    if (diff > 180)  diff -= 360;
    if (diff < -180) diff += 360;
    return (current + diff * alpha) % 360;
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      shift = result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<div[^>]*>'), ' — ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#160;', ' ')
      .trim();

  IconData _maneuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn-left':
      case 'ramp-left':
      case 'fork-left':         return Icons.turn_left_rounded;
      case 'turn-right':
      case 'ramp-right':
      case 'fork-right':        return Icons.turn_right_rounded;
      case 'turn-slight-left':  return Icons.turn_slight_left_rounded;
      case 'turn-slight-right': return Icons.turn_slight_right_rounded;
      case 'turn-sharp-left':   return Icons.turn_sharp_left_rounded;
      case 'turn-sharp-right':  return Icons.turn_sharp_right_rounded;
      case 'uturn-left':
      case 'uturn-right':       return Icons.u_turn_left_rounded;
      case 'roundabout-left':
      case 'roundabout-right':  return Icons.roundabout_left_rounded;
      case 'merge':             return Icons.merge_rounded;
      default:                  return Icons.navigation_rounded;
    }
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────

  @override
  void onClose() {
    _rideWatcher?.cancel();
    _locationWatcher?.cancel();
    LocationService.to.stopTracking();
    mapController?.dispose();
    super.onClose();
  }
}

// ─── Nav step ─────────────────────────────────────────────────────────────────

class _NavStep {
  final String   instruction;
  final IconData icon;
  final double   endLat;
  final double   endLng;
  final double   distanceMeters;

  const _NavStep({
    required this.instruction,
    required this.icon,
    required this.endLat,
    required this.endLng,
    required this.distanceMeters,
  });
}