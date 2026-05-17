import 'package:flutter/material.dart';

class NavStep {
  final String   instruction;
  final IconData icon;
  final double   endLat;
  final double   endLng;
  final double   distanceMeters;

  const NavStep({
    required this.instruction,
    required this.icon,
    required this.endLat,
    required this.endLng,
    required this.distanceMeters,
  });
}