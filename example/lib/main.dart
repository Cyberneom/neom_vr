import 'package:flutter/material.dart';
import 'package:neom_vr/neom_vr.dart';
import 'package:sint/sint.dart';

void main() {
  runApp(const MyApp());
}

/// Aplicación principal de demostración del módulo neom_vr.
class MyApp extends StatelessWidget {
  /// Constructor base de la app de ejemplo.
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SintMaterialApp(
      title: 'Neom VR Demo',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

/// Pantalla de inicio con botón interactivo para entrar en el espacio VR.
class HomeScreen extends StatelessWidget {
  /// Constructor base de la pantalla de inicio.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neom VR Simulator'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.vrpano,
              size: 100,
              color: Colors.cyan,
            ),
            const SizedBox(height: 24),
            const Text(
              'Immersive VR Space Simulator',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Experience audio-reactive spatial constellation engines, concéntric rings, and 360-degree gyroscopic view simulation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                // Entramos directamente a la simulación espacial completa
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NeomSpatial360FullscreenPage(),
                  ),
                );
              },
              icon: const Icon(Icons.fullscreen),
              label: const Text('LAUNCH 360 VR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
