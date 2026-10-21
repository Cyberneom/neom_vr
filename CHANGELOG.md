### 2.0.0 - SINT 2.0, Tri-Camera Passthrough HUD & Portable `.vrlw` Ecosystem

- Upgrade `neom_vr` to `2.0.0` powered by `sint: ^2.0.0` (`NeomVrHostBindings`).
- Extract Open Neom Ecosystem (`lib/ecosystem/`), AI Assistant (`lib/ai/`) and BLE Controller (`lib/ble/`) services into `neom_vr` (`neom_vr_ecosystem.dart`, `neom_vr_ai.dart`, `neom_vr_ble.dart`).
- Add `VrStereoPassthroughCameraFeed` and `VrTriCameraInspectorSheet` for live Tri-Camera + Ultrasonic + 6-Channel Synthetic LiDAR spatial inspection and stereo passthrough preview.
- Support `VrHomeRoomPurpose.portableWorld` and `VrHomeRoomIcon.world` in `VrNeomRoomPreview` for dynamic `.vrlw` Mall storefronts.
- Centralize constants in `NeomVrConstants` and `NeomVrTranslationConstants`.

### 1.4.0 - Open Neom integration for renderer sessions

- Replace the `sint_vr` dependency with vrlizate 1.13.0 and SINT 1.7.0-dev.1.
- Add `neom_vr_sessions.dart`, `NeomVrSessionController` and `NeomVrSessionHost`.
  The bridge composes the core controller; the renderer lifecycle remains in
  vrlizate, without a second state machine or resource owner.
- Register hosted bridges under unique permanent tags and protect foreign
  replacements during disposal. External SINT deletion closes the core session.
- Move VR bindings, legacy controller/scene state, scene navigation and translation
  maps into neom_vr, retaining their public names and ownership semantics.
- Use SINT's generic navigation fixes directly; correct stale engine attribution.
- Raise the minimum toolchain to Dart 3.12 / Flutter 3.47 for these dependencies.
- Add registration, error, nested-host, replacement and engine-ownership tests.

### 1.2.0 - Custom Painter Engine & Enhanced VR Experience

This release represents a major evolution towards a fully custom VR rendering solution, moving away from external library dependencies.

**Key Changes:**

**Custom Painter Engine:**
- Introduced `NeomVrPainterEngine` - a native Flutter CustomPainter for 360° rendering
- Removed dependency on external panorama and video_360 libraries
- Equirectangular projection math implemented from scratch
- Foundation for GPU-accelerated rendering in future releases

**Sensor-Based Navigation:**
- Enhanced `NeomSpatial360Controller` with improved sensor fusion
- Better accelerometer and gyroscope integration for head tracking
- Smoother orientation updates with optimized sensor event handling
- Groundwork for Kalman filter implementation (Q1 2026)

**Stereo VR Mode:**
- Improved `NeomVr360StereoPage` for Google Cardboard-style viewing
- Split-screen rendering with proper eye separation
- Fullscreen immersive experience optimization

**Architecture Improvements:**
- Reorganized route structure in `vr_routes.dart`
- Centralized VR widgets in `vr_widgets.dart`
- Updated to flutter_lints ^5.0.0
- SDK constraint updated to >=3.8.0 <4.0.0
- sensors_plus upgraded to ^6.1.1

**Documentation:**
- Comprehensive ROADMAP 2026 added to README.md
- Technical architecture goals defined
- Performance targets established (60 FPS, <20ms latency)
- Device compatibility tiers documented

---

### 1.1.0 - Initial Release & Experimental VR Development
This release is to start a new way of VR manipulation with painters and sensors instead of libraries
to create basic neom functionalities instead of trying to get Youtube VR Videos.

### 1.0.0 - Initial Release & Experimental VR Development
This release marks the initial official release (v1.0.0) of neom_vr as a new, independent and experimental module within the Open Neom ecosystem. This module is introduced to research and develop Virtual Reality (VR) functionalities, specifically focusing on democratizing VR for smartphone users.

Key Highlights of this Release:

New Module Introduction & Experimental Focus:

neom_vr is now a dedicated module for VR-related processes, serving as an R&D sandbox for mobile VR.

Its primary goal is to explore how immersive experiences can be delivered on readily available smartphone devices.

Foundational VR Capabilities:

Includes initial functionalities for 360 video playback (video_360 integration) and panoramic image viewing (panorama integration).

Implements a smartphone VR split view (split_view) to enable stereoscopic viewing for mobile VR headsets (e.g., Google Cardboard).

Provides experimental integration for launching external web-based VR experiences (e.g., WebVR/WebXR) via custom tabs.

Module-Specific Translations:

Introduced VrTranslationConstants to centralize and manage all UI text strings specific to VR functionalities. This ensures improved localization, maintainability, and consistency with Open Neom's global strategy.

Architectural Alignment for Experimentation:

While experimental, the module is structured to adhere to Open Neom's Clean Architecture principles where feasible, ensuring that its development contributes to the overall modularity and integrity of the project.

It leverages neom_core for core services and neom_commons for reusable UI components and utilities.

Future-Oriented Development:

This initial release lays the groundwork for ambitious future expansion into advanced video editing, interactive VR experiences, biofeedback visualization in VR, and spatial audio.

Overall Benefits of this Initial Release:

Pioneering Accessible VR: Directly addresses Open Neom's vision of democratizing VR, making immersive experiences available to a wider audience.

Dedicated R&D Space: Provides a focused environment for continuous research and development in mobile VR technologies.

Enhanced User Engagement: Introduces novel ways for users to interact with content and experience digital well-being.

Stronger Clean Architecture Adherence: Even as an experimental module, its structured introduction reinforces the modular design principles of Open Neom.