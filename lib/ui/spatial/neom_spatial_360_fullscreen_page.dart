import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';

import '../painters/neom_spatial_painter.dart';
import 'neom_spatial_360_controller.dart';

class NeomSpatial360FullscreenPage extends StatelessWidget {
  const NeomSpatial360FullscreenPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<NeomSpatial360Controller>(
      id: AppPageIdConstants.spatial360,
      init: NeomSpatial360Controller(),
      builder: (controller) => Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          // Touch para mover cámara (cuando no hay giroscopio)
          onPanStart: (details) {
            controller.onPanStart(
              details.localPosition.dx,
              details.localPosition.dy,
            );
          },
          onPanUpdate: (details) {
            controller.onPanUpdate(
              details.localPosition.dx,
              details.localPosition.dy,
            );
          },
          // Tap para pausar
          onTap: controller.toggleSimulation,
          onLongPress: () => Get.back(),
          // Double tap para reset
          onDoubleTap: controller.resetCamera,
          child: Stack(
            children: [
              // Canvas VR 360
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: controller.vrEngine,
                  builder: (_, __) => CustomPaint(
                    painter: NeomVR360Painter(
                      engine: controller.vrEngine,
                      showRings: controller.showRings.value,
                      showConstellations: controller.showConstellations.value,
                      showNebula: controller.showNebula.value,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),

              // Crosshair central sutil
              Center(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                ),
              ),

              // Indicador de pausa
              if (!controller.isRunning.value)
                Positioned(
                  top: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColor.bondiBlue.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause, color: AppColor.bondiBlue, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'PAUSED',
                            style: TextStyle(
                              color: AppColor.bondiBlue,
                              fontFamily: 'Courier',
                              fontSize: 12,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Panel de controles
              Positioned(
                right: 10,
                top: 0,
                bottom: 0,
                child: _buildControlPanel(controller),
              ),

              // Botón de salir
              Positioned(
                top: 10,
                left: 10,
                child: _buildExitButton(controller),
              ),

              // Info panel
              Positioned(
                bottom: 10,
                left: 10,
                child: _buildInfoPanel(controller),
              ),

              // Color modes
              Positioned(
                bottom: 10,
                right: 80,
                child: _buildColorModeSelector(controller),
              ),

              // Indicador de modo gyro/touch
              Positioned(
                top: 10,
                left: 60,
                child: _buildGyroIndicator(controller),
              ),

              // Botón VR Headset Mode (estereoscópico)
              // Positioned(
              //   top: 10,
              //   right: 70,
              //   child: _buildVRHeadsetButton(controller),
              // ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlPanel(NeomSpatial360Controller controller) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Toggle Giroscopio
        _buildToggleButton(
          icon: Icons.screen_rotation,
          isActive: controller.useGyroscope.value,
          onTap: controller.toggleGyroscope,
          label: 'GYRO',
        ),
        const SizedBox(height: 10),

        // Toggle Auto-rotación
        _buildToggleButton(
          icon: Icons.autorenew,
          isActive: controller.autoRotate.value,
          onTap: controller.toggleAutoRotate,
          label: 'AUTO',
        ),
        const SizedBox(height: 20),

        // Toggle Anillos
        _buildToggleButton(
          icon: Icons.radio_button_unchecked,
          isActive: controller.showRings.value,
          onTap: controller.toggleRings,
          label: 'RINGS',
        ),
        const SizedBox(height: 10),

        // Toggle Constelaciones
        _buildToggleButton(
          icon: Icons.star_outline,
          isActive: controller.showConstellations.value,
          onTap: controller.toggleConstellations,
          label: 'STARS',
        ),
        const SizedBox(height: 10),

        // Toggle Nebula
        _buildToggleButton(
          icon: Icons.cloud,
          isActive: controller.showNebula.value,
          onTap: controller.toggleNebula,
          label: 'NEBULA',
        ),
        const SizedBox(height: 20),

        // Reset camera
        GestureDetector(
          onTap: controller.resetCamera,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.center_focus_strong, color: Colors.white54, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColor.bondiBlue.withOpacity(0.3) : Colors.black54,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? AppColor.bondiBlue : Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? AppColor.bondiBlue : Colors.white38, size: 18),
            if (label != null) ...[
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? AppColor.bondiBlue : Colors.white38,
                  fontSize: 7,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExitButton(NeomSpatial360Controller controller) {
    return GestureDetector(
      onTap: controller.exitFullscreen,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: const Icon(Icons.fullscreen_exit, color: Colors.white70, size: 22),
      ),
    );
  }

  Widget _buildInfoPanel(NeomSpatial360Controller controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInfoItem('TAP', 'pause'),
          const SizedBox(width: 12),
          _buildInfoItem('DRAG', 'look'),
          const SizedBox(width: 12),
          _buildInfoItem('2xTAP', 'reset'),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String key, String action) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: AppColor.bondiBlue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            key,
            style: const TextStyle(
              color: AppColor.bondiBlue,
              fontFamily: 'Courier',
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(action, style: const TextStyle(color: Colors.white54, fontSize: 9)),
      ],
    );
  }

  Widget _buildGyroIndicator(NeomSpatial360Controller controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: controller.useGyroscope.value
              ? Colors.green.withOpacity(0.5)
              : Colors.orange.withOpacity(0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            controller.useGyroscope.value ? Icons.screen_rotation : Icons.touch_app,
            color: controller.useGyroscope.value ? Colors.green : Colors.orange,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            controller.useGyroscope.value ? 'GYRO' : 'TOUCH',
            style: TextStyle(
              color: controller.useGyroscope.value ? Colors.green : Colors.orange,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorModeSelector(NeomSpatial360Controller controller) {
    final modes = ['default', 'calm', 'focus', 'sleep', 'creativity'];
    final icons = [Icons.auto_awesome, Icons.spa, Icons.psychology, Icons.nightlight, Icons.palette];
    final colors = [AppColor.bondiBlue, Colors.purple, Colors.orange, Colors.indigo, Colors.pink];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(modes.length, (i) {
          final isSelected = controller.colorMode.value == modes[i];
          return GestureDetector(
            onTap: () => controller.setColorMode(modes[i]),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? colors[i].withOpacity(0.3) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? colors[i] : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Icon(icons[i], color: isSelected ? colors[i] : Colors.white38, size: 16),
            ),
          );
        }),
      ),
    );
  }
}
