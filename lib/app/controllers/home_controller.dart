import 'package:get/get.dart';
import '../routes/app_routes.dart';
import '../services/user_service.dart';

class HomeController extends GetxController {
  String get userName => UserService.to.userName;

  void goToCreateRide() => Get.toNamed(AppRoutes.createRide);
  void goToJoinRide() => Get.toNamed(AppRoutes.joinRide);
}
