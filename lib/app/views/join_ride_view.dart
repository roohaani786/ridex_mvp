import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/join_ride_controller.dart';
import '../theme/app_theme.dart';

class JoinRideView extends GetView<JoinRideController> {
  const JoinRideView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Join a Ride'),
        leading: const BackButton(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Enter Ride Code',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask the ride creator to share their 4-digit code',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 48),
            _buildCodeInput(),
            const SizedBox(height: 16),
            Obx(() {
              if (controller.errorMessage.value.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.sos.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppTheme.sos, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.errorMessage.value,
                        style: const TextStyle(
                          color: AppTheme.sos,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Spacer(),
            _buildJoinButton(),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'The code is shared by the ride creator',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeInput() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(4, (index) {
        return SizedBox(
          width: 68,
          height: 76,
          child: GetBuilder<JoinRideController>(
            builder: (_) => TextField(
              controller: controller.codeControllers[index],
              focusNode: controller.focusNodes[index],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 2.5),
                ),
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (val) => controller.onDigitEntered(index, val),
              onTap: () => controller.codeControllers[index].selection =
                  TextSelection.fromPosition(
                TextPosition(
                  offset: controller.codeControllers[index].text.length,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildJoinButton() {
    return Obx(() => ElevatedButton(
          onPressed:
          (){
            if(controller.isCodeComplete && !controller.isLoading.value){
              controller.joinRide();
            }
            else{
              print(controller.isLoading.value);
              print(controller.isCodeComplete);
            }
          },
          // controller.isCodeComplete && !controller.isLoading.value
          //     ? controller.joinRide
          //     :  (){
          //   print(controller.isLoading.value);
          //   print(controller.isCodeComplete);
          // },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            disabledBackgroundColor: AppTheme.primary.withOpacity(0.4),
          ),
          child: controller.isLoading.value
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text('Joining...'),
                  ],
                )
              : const Text('Join Ride'),
        ));
  }
}
