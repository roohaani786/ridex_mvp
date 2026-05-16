import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../controllers/location_picker_controller.dart';
import '../models/ride_model.dart';
import '../theme/app_theme.dart';
import '../utilities/map_control_button.dart';

class LocationPickerView extends GetView<LocationPickerController> {

  final Function(LocationPoint)? onLocationSelected;
  final Set<Polyline>? polylines;

  const LocationPickerView({
    super.key,
    this.onLocationSelected,
    this.polylines,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildCenterPin(),
          _buildMapControls(),
          _buildBottomSheet(),
          _buildSearchBar(),
        ],
      ),
    );
  }



  Widget _buildMap() {
    return Obx(() => GoogleMap(
      onMapCreated: controller.onMapCreated,
      mapType: controller.mapType.value,
      initialCameraPosition: const CameraPosition(
        target: LatLng(17.3850, 78.4867),
        zoom: 14,
      ),
      onCameraMove: controller.onCameraMove,
      onCameraIdle: controller.onCameraIdle,
      markers: Set<Marker>.of(controller.poiMarkers.values),
      polylines: polylines ?? {},
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: true,
    ));
  }

  Widget _buildSearchBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,           // ← critical, don't expand
            children: [
              // ── Text field ─────────────────────────────────────────────────
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(14),
                child: TextField(
                  controller: controller.searchController,
                  decoration: InputDecoration(
                    hintText: 'Search location...',
                    prefixIcon: GestureDetector(
                      onTap: Get.back,
                      child: const Icon(Icons.arrow_back_rounded),
                    ),
                    suffixIcon: Obx(() {
                      if (controller.isSearching.value ||
                          controller.isLoadingPlace.value) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return controller.searchController.text.isNotEmpty
                          ? GestureDetector(
                        onTap: () {
                          controller.searchController.clear();
                          controller.searchResults.clear();
                        },
                        child: const Icon(Icons.close),
                      )
                          : const SizedBox.shrink();
                    }),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: controller.searchLocation,
                  onSubmitted: controller.searchLocation,
                ),
              ),
          
              // ── Results dropdown ────────────────────────────────────────────
              // Rendered in the same Column so it naturally appears directly
              // below the search bar, and since _buildSearchBar is last in the
              // Stack it renders above the bottom sheet and map controls.
              Obx(() {
                if (controller.searchResults.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Material(
                  elevation: 8,                        // ← higher elevation = visually on top
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: controller.searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final suggestion = controller.searchResults[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.location_on_outlined,
                                color: AppTheme.primary, size: 18),
                          ),
                          title: Text(
                            suggestion.mainText,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: suggestion.secondaryText.isNotEmpty
                              ? Text(
                            suggestion.secondaryText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                              : null,
                          dense: true,
                          onTap: () => controller.selectSearchResult(suggestion),
                        );
                      },
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterPin() {
    return IgnorePointer(
      child: Center(
        child: Obx(() {
          final isLoading = controller.isLoadingAddress.value;
          return AnimatedScale(
            scale: isLoading ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 150),
            // ── THE FIX: shift the whole pin UP by 50% of its height ──────────
            // This makes the pin TIP (bottom of dot) sit exactly at screen
            // centre, which is the coordinate the map reads. Without this,
            // the tip is ~34px below the coordinate, causing visible deviation.
            child: FractionalTranslation(
              translation: const Offset(0, -0.5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.sports_motorsports_sharp,
                      color: AppTheme.primary,
                      size: 32,
                    ),
                  ),
                  Container(width: 2, height: 16, color: AppTheme.primary),
                  Container(
                    width: 8,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      right: 16,
      bottom: 230,
      child: Column(
        children: [
          // ── Dark / Light theme toggle ─────────────────────────────────
          Obx(() {
            final isDark = controller.isDarkMode.value;
            return MapControlButton(
              icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              tooltip: isDark ? 'Light mode' : 'Dark mode',
              isActive: isDark,
              onTap: controller.toggleMapTheme,
            );
          }),
          const SizedBox(height: 8),

          // ── Satellite toggle ──────────────────────────────────────────
          Obx(() {
            final isSatellite = controller.mapType.value == MapType.satellite;
            return MapControlButton(
              icon: isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
              tooltip: isSatellite ? 'Normal view' : 'Satellite view',
              isActive: isSatellite,
              onTap: controller.toggleMapType,
            );
          }),
          const SizedBox(height: 8),

          // ── Zoom in ───────────────────────────────────────────────────
          MapControlButton(
            icon: Icons.add_rounded,
            tooltip: 'Zoom in',
            onTap: controller.zoomIn,
          ),
          const SizedBox(height: 4),

          // ── Zoom out ──────────────────────────────────────────────────
          MapControlButton(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom out',
            onTap: controller.zoomOut,
          ),
          const SizedBox(height: 8),

          // ── My location ───────────────────────────────────────────────
          MapControlButton(
            icon: Icons.my_location_rounded,
            tooltip: 'My location',
            onTap: controller.goToMyLocation,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(() {
                    if (controller.isLoadingAddress.value) {
                      return const SizedBox(
                        height: 16,
                        width: 120,
                        child: LinearProgressIndicator(
                          color: AppTheme.primary,
                          backgroundColor: Color(0xFFE8EAF6),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.selectedAddress.value.isEmpty
                              ? 'Move map to select location'
                              : controller.selectedAddress.value,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (controller.selectedPosition.value != null)
                          Text(
                            '${controller.selectedPosition.value!.latitude.toStringAsFixed(5)}, '
                            '${controller.selectedPosition.value!.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onLocationSelected != null
                  ? () async {
                final point = await controller.buildLocationPoint();

                if (point == null) return;

                onLocationSelected!(point);
              }
                  : controller.confirmLocation,
              child: const Text('Confirm Location'),
            ),
          ],
        ),
      ),
    );
  }
}
