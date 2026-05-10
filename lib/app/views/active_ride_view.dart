import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../controllers/active_ride_controller.dart';
import '../models/ride_model.dart';
import '../theme/app_theme.dart';

class ActiveRideView extends GetView<ActiveRideController> {
  const ActiveRideView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildNavBanner(),
          _buildLeftActions(),
          _buildRightActions(),
          _buildBottomBar(),
          _buildRideCodeBadge(),
        ],
      ),
    );
  }

  // ─── Map ─────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    return Obx(() {
      final initialPos = LatLng(
        controller.ride.startLocation.lat,
        controller.ride.startLocation.lng,
      );
      return GoogleMap(
        onMapCreated: controller.onMapCreated,

        initialCameraPosition: CameraPosition(
          target: LatLng(
            controller.ride.startLocation.lat,
            controller.ride.startLocation.lng,
          ),
          zoom: 15,
        ),

        markers: Set<Marker>.of(controller.markers.values),

        polylines: {
          Polyline(
            polylineId: const PolylineId('route'),
            points: controller.polylineCoords,
            color: Colors.blue,
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            geodesic: true,
          ),
        },

        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        compassEnabled: false,
      );
    });
  }

  // ─── Nav banner (instruction + distance) ─────────────────────────────────

  Widget _buildNavBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Obx(
              () => Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  // ← uses reactive icon from controller
                  child: Icon(
                    controller.currentInstructionIcon.value,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.currentInstruction.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        controller.distanceText.value.isEmpty
                            ? controller.ride.endLocation.address
                            : '${controller.distanceText.value} remaining',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Left action buttons ──────────────────────────────────────────────────

  Widget _buildLeftActions() {
    return Positioned(
      left: 14,
      top: 0,
      bottom: 140,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ActionButton(
            icon: Icons.pan_tool_alt_outlined,
            label: 'PULL\nOVER',
            color: Colors.white,
            iconColor: AppTheme.primary,
            onTap: () =>
                Get.snackbar('Pull Over', 'Notifying your group...'),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.local_gas_station_rounded,
            label: 'FUEL',
            color: Colors.white,
            iconColor: AppTheme.primary,
            onTap: () => Get.snackbar(
                'Fuel Stop', 'Searching nearby fuel stations...'),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.restaurant_rounded,
            label: 'FOOD',
            color: Colors.white,
            iconColor: AppTheme.primary,
            onTap: () => Get.snackbar(
                'Food Stop', 'Searching nearby restaurants...'),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.warning_amber_rounded,
            label: 'SOS',
            color: AppTheme.sos,
            iconColor: Colors.white,
            onTap: controller.onSOS,
          ),
        ],
      ),
    );
  }

  // ─── Right icon buttons ───────────────────────────────────────────────────

  Widget _buildRightActions() {
    return Positioned(
      right: 14,
      top: 0,
      bottom: 140,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RoundButton(
            icon: Icons.notifications_outlined,
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _RoundButton(
            icon: Icons.volume_up_outlined,
            onTap: () {},
          ),
          const SizedBox(height: 10),

          // ← Obx so badge re-renders when members count changes
          Obx(() => _RoundButton(
            icon: Icons.group_outlined,
            onTap: _showGroupPanel,
            badge: controller.memberCount.value > 1
                ? '${controller.memberCount.value}'
                : null,
          )),
          const SizedBox(height: 10),

          // Jump to partner's location
          Obx(() {
            final partner = controller.partnerMember;
            if (partner == null) return const SizedBox.shrink();
            final hasLoc =
            controller.memberLocations.containsKey(partner.userId);
            return _RoundButton(
              icon: Icons.person_pin_circle_rounded,
              onTap: () => controller.focusOnMember(partner.userId),
              isActive: hasLoc,
              tooltip: hasLoc
                  ? 'Jump to ${partner.name}'
                  : '${partner.name} — waiting...',
            );
          }),
          const SizedBox(height: 10),

          // ← Obx so icon + active state re-render on toggle
          Obx(() => _RoundButton(
            icon: controller.isFollowingMe.value
                ? Icons.my_location_rounded
                : Icons.location_searching_rounded,
            onTap: controller.toggleFollowMe,
            isActive: controller.isFollowingMe.value,
          )),
          const SizedBox(height: 10),
          _RoundButton(
            icon: Icons.fit_screen_rounded,
            onTap: controller.fitAllRiders,
          ),
        ],
      ),
    );
  }

  // ─── Bottom ETA bar ───────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: controller.endRide,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 20),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Obx(() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controller.etaText.value.isEmpty
                        ? 'Calculating...'
                        : controller.etaText.value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: controller.hasIReached.value
                          ? AppTheme.success
                          : AppTheme.primary,
                    ),
                  ),
                  Text(
                    controller.hasIReached.value
                        ? '✅ You have arrived!'
                        : '${controller.distanceText.value}  •  '
                        '${controller.ride.endLocation.address.split(',').first}',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              )),
            ),
            GestureDetector(
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.alt_route_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Ride code badge ─────────────────────────────────────────────────────

  Widget _buildRideCodeBadge() {
    return Positioned(
      top: 110,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => Get.snackbar(
            'Ride Code',
            'Share code ${controller.rideCode} with your partner to join',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppTheme.primary,
            colorText: Colors.white,
          ),
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.share, size: 14, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Code: ${controller.rideCode}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  // ─── Group panel bottom sheet ─────────────────────────────────────────────

  void _showGroupPanel() {
    Get.bottomSheet(
      // ← Obx wraps the whole sheet so loc re-reads on every RTDB update
      Obx(() => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Riders',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ...controller.members.map((member) {
              // reads fresh value every Obx rebuild
              final loc = controller.memberLocations[member.userId];

              final isCreator = member.userId == controller.ride.creatorId;
              final isMe = member.userId == controller.myUserId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: isCreator
                      ? AppTheme.primary
                      : const Color(0xFFE91E63),
                  child: Text(
                    member.name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Row(
                  children: [
                    Text(member.name,
                        style:
                        const TextStyle(fontWeight: FontWeight.w600)),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Builder(
                  builder: (_) {
                    final fallbackLatLng = controller.getMemberLatLng(member);

                    return Text(
                      loc != null
                          ? 'Speed: ${(loc.speed * 3.6).toStringAsFixed(0)} km/h'
                          '  •  ±${loc.accuracy.toStringAsFixed(0)}m'
                          : 'Last known: '
                          '${fallbackLatLng.latitude.toStringAsFixed(4)}, '
                          '${fallbackLatLng.longitude.toStringAsFixed(4)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: loc != null
                            ? AppTheme.textSecondary
                            : Colors.orange.shade600,
                      ),
                    );
                  },
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loc?.hasReached == true)
                      const Icon(Icons.check_circle,
                          color: AppTheme.success)
                    else
                      Icon(
                        Icons.location_on,
                        color: loc != null
                            ? AppTheme.primary
                            : Colors.grey.shade400,
                      ),
                    if (!isMe) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
              onTap: () {
              Get.back();
              controller.focusOnMember(member.userId);
              },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: loc != null
                                ? AppTheme.primary
                                : Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.my_location_rounded,
                            size: 16,
                            color:
                            loc != null ? Colors.white : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: !isMe
                    ? () {
                  Get.back();
                  controller.focusOnMember(member.userId);
                }
                    : null,
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      )),
      isScrollControlled: true,
    );
  }
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 66,
        padding:
        const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: iconColor,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final String? badge;
  final String? tooltip;

  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
    this.badge,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primary : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.white : AppTheme.primary,
              size: 20,
            ),
          ),
          if (badge != null)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppTheme.sos,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        preferBelow: false,
        child: button,
      );
    }
    return button;
  }
}