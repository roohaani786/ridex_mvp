import 'package:get/get.dart';
import '../controllers/join_ride_controller.dart';

class JoinRideBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<JoinRideController>(() => JoinRideController());
  }
}
