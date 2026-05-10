import 'package:get/get.dart';
import '../bindings/home_binding.dart';
import '../bindings/create_ride_binding.dart';
import '../bindings/join_ride_binding.dart';
import '../bindings/active_ride_binding.dart';
import '../bindings/location_picker_binding.dart';
import '../views/home_view.dart';
import '../views/create_ride_view.dart';
import '../views/join_ride_view.dart';
import '../views/active_ride_view.dart';
import '../views/location_picker_view.dart';
import 'app_routes.dart';

class AppPages {
  static final routes = [
    GetPage(
      name: AppRoutes.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.createRide,
      page: () => const CreateRideView(),
      binding: CreateRideBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.joinRide,
      page: () => const JoinRideView(),
      binding: JoinRideBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.activeRide,
      page: () => const ActiveRideView(),
      binding: ActiveRideBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.locationPicker,
      page: () => const LocationPickerView(),
      binding: LocationPickerBinding(),
      transition: Transition.downToUp,
    ),
  ];
}
