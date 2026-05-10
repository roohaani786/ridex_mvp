import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

class LocationService extends GetxService {
  static LocationService get to => Get.find();

  StreamSubscription<Position>? _positionStream;
  final Rx<Position?> currentPosition = Rx<Position?>(null);

  Future<LocationService> init() async {
    // init() is a no-op now — permissions are requested on demand
    // so the service can be registered before any UI is ready
    return this;
  }

  /// Call this before starting tracking. Returns true if permission is granted.
  Future<bool> ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Get.snackbar(
        'Location Off',
        'Please enable location services in your device settings.',
        snackPosition: SnackPosition.TOP,
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      Get.snackbar(
        'Permission Denied',
        'Location permission is required for ride sharing.',
        snackPosition: SnackPosition.TOP,
      );
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );
      currentPosition.value = pos;
      return pos;
    } catch (e) {
      // Fallback: get last known position if fresh fix times out
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) currentPosition.value = last;
        return last;
      } catch (_) {
        return null;
      }
    }
  }

  /// Starts a continuous position stream. Calls [onPosition] on every update.
  void startTracking({Function(Position)? onPosition}) {
    // Cancel any existing stream first
    _positionStream?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1, // fire every 1 metre of movement
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      currentPosition.value = pos;
      onPosition?.call(pos);
    }, onError: (e) {
      // Don't crash — just log silently
      debugPrint('Location stream error: $e');
    });
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  @override
  void onClose() {
    stopTracking();
    super.onClose();
  }
}
