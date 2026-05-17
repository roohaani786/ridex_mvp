import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/ride_model.dart';
import '../routes/app_routes.dart';
import '../services/ride_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';

class HomeController extends GetxController {
  RxString get userName => UserService.to.userName;

  final selectedTab  = RxInt(0);
  final activeRide   = Rx<RideModel?>(null);
  final isLoading    = RxBool(false);

  @override
  void onInit() {
    super.onInit();
    _checkForActiveRide();
    if (UserService.to.isNameDefault) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showNameDialog());
    }
  }

  void showNameDialog({bool isEdit = false}) {
    final nameController = TextEditingController(
      text: isEdit ? UserService.to.userName.value : '',
    );
    final formKey = GlobalKey<FormState>();

    Get.bottomSheet(
      Container(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(Get.context!).viewInsets.bottom + 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isEdit ? 'Edit your name' : 'What should we call you?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This name is shown to your ride group.',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g. Arjun, Priya...',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 1.5),
                  ),
                  prefixIcon: const Icon(Icons.person_outline_rounded,
                      color: AppTheme.primary),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Please enter a name';
                  if (v.trim().length < 2) return 'Name too short';
                  if (v.trim().length > 20) return 'Name too long';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  await UserService.to.setName(nameController.text.trim());
                  Get.back();
                  Get.snackbar(
                    'Name saved!',
                    'You\'re now known as ${UserService.to.userName.value}',
                    snackPosition: SnackPosition.TOP,
                    backgroundColor: AppTheme.primary,
                    colorText: Colors.white,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Save Name',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
      isDismissible: !isEdit ? false : true, // can't dismiss on first launch
    );
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