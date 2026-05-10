import 'package:get/get.dart';
import '../models/ride_model.dart';
import '../routes/app_routes.dart';
import '../services/ride_service.dart';

class CreateRideController extends GetxController {
  final startLocation = Rx<LocationPoint?>(null);
  final endLocation = Rx<LocationPoint?>(null);
  final isLoading = RxBool(false);

  bool get canCreate =>
      startLocation.value != null && endLocation.value != null;

  Future<void> pickStartLocation() async {
    final result = await Get.toNamed(AppRoutes.locationPicker);
    if (result != null && result is LocationPoint) {
      startLocation.value = result;
    }
  }

  Future<void> pickEndLocation() async {
    final result = await Get.toNamed(AppRoutes.locationPicker);
    if (result != null && result is LocationPoint) {
      endLocation.value = result;
    }
  }

  Future<void> createRide() async {
    if (!canCreate) return;

    isLoading.value = true;

    try {
      final start = startLocation.value!;
      final end = endLocation.value!;

      final ride = await RideService.to.createRide(
        startAddress: start.address,
        startLat: start.lat,
        startLng: start.lng,
        endAddress: end.address,
        endLat: end.lat,
        endLng: end.lng,
      );

      if (ride != null) {
        isLoading.value = false;
        Get.offNamed(AppRoutes.activeRide, arguments: ride);
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to create ride: $e');
      isLoading.value = false;
    } finally {
      isLoading.value = false;
    }
  }
}
