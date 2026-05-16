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
      // Reading polylineVersion registers it as a dependency.
      // It always increments so Obx always fires when polylines change.
      final _ = controller.polylineVersion.value;

      return GoogleMap(
        key: const ValueKey('active_ride_map'),
        onMapCreated: controller.onMapCreated,
        mapType: controller.mapType.value,
        initialCameraPosition: CameraPosition(
          target: LatLng(
            controller.ride.startLocation.lat,
            controller.ride.startLocation.lng,
          ),
          zoom: 17,
          tilt: 50,
          bearing: 0,
        ),
        markers:   Set<Marker>.of(controller.markers.values),
        polylines: controller.currentPolylines.toSet(),  // ← plain field, no equality trap
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

                      // ── REPLACE the old subtitle Text with this ───────────
                      Text(
                        _buildNavSubtitle(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // ── END REPLACEMENT ───────────────────────────────────

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

// ── Add this helper method anywhere in the view class ─────────────────────
  String _buildNavSubtitle() {
    final stopIdx = controller.currentStopIndex.value;
    final stops   = controller.stops;

    if (!controller.hasNavigationStarted.value) {
      // Pre-navigation — just show destination
      return controller.ride.endLocation.address;
    }

    if (stopIdx < stops.length) {
      // Navigating toward a stop
      final remainingStops = stops.length - stopIdx;
      final dist = controller.distanceText.value;
      return '${dist.isEmpty ? '' : '$dist to '}Stop ${stopIdx + 1}'
          '  •  $remainingStops stop${remainingStops > 1 ? 's' : ''} remaining';
    }

    // All stops passed — heading to final destination
    return controller.distanceText.value.isEmpty
        ? controller.ride.endLocation.address
        : '${controller.distanceText.value} remaining';
  }

  void _showStopsPanel(BuildContext context) {
    Get.bottomSheet(
      StatefulBuilder(
        builder: (context, setState) {
          return Obx(() => Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Handle ──────────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    const Text(
                      'Stops',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (controller.isCreator.value)
                      GestureDetector(
                        onTap: () {
                          Get.back();
                          controller.pickAndAddStop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Add Stop',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Stop list ────────────────────────────────────────────────
                if (controller.stops.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No stops added yet.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      onReorder: (oldIndex, newIndex) {
                        if (!controller.isCreator.value) return;
                        final list = [...controller.stops];
                        if (newIndex > oldIndex) newIndex--;
                        final item = list.removeAt(oldIndex);
                        list.insert(newIndex, item);
                        controller.reorderStops(list);
                      },
                      itemCount: controller.stops.length,
                      itemBuilder: (context, i) {
                        final stop    = controller.stops[i];
                        final reached = i < controller.currentStopIndex.value;
                        return ListTile(
                          key: ValueKey('stop_$i'),
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: reached
                                  ? AppTheme.success.withOpacity(0.15)
                                  : const Color(0xFFFF8C00).withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: reached
                                  ? const Icon(Icons.check_rounded,
                                  color: AppTheme.success, size: 16)
                                  : Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF8C00),
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            stop.address.split(',').first,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: reached
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary,
                              decoration: reached
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            stop.address,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: controller.isCreator.value
                              ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () =>
                                    controller.removeStop(i),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.sos
                                        .withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: AppTheme.sos,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.drag_handle_rounded,
                                  color: AppTheme.textSecondary,
                                  size: 20),
                            ],
                          )
                              : null,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ));
        },
      ),
      isScrollControlled: true,
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

          // ── Add between FOOD and SOS ──────────────────────────────────────────────
          Obx(() => controller.isCreator.value
              ? Column(
            children: [
              // const SizedBox(height: 10),
              _ActionButton(
                icon: Icons.add_location_alt_rounded,
                label: 'STOP',
                color: Colors.white,
                iconColor: AppTheme.primary,
                onTap: () => _showStopsPanel(Get.context!),  // ← add context param to _buildLeftActions
              ),
            ],
          )
              : const SizedBox.shrink()),

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

          // ── Map controls ──────────────────────────────────────────────
          Obx(() {
            final isDark = controller.isDarkMode.value;
            return _RoundButton(
              icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              onTap: controller.toggleMapTheme,
              isActive: isDark,
              tooltip: isDark ? 'Light mode' : 'Dark mode',
            );
          }),
          const SizedBox(height: 10),
          Obx(() {
            final isSatellite = controller.mapType.value == MapType.satellite;
            return _RoundButton(
              icon: isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
              onTap: controller.toggleMapType,
              isActive: isSatellite,
              tooltip: isSatellite ? 'Normal view' : 'Satellite view',
            );
          }),
          const SizedBox(height: 10),
          _RoundButton(
            icon: Icons.add_rounded,
            onTap: controller.zoomIn,
            tooltip: 'Zoom in',
          ),
          const SizedBox(height: 4),
          _RoundButton(
            icon: Icons.remove_rounded,
            onTap: controller.zoomOut,
            tooltip: 'Zoom out',
          ),
          const SizedBox(height: 10),

          // ── Existing buttons — unchanged ──────────────────────────────
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
          Obx(() => _RoundButton(
            icon: Icons.group_outlined,
            onTap: _showGroupPanel,
            badge: controller.memberCount.value > 1
                ? '${controller.memberCount.value}'
                : null,
          )),
          const SizedBox(height: 10),
          Obx(() {
            controller.memberCount.value;
            final partner = controller.partnerMember;
            if (partner == null) return const SizedBox.shrink();
            final hasLoc = controller.memberLocations.containsKey(partner.userId);
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

  void _showRouteOptions() {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.45,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose Route',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: Obx(() {
                return ListView.separated(
                  itemCount: controller.allRoutes.length,
                  separatorBuilder: (_, __) =>
                  const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final route = controller.allRoutes[i];
                    final selected =
                        controller.selectedRouteIndex.value == i;

                    return GestureDetector(
                      onTap: () {
                        controller.selectRoute(i);
                        Get.back();
                      },
                      child: AnimatedContainer(
                        duration:
                        const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? AppTheme.primary
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.route_rounded,
                              color: selected
                                  ? Colors.white
                                  : AppTheme.primary,
                            ),

                            const SizedBox(width: 14),

                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    route.duration,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: selected
                                          ? Colors.white
                                          : AppTheme.textPrimary,
                                    ),
                                  ),

                                  const SizedBox(height: 4),

                                  Text(
                                    '${route.distance} • ${route.summary}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: selected
                                          ? Colors.white.withOpacity(0.9)
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (selected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Colors.white,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
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
        child: Obx(() {
          // ── Pre-navigation state ───────────────────────────────────────────
          if (!controller.hasNavigationStarted.value) {
            return Row(
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
                // ── Inside the pre-navigation Row, replace the Expanded Column with this ──

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'To: ${controller.ride.endLocation.address.split(',').first}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // ── Route options ─────────────────────────────────────────────
                      Obx(() {
                        if (controller.allRoutes.isEmpty) {
                          return controller.isPreviewingRoute.value
                              ? const LinearProgressIndicator(
                            color: AppTheme.primary,
                            backgroundColor: Color(0xFFE8EAF6),
                            minHeight: 3,
                          )
                              : const SizedBox.shrink();
                        }
                        return GestureDetector(
                          onTap: _showRouteOptions,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.alt_route_rounded,
                                  size: 18,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Obx(() {
                                  final route = controller.allRoutes[
                                  controller.selectedRouteIndex.value];

                                  return Text(
                                    '${route.duration} • ${route.distance}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // ── Start Navigation button ──────────────────────────────────
                GestureDetector(
                  onTap: controller.isStartingNavigation.value
                      ? null
                      : controller.startNavigation,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: controller.isStartingNavigation.value
                          ? AppTheme.primary.withOpacity(0.6)
                          : AppTheme.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: controller.isStartingNavigation.value
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.navigation_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Start',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // ── Active navigation state ────────────────────────────────────────
          return Row(
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
                child: Column(
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
                ),
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
          );
        }),
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