import 'dart:math' as math;

import 'package:vrlizate_joystick/vrlizate_joystick.dart';

import 'vr_desktop_beacon_models.dart';
import 'vr_desktop_capabilities.dart';

/// Optional direct LAN telemetry reported by a Joystick smartphone directly to
/// the Desktop Estación Faro (`PC ↔ Joystick` direct UDP bridge).
class VrJoystickDirectBridgeTelemetry {
  const VrJoystickDirectBridgeTelemetry({
    required this.timestampMicros,
    this.batteryPercent,
    this.linkHz = 60,
    this.castOffloadedAck = false,
    this.visionOffloadedAck = false,
    this.capabilities,
  });

  final int timestampMicros;
  final int? batteryPercent;
  final int linkHz;
  final bool castOffloadedAck;
  final bool visionOffloadedAck;
  final VrMobileNodeCapabilities? capabilities;

  Map<String, Object?> toJson() => {
    'ts': timestampMicros,
    if (batteryPercent != null) 'bat': batteryPercent!.clamp(0, 100),
    'hz': linkHz.clamp(30, 240),
    'castAck': castOffloadedAck,
    'visAck': visionOffloadedAck,
    if (capabilities != null) 'jc': capabilities!.toJson(),
  };

  static VrJoystickDirectBridgeTelemetry? fromJson(Map<String, dynamic> map) {
    final ts = (map['ts'] as num?)?.toInt();
    if (ts == null || ts < 0) return null;
    final bat = (map['bat'] as num?)?.toInt();
    return VrJoystickDirectBridgeTelemetry(
      timestampMicros: ts,
      batteryPercent: bat?.clamp(0, 100),
      linkHz: ((map['hz'] as num?)?.toInt() ?? 60).clamp(30, 240),
      castOffloadedAck: map['castAck'] == true,
      visionOffloadedAck: map['visAck'] == true,
      capabilities: VrMobileNodeCapabilities.fromJson(map['jc']),
    );
  }
}

/// Actionable compute, offload, capability-matched topology, and safety
/// directive autonomously synthesized by **VRlizate Desktop (Estación Faro)**
/// and shared with both the **Visor** and the **Joystick**.
class VrDesktopBridgeDirective {
  const VrDesktopBridgeDirective({
    required this.decisionEpoch,
    required this.timestampMicros,
    required this.stationName,
    required this.autonomousMode,
    required this.offloadCastToDesktop,
    required this.offloadJoystickVisionToDesktop,
    required this.offloadVisorOpticalSlamToBeacon,
    required this.recommendedJoystickHz,
    required this.recommendedVisorQualityScale,
    required this.autoPassthroughFloor,
    required this.deskClearanceMeters,
    this.topologyMode = VrTriDeviceTopologyMode.sensorAiAndCastBridge,
    this.desktopTier = VrDesktopComputeTier.sensorAndAiBridge,
    this.pcRendersStereoFrame = false,
    this.pcHostsLocalAiAgents = false,
    this.substituteJoystickGyroWithPcVision = false,
    this.targetVisorRefreshHz = 60,
    this.vaultCatalogUrl,
    this.pushedVaultItemId,
    this.pushedVaultSeq = 0,
    this.joystickHapticAlert,
    required this.activeSummary,
    this.decisionLog = const [],
  });

  final int decisionEpoch;
  final int timestampMicros;
  final String stationName;
  final bool autonomousMode;

  /// Moves live `.vrlz` screen cast to the PC monitor and frees the Joystick
  /// smartphone from decoding/rendering video.
  final bool offloadCastToDesktop;

  /// Pauses local Joystick camera CV & ML body inference while the PC webcam
  /// holds high-confidence pose/hand lock; re-enables automatically if lost.
  final bool offloadJoystickVisionToDesktop;

  /// Allows the Visor to throttle local single-camera SLAM edge scanning while
  /// receiving 60 Hz metric room coordinates from the Desktop Faro station.
  final bool offloadVisorOpticalSlamToBeacon;

  /// Target Joystick input rate (`60` or `120` Hz) once freed from video/CV.
  final int recommendedJoystickHz;

  /// Adaptive render quality scale (`0.75 .. 1.0`) computed from Visor FPS.
  final double recommendedVisorQualityScale;

  /// Autonomous Breakthrough Chaperone opacity floor (`0.0 .. 0.75`) when the
  /// user approaches too close to the physical desk/monitor.
  final double autoPassthroughFloor;

  final double deskClearanceMeters;

  /// Optimal capability-matched workload topology across PC + Visor + Joystick.
  final VrTriDeviceTopologyMode topologyMode;

  /// Hardware capability tier of the connected Computer.
  final VrDesktopComputeTier desktopTier;

  /// True when the Computer renders the 3D stereo scene (`Modo Proyector PC-VR`)
  /// and the Smartphone Visor acts solely as optical Wi-Fi projector + TimeWarp.
  final bool pcRendersStereoFrame;

  /// True when the Computer has sufficient RAM/VRAM headroom to host local
  /// conversational/world AI agents alongside spatial tracking.
  final bool pcHostsLocalAiAgents;

  /// True when the Joystick lacks a physical gyroscope and the PC webcam AI
  /// substitutes spatial hand/controller orientation.
  final bool substituteJoystickGyroWithPcVision;

  /// Capability-matched target refresh rate for the Smartphone Visor (`60..120`).
  final int targetVisorRefreshHz;

  /// Authenticated LAN capability URL for the Desktop `3D-VR` Media Vault
  /// (`http://<lanIp>:<port>/<vaultToken>/api/catalog.json`).
  final String? vaultCatalogUrl;

  /// Optional Vault item ID pushed from the Desktop UI/Web Library for instant
  /// Dual-Eye `3D-VR` projection on the Smartphone Visor.
  final String? pushedVaultItemId;

  /// Monotonically increasing sequence number for [pushedVaultItemId].
  final int pushedVaultSeq;

  final String? joystickHapticAlert;
  final String activeSummary;
  final List<String> decisionLog;

  VrDesktopBridgeState toJoystickBridgeState({int revision = 1}) =>
      VrDesktopBridgeState(
        revision: revision,
        stationConnected: true,
        stationName: stationName,
        castOffloadedToDesktop: offloadCastToDesktop,
        visionOffloadedToDesktop: offloadJoystickVisionToDesktop,
        recommendedJoystickHz: recommendedJoystickHz,
        deskClearanceMeters: deskClearanceMeters,
        hapticAlert: joystickHapticAlert,
        activeDecisionSummary: activeSummary,
        topologyMode: topologyMode.name,
        substituteGyroWithPcVision: substituteJoystickGyroWithPcVision,
      );

  Map<String, Object?> toJson() => {
    'ep': decisionEpoch,
    'ts': timestampMicros,
    'st': stationName.length > 36 ? stationName.substring(0, 36) : stationName,
    'auto': autonomousMode,
    'castOff': offloadCastToDesktop,
    'joyCvOff': offloadJoystickVisionToDesktop,
    'visSlamOff': offloadVisorOpticalSlamToBeacon,
    'joyHz': recommendedJoystickHz,
    'qScale': double.parse(recommendedVisorQualityScale.toStringAsFixed(2)),
    'ptFloor': double.parse(autoPassthroughFloor.toStringAsFixed(2)),
    'deskM': double.parse(deskClearanceMeters.toStringAsFixed(2)),
    'topo': topologyMode.name,
    'pcTier': desktopTier.name,
    if (pcRendersStereoFrame) 'pcProj': true,
    if (pcHostsLocalAiAgents) 'pcAi': true,
    if (substituteJoystickGyroWithPcVision) 'pcGyro': true,
    'visHz': targetVisorRefreshHz,
    if (vaultCatalogUrl != null && vaultCatalogUrl!.length <= 240)
      'vUrl': vaultCatalogUrl,
    if (pushedVaultItemId != null && pushedVaultSeq > 0) ...{
      'vPush': pushedVaultItemId!.length > 64
          ? pushedVaultItemId!.substring(0, 64)
          : pushedVaultItemId,
      'vSeq': pushedVaultSeq,
    },
    if (joystickHapticAlert != null) 'hap': joystickHapticAlert,
    'sum': activeSummary.length > 96
        ? activeSummary.substring(0, 96)
        : activeSummary,
    if (decisionLog.isNotEmpty)
      'log': decisionLog
          .take(4)
          .map((e) => e.length > 88 ? e.substring(0, 88) : e)
          .toList(growable: false),
  };

  static VrDesktopBridgeDirective? fromJson(Map<String, dynamic> map) {
    final ep = (map['ep'] as num?)?.toInt();
    final ts = (map['ts'] as num?)?.toInt();
    if (ep == null || ep < 0 || ts == null || ts < 0) return null;
    final rawLog = map['log'];
    final log = rawLog is List
        ? rawLog.whereType<String>().take(6).toList(growable: false)
        : const <String>[];
    final topoName = map['topo'] as String?;
    final topo = VrTriDeviceTopologyMode.values
            .where((m) => m.name == topoName)
            .firstOrNull ??
        VrTriDeviceTopologyMode.sensorAiAndCastBridge;
    final tierName = map['pcTier'] as String?;
    final tier = VrDesktopComputeTier.values
            .where((t) => t.name == tierName)
            .firstOrNull ??
        VrDesktopComputeTier.sensorAndAiBridge;

    return VrDesktopBridgeDirective(
      decisionEpoch: ep,
      timestampMicros: ts,
      stationName: (map['st'] as String?) ?? 'PC Faro',
      autonomousMode: map['auto'] != false,
      offloadCastToDesktop: map['castOff'] == true,
      offloadJoystickVisionToDesktop: map['joyCvOff'] == true,
      offloadVisorOpticalSlamToBeacon: map['visSlamOff'] == true,
      recommendedJoystickHz: ((map['joyHz'] as num?)?.toInt() ?? 60).clamp(
        30,
        120,
      ),
      recommendedVisorQualityScale:
          ((map['qScale'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 1.0),
      autoPassthroughFloor:
          ((map['ptFloor'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      deskClearanceMeters:
          ((map['deskM'] as num?)?.toDouble() ?? 1.2).clamp(0.0, 10.0),
      topologyMode: topo,
      desktopTier: tier,
      pcRendersStereoFrame: map['pcProj'] == true,
      pcHostsLocalAiAgents: map['pcAi'] == true,
      substituteJoystickGyroWithPcVision: map['pcGyro'] == true,
      targetVisorRefreshHz:
          ((map['visHz'] as num?)?.toInt() ?? 60).clamp(30, 144),
      vaultCatalogUrl: map['vUrl'] as String?,
      pushedVaultItemId: map['vPush'] as String?,
      pushedVaultSeq: ((map['vSeq'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      joystickHapticAlert: map['hap'] as String?,
      activeSummary: (map['sum'] as String?) ?? 'Puente PC activo',
      decisionLog: log,
    );
  }
}

/// Hysteresis-stabilized autonomous decision engine running on the Computer.
///
/// Continuously evaluates the hardware capabilities of all 3 heterogeneous
/// devices (`Computadora` + `Visor` + `Joystick`), 3-node spatial depth, AI
/// hand/pose lock, network RTT, and Visor frame telemetry to orchestrate the
/// optimal workload split and physical safety interventions.
class VrDesktopAutonomousBridgeEngine {
  static const VrDesktopCapabilities _defaultDesktopCaps =
      VrDesktopCapabilities(
        os: 'desktop',
        arch: 'x86_64',
        cpuCores: 8,
        totalRamMb: 12288,
        hasHardwareVideoEncoder: true,
      );

  bool autonomousModeEnabled = true;
  bool castToDesktopEnabled = true;
  bool preferPcProjectorMode = false;

  int _epoch = 0;
  int _highConfidenceStreak = 0;
  bool _joystickVisionOffloaded = false;
  bool _deskSafetyActive = false;
  double _qualityScale = 1.0;
  int _lastProximityHapticUs = -10000000;
  VrBeaconHandGesture _lastGesture = VrBeaconHandGesture.none;
  bool? _lastLoggedCastOffload;
  bool? _lastLoggedVisionOffload;
  bool? _lastLoggedDeskWarn;
  bool? _lastLoggedGyroSub;
  double? _lastLoggedQuality;
  VrTriDeviceTopologyMode? _lastLoggedTopology;
  VrTriDeviceExecutionPlan? _latestPlan;
  final List<String> _decisionHistory = <String>[];

  List<String> get decisionHistory => List.unmodifiable(_decisionHistory);
  VrTriDeviceExecutionPlan? get latestExecutionPlan => _latestPlan;

  void _recordDecision(String entry) {
    if (_decisionHistory.isNotEmpty && _decisionHistory.first == entry) return;
    _decisionHistory.insert(0, entry);
    if (_decisionHistory.length > 8) {
      _decisionHistory.removeRange(8, _decisionHistory.length);
    }
  }

  VrDesktopBridgeDirective evaluate({
    required int nowMicros,
    required String stationName,
    required bool visorConnected,
    required VrTriNodeDepthSolution solution,
    VrDesktopCapabilities? desktopCapabilities,
    VrVisorBeaconFeedback? visorFeedback,
    VrJoystickDirectBridgeTelemetry? joystickTelemetry,
    String? vaultCatalogUrl,
    String? pushedVaultItemId,
    int pushedVaultSeq = 0,
  }) {
    _epoch++;
    final pcCaps = desktopCapabilities ?? _defaultDesktopCaps;
    final visorCaps = visorFeedback?.visorCapabilities;
    final joyCaps =
        joystickTelemetry?.capabilities ?? visorFeedback?.joystickCapabilities;
    final offloadCast = visorConnected && castToDesktopEnabled;

    if (_lastLoggedCastOffload != offloadCast && visorConnected) {
      _lastLoggedCastOffload = offloadCast;
      _recordDecision(
        offloadCast
            ? 'Pantalla transferida al monitor PC → Joystick liberado de video'
            : 'Transmisión devuelta al Joystick',
      );
    }

    if (!autonomousModeEnabled) {
      _joystickVisionOffloaded = false;
      _deskSafetyActive = false;
      _qualityScale = 1.0;
      _lastGesture = solution.gesture;
      return VrDesktopBridgeDirective(
        decisionEpoch: _epoch,
        timestampMicros: nowMicros,
        stationName: stationName,
        autonomousMode: false,
        offloadCastToDesktop: offloadCast,
        offloadJoystickVisionToDesktop: false,
        offloadVisorOpticalSlamToBeacon: false,
        recommendedJoystickHz: offloadCast ? 120 : 60,
        recommendedVisorQualityScale: 1.0,
        autoPassthroughFloor: 0.0,
        deskClearanceMeters: solution.deskClearanceMeters,
        topologyMode: VrTriDeviceTopologyMode.visorStandaloneLightBeacon,
        desktopTier: pcCaps.computeTier,
        vaultCatalogUrl: vaultCatalogUrl,
        pushedVaultItemId: pushedVaultItemId,
        pushedVaultSeq: pushedVaultSeq,
        activeSummary: offloadCast
            ? 'Vista en PC · Modo manual'
            : 'Puente PC en modo manual',
        decisionLog: List.unmodifiable(_decisionHistory),
      );
    }

    // 1. Autonomous Joystick CV Camera Offload with hysteresis
    final hasAiModality =
        (solution.activeModalitiesMask &
            VrTriNodeDepthSolution.modalityWebcamAi) !=
        0;
    if (pcCaps.computeTier == VrDesktopComputeTier.entryAssist) {
      _highConfidenceStreak = 0;
      _joystickVisionOffloaded = false;
    } else if (hasAiModality && solution.confidence >= 0.58) {
      _highConfidenceStreak = math.min(_highConfidenceStreak + 1, 10);
      if (_highConfidenceStreak >= 2) {
        _joystickVisionOffloaded = true;
      }
    } else if (!hasAiModality || solution.confidence < 0.38) {
      _highConfidenceStreak = 0;
      _joystickVisionOffloaded = false;
    }

    // 2. Negotiate Tri-Device Capability-Matched Execution Plan
    final plan = VrTriDeviceTopologyOptimizer.optimize(
      desktop: pcCaps,
      visor: visorCaps,
      joystick: joyCaps,
      rttMs: visorFeedback?.rttMs,
      visorFps: visorFeedback?.visorFps,
      webcamAiConfident: _joystickVisionOffloaded,
      castToDesktopEnabled: offloadCast,
      preferPcProjector: preferPcProjectorMode,
    );
    _latestPlan = plan;

    if (visorConnected && _lastLoggedTopology != plan.mode) {
      _lastLoggedTopology = plan.mode;
      _recordDecision('Topología Tri-Dispositivo → ${plan.summaryEs}');
    }

    if (visorConnected &&
        _lastLoggedGyroSub != plan.substituteJoystickGyroWithPcVision &&
        plan.substituteJoystickGyroWithPcVision) {
      _lastLoggedGyroSub = true;
      _recordDecision(
        'Joystick sin giroscopio físico → Orientación suplida por IA de Webcam PC',
      );
    } else if (!plan.substituteJoystickGyroWithPcVision) {
      _lastLoggedGyroSub = false;
    }

    if (visorConnected && _lastLoggedVisionOffload != _joystickVisionOffloaded) {
      _lastLoggedVisionOffload = _joystickVisionOffloaded;
      _recordDecision(
        _joystickVisionOffloaded
            ? 'IA PC óptima (${(solution.confidence * 100).round()}%) → Cámaras CV del Joystick en reposo térmico'
            : 'IA PC sin bloqueo visual → Cámaras ópticas del Joystick reactivadas como respaldo',
      );
    }

    // 3. Autonomous Visor SLAM offload & FPS-driven quality scaling
    final offloadVisorSlam =
        plan.offloadVisorSlamToPc ||
        (pcCaps.computeTier != VrDesktopComputeTier.entryAssist &&
            solution.confidence >= 0.52);
    final fps = visorFeedback?.visorFps ?? 60.0;
    if (plan.pcRendersStereoFrame) {
      _qualityScale = 1.0;
    } else if (fps < 46.0) {
      _qualityScale = 0.75;
    } else if (fps < 54.0) {
      _qualityScale = 0.88;
    } else if (fps >= 56.0) {
      _qualityScale = 1.0;
    }
    if (visorConnected && _lastLoggedQuality != _qualityScale) {
      _lastLoggedQuality = _qualityScale;
      if (_qualityScale < 1.0) {
        _recordDecision(
          'Visor a ${fps.round()} FPS → Escala adaptativa ${(_qualityScale * 100).round()}% + SLAM delegado a PC',
        );
      } else {
        _recordDecision(
          'Visor fluido (${fps.round()} FPS) → Calidad 100% mantenida con SLAM en PC',
        );
      }
    }

    // 4. Autonomous Desk Proximity Safety (Chaperone + Joystick Haptics)
    String? hapticAlert;
    double passthroughFloor = 0.0;
    final deskM = solution.deskClearanceMeters;
    if (deskM < 0.55) {
      _deskSafetyActive = true;
      passthroughFloor = ((0.55 - deskM) / 0.25).clamp(0.22, 0.72);
      if (nowMicros - _lastProximityHapticUs >= 2500000) {
        _lastProximityHapticUs = nowMicros;
        hapticAlert = 'desk_proximity_warning';
      }
    } else if (deskM >= 0.62) {
      _deskSafetyActive = false;
      passthroughFloor = 0.0;
    } else if (_deskSafetyActive) {
      passthroughFloor = 0.22;
    }

    if (visorConnected && _lastLoggedDeskWarn != _deskSafetyActive) {
      _lastLoggedDeskWarn = _deskSafetyActive;
      _recordDecision(
        _deskSafetyActive
            ? 'Escritorio cerca (${(deskM * 100).round()} cm) → Chaperone y vibración háptica activados'
            : 'Distancia al escritorio segura (${(deskM * 100).round()} cm) → Inmersión 100% restaurada',
      );
    }

    // 5. Tactile confirmation on pinch transition
    final isPinch =
        solution.gesture == VrBeaconHandGesture.leftPinch ||
        solution.gesture == VrBeaconHandGesture.rightPinch;
    final wasPinch =
        _lastGesture == VrBeaconHandGesture.leftPinch ||
        _lastGesture == VrBeaconHandGesture.rightPinch;
    _lastGesture = solution.gesture;
    if (isPinch && !wasPinch && hapticAlert == null) {
      hapticAlert = 'hand_pinch_confirm';
    }

    // 6. Recommended Joystick Hz boost when freed from video & CV (and not BLE-only)
    final recommendedHz =
        (!(joyCaps?.bleOnly ?? false) && offloadCast && _joystickVisionOffloaded)
            ? 120
            : 60;

    final summaryParts = <String>[
      if (plan.pcRendersStereoFrame)
        'Proyector PC-VR ${plan.targetVisorRefreshHz}Hz'
      else if (offloadCast)
        'Vista→PC',
      if (_joystickVisionOffloaded) 'CV→PC' else 'CV→Dúo',
      if (plan.substituteJoystickGyroWithPcVision) 'Gyro→Webcam',
      '${recommendedHz}Hz',
      if (_qualityScale < 1.0) 'Q${(_qualityScale * 100).round()}%',
      if (_deskSafetyActive) 'Alerta ${(deskM * 100).round()}cm',
    ];

    return VrDesktopBridgeDirective(
      decisionEpoch: _epoch,
      timestampMicros: nowMicros,
      stationName: stationName,
      autonomousMode: true,
      offloadCastToDesktop: offloadCast,
      offloadJoystickVisionToDesktop: _joystickVisionOffloaded,
      offloadVisorOpticalSlamToBeacon: offloadVisorSlam,
      recommendedJoystickHz: recommendedHz,
      recommendedVisorQualityScale: _qualityScale,
      autoPassthroughFloor: passthroughFloor,
      deskClearanceMeters: deskM,
      topologyMode: plan.mode,
      desktopTier: pcCaps.computeTier,
      pcRendersStereoFrame: plan.pcRendersStereoFrame,
      pcHostsLocalAiAgents: plan.pcHostsLocalAiAgents,
      substituteJoystickGyroWithPcVision:
          plan.substituteJoystickGyroWithPcVision,
      targetVisorRefreshHz: plan.targetVisorRefreshHz,
      vaultCatalogUrl: vaultCatalogUrl,
      pushedVaultItemId: pushedVaultItemId,
      pushedVaultSeq: pushedVaultSeq,
      joystickHapticAlert: hapticAlert,
      activeSummary: summaryParts.join(' · '),
      decisionLog: List.unmodifiable(_decisionHistory),
    );
  }
}
