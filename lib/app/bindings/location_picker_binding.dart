import 'package:get/get.dart';
import '../controllers/location_picker_controller.dart';
import '../services/location_service.dart';

class LocationPickerBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<LocationService>()) {
      Get.put<LocationService>(LocationService(), permanent: true);
    }
    Get.lazyPut<LocationPickerController>(() => LocationPickerController());
  }
}
