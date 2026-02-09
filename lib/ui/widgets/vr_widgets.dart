import 'package:flutter/material.dart';
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_core/utils/constants/app_route_constants.dart';
import 'package:sint/sint.dart';

import '../spatial/neom_spatial_360_controller.dart';

Widget buildVRHeadsetButton(NeomSpatial360Controller controller) {
  return GestureDetector(
    onTap: () {
      // Navegar al modo VR estereoscópico
      Sint.toNamed(
        AppRouteConstants.vr360StereoFullscreen,
        arguments: controller.painterEngine,
      );
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColor.bondiBlue.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.vrpano, color: AppColor.bondiBlue, size: 16),
          const SizedBox(width: 6),
          const Text(
            'VR HEADSET',
            style: TextStyle(
              color: AppColor.bondiBlue,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    ),
  );
}
