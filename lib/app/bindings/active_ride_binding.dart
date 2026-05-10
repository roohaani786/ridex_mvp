import 'package:get/get.dart';
import '../controllers/active_ride_controller.dart';
import '../services/location_service.dart';

class ActiveRideBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<LocationService>()) {
      Get.put<LocationService>(LocationService(), permanent: true);
    }
    Get.lazyPut<ActiveRideController>(() => ActiveRideController());
  }
}