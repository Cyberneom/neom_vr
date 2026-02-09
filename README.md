# neom_vr

An experimental Virtual Reality module for Flutter applications, part of the Open Neom ecosystem. Focused on democratizing VR for smartphone users without expensive equipment.

## Current Version: 1.2.0

## Philosophy

**VR must be accessible to everyone.** We believe immersive experiences shouldn't require expensive headsets. neom_vr explores novel ways to deliver VR using readily available mobile devices.

## Features

### Current Capabilities (v1.2.0)
- **Custom Painter Engine**: Native VR rendering without external library dependencies
- **Sensor-Based Navigation**: Uses device sensors (accelerometer, gyroscope) for head tracking
- **360 Spatial Viewer**: Immersive panoramic content viewing
- **Stereo VR Mode**: Split-screen for Google Cardboard-style headsets
- **Fullscreen Experience**: Optimized immersive viewing

## Installation

```yaml
dependencies:
  neom_vr:
    git:
      url: git@github.com:Cyberneom/neom_vr.git
```

## Usage

```dart
import 'package:neom_vr/vr_routes.dart';

// Navigate to 360 spatial viewer
Navigator.pushNamed(context, VrRoutes.spatial360);

// Navigate to stereo VR mode
Navigator.pushNamed(context, VrRoutes.vrStereo);
```

---

## ROADMAP 2026: Accessible VR Platform

Our vision is to create a **world-class mobile VR platform** that makes immersive experiences accessible to everyone with a smartphone.

### Q1 2026: Core Engine Enhancement

#### Rendering Engine
- [ ] **GPU-Accelerated Rendering** - Custom shader-based 360 projection
- [ ] **Optimized Painter Engine** - 60 FPS on mid-range devices
- [ ] **LOD System** - Level of detail for performance scaling
- [ ] **Texture Streaming** - Progressive loading for large panoramas
- [ ] **Anti-Aliasing** - MSAA/FXAA for smoother edges

#### Sensor Fusion
- [ ] **Advanced IMU Processing** - Kalman filter for smooth tracking
- [ ] **Magnetic Calibration** - Compass integration for absolute orientation
- [ ] **Drift Correction** - Long-session stability
- [ ] **Low-Latency Pipeline** - <20ms motion-to-photon
- [ ] **Prediction Algorithm** - Compensate for rendering latency

### Q2 2026: Content & Formats

#### Media Support
- [ ] **360 Video Playback** - Equirectangular and cubemap formats
- [ ] **8K Support** - High-resolution panoramic videos
- [ ] **Spatial Audio** - 3D positional audio tied to head tracking
- [ ] **Live Streaming** - Real-time 360 content
- [ ] **Offline Caching** - Download VR content for offline viewing

#### Content Types
- [ ] **Photo Spheres** - High-resolution panoramic images
- [ ] **Virtual Tours** - Multi-room navigation with hotspots
- [ ] **360 Stories** - Interactive narrative experiences
- [ ] **VR Galleries** - Art and photography exhibitions

### Q3 2026: Interactive Experiences

#### User Interaction
- [ ] **Gaze-Based Selection** - Look-to-select UI
- [ ] **Cardboard Button Support** - Physical trigger input
- [ ] **Voice Commands** - Hands-free navigation
- [ ] **Gesture Recognition** - Camera-based hand tracking (experimental)

#### Guided Experiences
- [ ] **VR Meditation** - Immersive mindfulness environments
- [ ] **Breathing Exercises** - Visual breath guides in VR
- [ ] **Nature Escapes** - Calming virtual environments
- [ ] **Focus Spaces** - Distraction-free work environments

### Q4 2026: Advanced Features & AI

#### Biofeedback Integration
- [ ] **Heart Rate Visualization** - Real-time HRV display in VR
- [ ] **EEG Integration** - Brainwave visualization (with compatible devices)
- [ ] **Stress Response** - Environment adapts to user state
- [ ] **Session Analytics** - Track relaxation progress over time

#### AI-Powered Features
- [ ] **Auto-Generated Environments** - AI creates calming scenes
- [ ] **Personalized Experiences** - Content adapts to preferences
- [ ] **Smart Recommendations** - Suggest VR content based on mood
- [ ] **Voice-Guided Sessions** - AI narration for meditation

#### Social VR (Experimental)
- [ ] **Shared Viewing** - Watch 360 content together
- [ ] **Virtual Rooms** - Basic avatar presence
- [ ] **Group Meditation** - Synchronized guided sessions

### Technical Architecture Goals

```
lib/
├── core/
│   ├── engine/
│   │   ├── vr_painter_engine.dart     # Custom 360 rendering
│   │   ├── projection_math.dart       # Equirectangular/cubemap math
│   │   ├── shader_programs.dart       # GPU shaders
│   │   └── texture_manager.dart       # Efficient texture handling
│   ├── sensors/
│   │   ├── imu_processor.dart         # Accelerometer + Gyroscope
│   │   ├── sensor_fusion.dart         # Kalman filter implementation
│   │   └── drift_correction.dart      # Long-session stability
│   └── audio/
│       ├── spatial_audio.dart         # 3D positional audio
│       └── ambisonic_decoder.dart     # Surround sound support
├── features/
│   ├── viewer_360/                    # Panoramic viewer
│   ├── video_360/                     # 360 video player
│   ├── stereo_vr/                     # Cardboard-style split view
│   ├── interactive/                   # Gaze selection, hotspots
│   ├── meditation/                    # Guided VR experiences
│   └── biofeedback/                   # Health data visualization
└── ui/
    ├── vr_scaffold.dart               # Base VR page structure
    ├── gaze_pointer.dart              # Look-to-select cursor
    └── vr_controls.dart               # In-VR UI elements
```

### Performance Targets
- **Frame Rate**: 60 FPS sustained on mid-range devices
- **Motion-to-Photon**: <20ms latency
- **Memory Usage**: <300MB for 4K content
- **Battery Impact**: <15% per hour of use
- **Startup Time**: <2s to immersive view
- **Thermal**: No throttling for 30min sessions

### Device Compatibility Goals

| Tier | Devices | Features |
|------|---------|----------|
| High | Flagship (2024+) | Full 8K, spatial audio, all effects |
| Medium | Mid-range (2022+) | 4K content, basic audio, core effects |
| Low | Budget (2020+) | 2K content, mono audio, essential VR |

### Competitive Positioning

| Feature | neom_vr (2026) | YouTube VR | Google Cardboard | Within |
|---------|----------------|------------|------------------|--------|
| Custom Engine | Yes | No | No | No |
| Meditation Focus | Yes | No | No | Yes |
| Biofeedback | Yes | No | No | No |
| Offline Mode | Yes | Limited | Yes | Yes |
| Open Source | Yes | No | Partial | No |
| No Ads | Yes | No | N/A | Freemium |

---

## Dependencies

- `neom_core` - Core services and configuration
- `neom_commons` - Shared UI components
- `sensors_plus` - Device sensor access

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.

---

**Open Neom** - Democratizing VR for conscious digital experiences.
