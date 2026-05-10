import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../controllers/location_picker_controller.dart';
import '../theme/app_theme.dart';

class LocationPickerView extends GetView<LocationPickerController> {
  const LocationPickerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildSearchBar(),
          _buildCenterPin(),
          _buildMyLocationButton(),
          _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Obx(() {
      final initialPos = controller.selectedPosition.value ??
          const LatLng(19.0760, 72.8777);

      return GoogleMap(
        onMapCreated: controller.onMapCreated,

        initialCameraPosition: CameraPosition(
          target: initialPos,
          zoom: 15,
        ),

        onCameraMove: controller.onCameraMove,
        onCameraIdle: controller.onCameraIdle,

        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: false,
      );
    });
  }

  Widget _buildSearchBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          children: [
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
                    print(controller.searchResults.value);
                    return
                    controller.searchController.text.isNotEmpty
                        ? GestureDetector(
                      onTap: () {
                        // print(controller.searchResults.value);
                        controller.searchController.clear();
                        controller.searchResults.clear();
                      },
                      child: const Icon(Icons.close),
                    )
                        : const SizedBox.shrink();
                  } ),
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
            Obx(() {
              if (controller.searchResults.isEmpty) return const SizedBox.shrink();
              return Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: controller.searchResults.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final loc = controller.searchResults[i];
                      return ListTile(
                        leading: const Icon(Icons.location_on_outlined,
                            color: AppTheme.primary),
                        title: Text(
                          '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        dense: true,
                        onTap: () => controller.selectSearchResult(loc),
                      );
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPin() {
    return Center(
      child: Obx(() {
        final isLoading = controller.isLoadingAddress.value;
        return AnimatedScale(
          scale: isLoading ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 150),
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
                      color: AppTheme.primary.withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on,
                  color: AppTheme.primary,
                  size: 32,
                ),
              ),
              Container(
                width: 2,
                height: 16,
                color: AppTheme.primary,
              ),
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
        );
      }),
    );
  }

  Widget _buildMyLocationButton() {
    return Positioned(
      right: 16,
      bottom: 220,
      child: FloatingActionButton.small(
        onPressed: controller.goToMyLocation,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 4,
        child: const Icon(Icons.my_location_rounded),
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
              onPressed: controller.confirmLocation,
              child: const Text('Confirm Location'),
            ),
          ],
        ),
      ),
    );
  }
}
