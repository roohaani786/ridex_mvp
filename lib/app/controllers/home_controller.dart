import 'package:get/get.dart';
import '../models/ride_model.dart';
import '../routes/app_routes.dart';
import '../services/ride_service.dart';
import '../services/user_service.dart';

class HomeController extends GetxController {
  String get userName => UserService.to.userName;

  final selectedTab  = RxInt(0);
  final activeRide   = Rx<RideModel?>(null);
  final isLoading    = RxBool(false);

  @override
  void onInit() {
    super.onInit();
    _checkForActiveRide();
  }

  Future<void> _checkForActiveRide() async {
    isLoading.value = true;
    activeRide.value = await RideService.to.getActiveRide();
    isLoading.value = false;
  }

  void selectTab(int index) {
    selectedTab.value = index;
    // Refresh active ride every time user taps Rides tab
    if (index == 1) _checkForActiveRide();
  }

  void resumeRide() {
    final ride = activeRide.value;
    if (ride == null) return;
    Get.toNamed(AppRoutes.activeRide, arguments: ride);
  }

  void goToCreateRide() => Get.toNamed(AppRoutes.createRide);
  void goToJoinRide()   => Get.toNamed(AppRoutes.joinRide);
}