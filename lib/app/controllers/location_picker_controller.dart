import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/ride_model.dart';
import '../services/location_service.dart';

class LocationPickerController extends GetxController {
  GoogleMapController? mapController;

  bool _mapReady = false;

  final selectedPosition = Rx<LatLng?>(null);
  final selectedAddress = RxString('');
  final isLoadingAddress = RxBool(false);
  final isLoadingLocation = RxBool(false);

  // Search
  final searchController = TextEditingController();
  final searchResults = RxList<Location>([]);
  final isSearching = RxBool(false);

  @override
  void onInit() {
    super.onInit();
    // _goToCurrentLocation();
  }

  void onMapCreated(GoogleMapController controller) async {
    mapController = controller;
    _mapReady = true;

    await _goToCurrentLocation();
  }

  Future<void> _goToCurrentLocation() async {
    try {
      isLoadingLocation.value = true;

      final granted = await LocationService.to.ensurePermissions();

      if (!granted) {
        isLoadingLocation.value = false;
        return;
      }

      final pos = await LocationService.to.getCurrentPosition();

      if (pos == null) {
        isLoadingLocation.value = false;
        return;
      }

      final latLng = LatLng(pos.latitude, pos.longitude);

      selectedPosition.value = latLng;

      if (!_mapReady || mapController == null) {
        isLoadingLocation.value = false;
        return;
      }

      await mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng,
            zoom: 16,
          ),
        ),
      );

      try {
        await _reverseGeocode(latLng);
      } catch (e) {
        debugPrint('Reverse geocode failed: $e');
      }

    } catch (e, stack) {
      debugPrint('Current location failed');
      debugPrint(e.toString());
      debugPrint(stack.toString());
    } finally {
      isLoadingLocation.value = false;
    }
  }

  void onCameraMove(CameraPosition position) {
    selectedPosition.value = position.target;
  }

  void onCameraIdle() {
    if (selectedPosition.value != null) {
      _reverseGeocode(selectedPosition.value!);
    }
  }

  Future<void> _reverseGeocode(LatLng latLng) async {
    isLoadingAddress.value = true;
    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.name,
          p.subLocality,
          p.locality,
        ].where((s) => s != null && s.isNotEmpty).toList();
        selectedAddress.value = parts.join(', ');
      }
    } catch (_) {
      selectedAddress.value = '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
    } finally {
      isLoadingAddress.value = false;
    }
  }

  Future<void> searchLocation(String query) async {
    if (query.trim().isEmpty) {
      searchResults.clear();
      return;
    }
    isSearching.value = true;
    try {
      final locations = await locationFromAddress(query);
      searchResults.assignAll(locations);
    } catch (_) {
      searchResults.clear();
    } finally {
      isSearching.value = false;
    }
  }

  void selectSearchResult(Location location) {
    final latLng = LatLng(location.latitude, location.longitude);
    selectedPosition.value = latLng;
    searchResults.clear();
    searchController.clear();
    mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: latLng, zoom: 16),
      ),
    );
    _reverseGeocode(latLng);
  }

  void goToMyLocation() => _goToCurrentLocation();

  void confirmLocation() {
    if (selectedPosition.value == null) return;
    final point = LocationPoint(
      lat: selectedPosition.value!.latitude,
      lng: selectedPosition.value!.longitude,
      address: selectedAddress.value,
    );
    Get.back(result: point);
  }

  @override
  void onClose() {
    mapController?.dispose();
    searchController.dispose();
    super.onClose();
  }
}
