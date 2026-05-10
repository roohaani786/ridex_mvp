import 'package:get/get.dart';
import '../controllers/create_ride_controller.dart';

class CreateRideBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CreateRideController>(() => CreateRideController());
  }
}
