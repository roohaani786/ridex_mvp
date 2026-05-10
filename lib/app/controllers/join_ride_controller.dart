import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import '../routes/app_routes.dart';
import '../services/ride_service.dart';

class JoinRideController extends GetxController {
  final codeControllers = List.generate(4, (_) => TextEditingController());
  final focusNodes = List.generate(4, (_) => FocusNode());
  final isLoading = RxBool(false);
  final errorMessage = RxString('');

  String get enteredCode =>
      codeControllers.map((c) => c.text).join();

  bool get isCodeComplete => enteredCode.length == 4;

  void onDigitEntered(int index, String value) {
    errorMessage.value = '';
    if (value.isNotEmpty && index < 3) {
      focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      focusNodes[index - 1].requestFocus();
    }
    update();
  }

  void onKeyEvent(int index, String value) {
    if (value.isEmpty && index > 0) {
      focusNodes[index - 1].requestFocus();
      codeControllers[index - 1].clear();
    }
  }

  Future<void> joinRide() async {
    print("36");
    if (!isCodeComplete) return;
    isLoading.value = true;
    errorMessage.value = '';

    final ride = await RideService.to.joinRide(enteredCode);
    isLoading.value = false;

    if (ride != null) {
      Get.offNamed(AppRoutes.activeRide, arguments: ride);
    } else {
      errorMessage.value = 'Ride not found. Check the code and try again.';
      isLoading.value = false;
      _clearCode();
    }
  }



  void _clearCode() {
    for (final c in codeControllers) {
      c.clear();
    }
    focusNodes[0].requestFocus();
    update();
  }

  @override
  void onClose() {
    for (final c in codeControllers) {
      c.dispose();
    }
    for (final f in focusNodes) {
      f.dispose();
    }
    super.onClose();
  }
}
