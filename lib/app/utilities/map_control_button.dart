import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool isActive;

  const MapControlButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(10),
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
          size: 20,
          color: isActive ? Colors.white : AppTheme.primary,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, preferBelow: false, child: button);
    }
    return button;
  }
}