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

class ActiveRideController extends GetxController {
  late RideModel ride;

  GoogleMapController? mapController;
  final markers         = RxMap<String, Marker>();
  final polylineCoords  = RxList<LatLng>();
  final memberLocations = RxMap<String, MemberLocation>();
  final memberCount     = RxInt(0);

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

  @override
  void onInit() {
    super.onInit();
    ride = Get.arguments as RideModel;
    rideStatus.value  = ride.status;
    memberCount.value = ride.members.length;
    _loadMarkerIcons();
    _initLocation();
    _watchRide();
    _watchMemberLocations();
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
    _applyPosition(pos, forceRtdbPush: true);

    // LocationService MUST configure its stream with distanceFilter: 5
    // (or you'll still receive sub-metre jitter updates from the OS).
    LocationService.to.startTracking(onPosition: _onNewPosition);
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

    // ── Gate 3: RTDB push throttle ────────────────────────────────────────
    // Only push to Firebase when actually moving (or forced on init).
    // This is the single biggest source of "location updating while stopped".
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

    if (!hasIReached.value && distToEnd <= _destinationThresholdMeters) {
      hasIReached.value = true;
      currentInstruction.value     = 'You have arrived!';
      currentInstructionIcon.value = Icons.flag_rounded;
      await RideService.to.markReached(ride.code, userId);
      Get.snackbar('🎉 Arrived!', 'You have reached the destination.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF43A047),
          colorText: Colors.white,
          duration: const Duration(seconds: 4));
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

  // ─── 7. Distance & ETA ────────────────────────────────────────────────────

  void _updateDistanceAndETA(double distanceMeters, double speedMps) {
    final km = distanceMeters / 1000;
    distanceText.value = km >= 1
        ? '${km.toStringAsFixed(1)} km'
        : '${distanceMeters.toStringAsFixed(0)} m';

    int etaSeconds;
    if (speedMps > 1.0) {
      etaSeconds = (distanceMeters / speedMps).round();
    } else if (_apiDurationSeconds > 0) {
      final totalDist = Geolocator.distanceBetween(
        ride.startLocation.lat, ride.startLocation.lng,
        ride.endLocation.lat,   ride.endLocation.lng,
      );
      if (totalDist == 0) return;
      etaSeconds =
          ((distanceMeters / totalDist) * _apiDurationSeconds).round();
    } else {
      return;
    }

    final minutes = (etaSeconds / 60).round();
    final hours   = minutes ~/ 60;
    final mins    = minutes % 60;
    etaText.value = hours > 0 ? '${hours}h ${mins}m' : '${minutes} min';
  }

  // ─── 8. Directions API ────────────────────────────────────────────────────

  Future<void> _fetchDirections({LatLng? from}) async {
    final originLat = from?.latitude  ?? ride.startLocation.lat;
    final originLng = from?.longitude ?? ride.startLocation.lng;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
            '?origin=$originLat,$originLng'
            '&destination=${ride.endLocation.lat},${ride.endLocation.lng}'
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
    } catch (_) {
      currentInstruction.value =
      'Head to ${ride.endLocation.address.split(',').first}';
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

  // ─── 11. Ride watcher ─────────────────────────────────────────────────────

  void _watchRide() {
    _rideWatcher =
        RideService.to.watchRide(ride.code).listen((updatedRide) {
          if (updatedRide == null) return;
          ride = updatedRide;
          rideStatus.value  = updatedRide.status;
          memberCount.value = updatedRide.members.length;
          if (updatedRide.status == RideStatus.completed)
            _onRideCompleted();
        });
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

  void onMapCreated(GoogleMapController c) => mapController = c;

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