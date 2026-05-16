import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sarathi/app/views/location_picker_view.dart';

import '../controllers/location_picker_controller.dart';
import '../models/ride_model.dart';

class LocationPickerSheet extends StatelessWidget {
  final Function(LocationPoint) onLocationSelected;
  final Set<Polyline>? polylines;

  const LocationPickerSheet({
    super.key,
    required this.onLocationSelected,
    this.polylines,
  });

  @override
  Widget build(BuildContext context) {
    Get.put(LocationPickerController());

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(24),
      ),
      child: SizedBox(
        height: Get.height * 0.92,
        child: Material(
          color: Colors.white,
          child: LocationPickerView(
            onLocationSelected: onLocationSelected,
            polylines: polylines,
          ),
        ),
      ),
    );
  }
}