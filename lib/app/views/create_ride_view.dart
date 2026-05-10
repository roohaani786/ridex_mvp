import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/create_ride_controller.dart';
import '../theme/app_theme.dart';

class CreateRideView extends GetView<CreateRideController> {
  const CreateRideView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Create a Ride'),
        leading: const BackButton(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set your route',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick start and end locations for your ride',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            _buildLocationCard(
              icon: Icons.trip_origin,
              iconColor: AppTheme.success,
              label: 'Start Location',
              rxLocation: controller.startLocation,
              onTap: controller.pickStartLocation,
            ),
            _buildRouteLine(),
            _buildLocationCard(
              icon: Icons.location_on,
              iconColor: AppTheme.sos,
              label: 'End Location (Destination)',
              rxLocation: controller.endLocation,
              onTap: controller.pickEndLocation,
            ),
            const Spacer(),
            _buildRoutePreview(),
            const SizedBox(height: 16),
            Obx(() => ElevatedButton(
                  onPressed: controller.canCreate && !controller.isLoading.value
                      ? controller.createRide
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: AppTheme.primary.withOpacity(0.4),
                  ),
                  child: controller.isLoading.value
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Create Ride & Get Code'),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required dynamic rxLocation,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Obx(() {
                final loc = rxLocation.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loc == null ? 'Tap to select' : loc.address,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            loc == null ? FontWeight.w400 : FontWeight.w600,
                        color: loc == null
                            ? AppTheme.textSecondary
                            : AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              }),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 27),
      child: Column(
        children: List.generate(
          4,
          (_) => Container(
            width: 2,
            height: 6,
            margin: const EdgeInsets.symmetric(vertical: 2),
            color: Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  Widget _buildRoutePreview() {
    return Obx(() {
      final start = controller.startLocation.value;
      final end = controller.endLocation.value;
      if (start == null || end == null) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: AppTheme.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Route set: ${start.address.split(',').first} → ${end.address.split(',').first}',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
