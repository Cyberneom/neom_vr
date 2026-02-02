import 'package:flutter/material.dart';
import 'package:sint/sint.dart';
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';

import '../painters/neom_vr360_stereo_painter.dart';
import 'neom_vr360_stereo_controller.dart';

/// Página VR estereoscópica para visores con smartphone dentro
/// Vista dividida (split-screen) para ojo izquierdo y derecho
/// FUERZA MODO LANDSCAPE OBLIGATORIO
class NeomVR360StereoPage extends StatefulWidget {
  const NeomVR360StereoPage({super.key});

  @override
  State<NeomVR360StereoPage> createState() => _NeomVR360StereoPageState();
}

class _NeomVR360StereoPageState extends State<NeomVR360StereoPage> {

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    // Restaurar orientación al salir
    //VRMode.disabled();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Forzar orientación cada vez que se reconstruye

    return SintBuilder<NeomVR360StereoController>(
      id: AppPageIdConstants.vr360,
      init: NeomVR360StereoController(),
      builder: (controller) => Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
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
          onTap: controller.toggleSimulation,
          onDoubleTap: controller.resetCamera,
          onLongPress: controller.exitFullscreen,
          child: Stack(
            children: [
              // Canvas VR Estereoscópico (vista dividida)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: controller.vrEngine,
                  builder: (_, __) => CustomPaint(
                    painter: NeomVR360StereoPainter(
                      engine: controller.vrEngine,
                      showRings: controller.showRings.value,
                      showConstellations: controller.showConstellations.value,
                      showNebula: controller.showNebula.value,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),

              // Indicador de pausa
              if (!controller.isRunning.value)
                _buildPauseOverlay(controller),

              // Panel de ajustes (solo cuando pausado)
              if (!controller.isRunning.value)
                Positioned(
                  bottom: 15,
                  left: 15,
                  right: 15,
                  child: _buildSettingsPanel(controller),
                ),

              // Indicador de modo VR (muy sutil)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: _buildVRModeIndicator(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPauseOverlay(NeomVR360StereoController controller) {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: AppColor.bondiBlue.withAlpha(128)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pause_circle_outline, color: AppColor.bondiBlue, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'VR PAUSED',
                      style: TextStyle(
                        color: AppColor.bondiBlue,
                        fontFamily: 'Courier',
                        fontSize: 16,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHintChip('TAP', 'resume'),
                  const SizedBox(width: 12),
                  _buildHintChip('2xTAP', 'calibrate'),
                  const SizedBox(width: 12),
                  _buildHintChip('HOLD', 'exit'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHintChip(String key, String action) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: AppColor.bondiBlue.withAlpha(77),
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
          const SizedBox(width: 5),
          Text(action, style: const TextStyle(color: Colors.white54, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel(NeomVR360StereoController controller) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(217),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'VR HEADSET SETTINGS',
            style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSliderControl(
                  label: 'FREQUENCY',
                  value: controller.frequency.value,
                  min: 20,
                  max: 2000,
                  onChanged: controller.setFrequency,
                  suffix: 'Hz',
                  color: controller.vrEngine.frequencyModulatedColor,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildSliderControl(
                  label: 'WAVELENGTH',
                  value: controller.wavelength.value,
                  min: 0.5,
                  max: 2.0,
                  onChanged: controller.setWavelength,
                  suffix: 'x',
                  color: AppColor.bondiBlue,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildSliderControl(
                  label: 'EYE DIST',
                  value: controller.eyeSeparation.value * 1000,
                  min: 40,
                  max: 80,
                  onChanged: (v) => controller.setEyeSeparation(v / 1000),
                  suffix: 'mm',
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToggleButton(
                icon: Icons.radio_button_unchecked,
                label: 'RINGS',
                isActive: controller.showRings.value,
                onTap: controller.toggleRings,
              ),
              _buildToggleButton(
                icon: Icons.star_outline,
                label: 'STARS',
                isActive: controller.showConstellations.value,
                onTap: controller.toggleConstellations,
              ),
              _buildToggleButton(
                icon: Icons.cloud,
                label: 'NEBULA',
                isActive: controller.showNebula.value,
                onTap: controller.toggleNebula,
              ),
              _buildToggleButton(
                icon: Icons.screen_rotation,
                label: 'GYRO',
                isActive: controller.useGyroscope.value,
                onTap: controller.toggleGyroscope,
              ),
              _buildExitButton(controller),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderControl({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required String suffix,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 8, letterSpacing: 1),
            ),
            Text(
              '${value.toStringAsFixed(value < 10 ? 2 : 0)}$suffix',
              style: TextStyle(
                color: color,
                fontFamily: 'Courier',
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            inactiveTrackColor: color.withAlpha(51),
            thumbColor: color,
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColor.bondiBlue.withAlpha(51) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? AppColor.bondiBlue : Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? AppColor.bondiBlue : Colors.white38, size: 16),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColor.bondiBlue : Colors.white38,
                fontSize: 7,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExitButton(NeomVR360StereoController controller) {
    return GestureDetector(
      onTap: controller.exitFullscreen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(51),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.red.withAlpha(128)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.exit_to_app, color: Colors.redAccent, size: 16),
            SizedBox(height: 3),
            Text(
              'EXIT',
              style: TextStyle(color: Colors.redAccent, fontSize: 7, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVRModeIndicator(NeomVR360StereoController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'L',
            style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 15),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: controller.useGyroscope.value
                  ? Colors.green.withAlpha(102)
                  : Colors.orange.withAlpha(102),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.vrpano, color: AppColor.bondiBlue.withAlpha(179), size: 12),
              const SizedBox(width: 5),
              Text(
                'VR HEADSET',
                style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 8, letterSpacing: 1),
              ),
              const SizedBox(width: 6),
              Icon(
                controller.useGyroscope.value ? Icons.screen_rotation : Icons.touch_app,
                color: controller.useGyroscope.value ? Colors.green : Colors.orange,
                size: 10,
              ),
            ],
          ),
        ),
        const SizedBox(width: 15),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'R',
            style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
