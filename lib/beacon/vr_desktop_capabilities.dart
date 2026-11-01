import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'vr_desktop_vision_platform.dart';

/// High-level VRlizate ecosystem device architecture:
/// - [twoDevices2dVr] (`Two-Devices VR · 2D-VR`): Smartphone Visor + Smartphone
///   Joystick — ultra-portable pocket VR running lightweight local packages.
/// - [threeDevices3dVr] (`Three-Devices VR · 3D-VR`): Computer + Smartphone
///   Visor + Smartphone Joystick — true triangulated spatial depth (`6-DoF` +
///   AI hands), holographic off-axis parallax, and dual-eye stereo LAN Vault.
enum VrEcosystemDeviceTier {
  twoDevices2dVr,
  threeDevices3dVr;

  String get shortCode => switch (this) {
    VrEcosystemDeviceTier.twoDevices2dVr => '2D-VR',
    VrEcosystemDeviceTier.threeDevices3dVr => '3D-VR',
  };

  String get labelEs => switch (this) {
    VrEcosystemDeviceTier.twoDevices2dVr => 'Two-Devices VR (2D-VR)',
    VrEcosystemDeviceTier.threeDevices3dVr => 'Three-Devices VR (3D-VR)',
  };

  String get descriptionEs => switch (this) {
    VrEcosystemDeviceTier.twoDevices2dVr =>
      'Visor + Joystick portátiles · biblioteca ligera local en el smartphone',
    VrEcosystemDeviceTier.threeDevices3dVr =>
      'Computadora + Visor + Joystick · profundidad holográfica 3D y Bóveda LAN estéreo',
  };

  static VrEcosystemDeviceTier fromWire(String? value) =>
      value == '3D-VR' || value == 'threeDevices3dVr'
      ? VrEcosystemDeviceTier.threeDevices3dVr
      : VrEcosystemDeviceTier.twoDevices2dVr;
}

/// Vendor-neutral capability tier classified from the real hardware reported by
/// any personal computer (Windows, Linux, or macOS — Intel, AMD, NVIDIA, or
/// Apple Silicon).
enum VrDesktopComputeTier {
  /// Modest laptop/PC (<= 6 GB RAM, < 4 cores, or thermally constrained):
  /// provides Wi-Fi/BLE spatial ranging and optional spectator screen without
  /// running heavy AI or stereo render streaming.
  entryAssist,

  /// Standard computer (8–15 GB RAM, >= 4 cores): absorbs live Cast monitor,
  /// runs webcam AI body/hand tracking + 3-node depth, and frees the Joystick
  /// to 120 Hz pure input while the Visor runs `.vrlz` unloaded.
  sensorAndAiBridge,

  /// High-capability computer (>= 16 GB RAM, >= 8 cores or >= 6 GB GPU budget):
  /// handles 60 Hz 6-DoF, Cast, and AI/world co-processing alongside the Visor.
  hybridSplitCompute,

  /// PC-VR projector-capable computer (>= 16 GB RAM, hardware low-latency video
  /// encoder, >= 8 GB GPU working set, nominal thermals): can render full
  /// stereo worlds on the PC and stream them to the Smartphone Visor acting as
  /// a lightweight optical Wi-Fi projector with local gyro TimeWarp.
  fullPcVrProjectorCapable;

  String get labelEs => switch (this) {
    VrDesktopComputeTier.entryAssist => 'Faro Ligero (Asistencia Básica)',
    VrDesktopComputeTier.sensorAndAiBridge => 'Puente Sensores + IA + Cast',
    VrDesktopComputeTier.hybridSplitCompute => 'Cómputo Híbrido Avanzado',
    VrDesktopComputeTier.fullPcVrProjectorCapable =>
      'Estación PC-VR Completa (Proyector Habilitado)',
  };
}

/// Optimal workload distribution negotiated across the 3 heterogeneous devices
/// (`Computadora` + `Smartphone Visor` + `Smartphone Joystick`).
enum VrTriDeviceTopologyMode {
  /// Visor renders `.vrlz`; PC contributes lightweight Wi-Fi/BLE anchor only.
  visorStandaloneLightBeacon,

  /// Visor renders `.vrlz` unloaded; PC takes Cast + AI vision; Joystick runs
  /// pure 120 Hz input (or webcam-substituted orientation if lacking a gyro).
  sensorAiAndCastBridge,

  /// Visor renders `.vrlz` at boosted quality while PC co-processes 60 Hz
  /// 6-DoF, Cast, and local AI/world tasks (also used when PC is powerful but
  /// Wi-Fi RTT/2.4 GHz makes full PC->Visor video streaming unsafe for comfort).
  hybridSplitCompute,

  /// Computer renders the stereo experience (+ optional local AI agents),
  /// Smartphone Visor acts solely as low-temp Wi-Fi optical projector + local
  /// gyro TimeWarp, and Smartphone Joystick runs dedicated 120 Hz input.
  pcRenderVisorProjector;

  String get labelEs => switch (this) {
    VrTriDeviceTopologyMode.visorStandaloneLightBeacon =>
      'Visor Soberano + Faro Ligero',
    VrTriDeviceTopologyMode.sensorAiAndCastBridge =>
      'Puente IA + Cast en PC + Joystick 120 Hz',
    VrTriDeviceTopologyMode.hybridSplitCompute =>
      'Cómputo Híbrido (Visor + Co-Procesador PC)',
    VrTriDeviceTopologyMode.pcRenderVisorProjector =>
      'Modo Visor PC-VR (Render en PC → Proyector Visor)',
  };
}

/// Hardware capabilities probed dynamically on the Desktop station.
@immutable
class VrDesktopCapabilities {
  const VrDesktopCapabilities({
    required this.os,
    required this.arch,
    required this.cpuCores,
    required this.totalRamMb,
    this.gpuName = 'Generic GPU',
    this.gpuWorkingSetMb = 0,
    this.hasUnifiedMemory = false,
    this.supportsRaytracing = false,
    this.hasHardwareVideoEncoder = false,
    this.hasWebcam = false,
    this.thermalLevel = 0,
  });

  final String os;
  final String arch;
  final int cpuCores;
  final int totalRamMb;
  final String gpuName;
  final int gpuWorkingSetMb;
  final bool hasUnifiedMemory;
  final bool supportsRaytracing;
  final bool hasHardwareVideoEncoder;
  final bool hasWebcam;

  /// `0` = nominal, `1` = fair, `2` = serious, `3` = critical.
  final int thermalLevel;

  bool get isThermallyConstrained => thermalLevel >= 2;

  /// Effective memory available to GPU/AI workloads in MiB.
  int get effectiveGpuBudgetMb => gpuWorkingSetMb > 0
      ? gpuWorkingSetMb
      : (hasUnifiedMemory ? (totalRamMb * 3) ~/ 4 : totalRamMb ~/ 4);

  /// True when the computer has enough memory bandwidth/headroom to run local
  /// conversational/world AI models alongside 3D & vision workloads.
  bool get canHostLocalAiModels =>
      !isThermallyConstrained &&
      totalRamMb >= 24576 &&
      effectiveGpuBudgetMb >= 12288;

  VrDesktopComputeTier get computeTier {
    if (isThermallyConstrained || cpuCores < 4 || totalRamMb < 6144) {
      return VrDesktopComputeTier.entryAssist;
    }
    if (totalRamMb >= 16384 &&
        hasHardwareVideoEncoder &&
        (effectiveGpuBudgetMb >= 8192 ||
            (cpuCores >= 10 && totalRamMb >= 24576))) {
      return VrDesktopComputeTier.fullPcVrProjectorCapable;
    }
    if (totalRamMb >= 16384 &&
        (cpuCores >= 8 || effectiveGpuBudgetMb >= 6144)) {
      return VrDesktopComputeTier.hybridSplitCompute;
    }
    return VrDesktopComputeTier.sensorAndAiBridge;
  }

  String get shortSummaryEs {
    final ramGb = (totalRamMb / 1024).round();
    return '$os ($arch) · $cpuCores núcleos · ${ramGb}GB RAM · $gpuName';
  }

  Map<String, Object?> toJson() => {
    'os': os,
    'arch': arch,
    'cores': cpuCores,
    'ramMb': totalRamMb,
    'gpu': gpuName.length > 48 ? gpuName.substring(0, 48) : gpuName,
    'gpuMb': gpuWorkingSetMb,
    'unified': hasUnifiedMemory,
    'rt': supportsRaytracing,
    'hwEnc': hasHardwareVideoEncoder,
    'cam': hasWebcam,
    'therm': thermalLevel,
    'tier': computeTier.name,
  };

  static VrDesktopCapabilities? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    final cores = (raw['cpuCores'] ?? raw['cores']) as num?;
    final ram = (raw['totalRamMb'] ?? raw['ramMb']) as num?;
    if (cores == null || ram == null) return null;
    return VrDesktopCapabilities(
      os: ((raw['os'] as String?) ?? 'desktop').trim(),
      arch: ((raw['arch'] as String?) ?? 'unknown').trim(),
      cpuCores: cores.toInt().clamp(1, 256),
      totalRamMb: ram.toInt().clamp(512, 2097152),
      gpuName: ((raw['gpuName'] ?? raw['gpu']) as String?)?.trim() ?? 'GPU',
      gpuWorkingSetMb:
          (((raw['gpuWorkingSetMb'] ?? raw['gpuMb']) as num?)?.toInt() ?? 0)
              .clamp(0, 2097152),
      hasUnifiedMemory:
          raw['hasUnifiedMemory'] == true || raw['unified'] == true,
      supportsRaytracing:
          raw['supportsRaytracing'] == true || raw['rt'] == true,
      hasHardwareVideoEncoder:
          raw['hasHardwareVideoEncoder'] == true || raw['hwEnc'] == true,
      hasWebcam: raw['hasWebcam'] == true || raw['cam'] == true,
      thermalLevel:
          (((raw['thermalLevel'] ?? raw['therm']) as num?)?.toInt() ?? 0).clamp(
            0,
            3,
          ),
    );
  }
}

/// Compact capability summary reported by a mobile node (`visor` or `joystick`)
/// so the Desktop bridge can optimize the 3-device topology dynamically.
@immutable
class VrMobileNodeCapabilities {
  const VrMobileNodeCapabilities({
    required this.role,
    this.modelLabel = 'Smartphone',
    this.totalRamMb,
    this.cpuCores,
    this.maxRefreshHz = 60,
    this.isLowRam = false,
    this.hasHardwareGyro = true,
    this.wifi5Or6Ghz = true,
    this.wifi24Ghz = false,
    this.bleOnly = false,
    this.thermalLevel = 0,
  });

  final String role;
  final String modelLabel;
  final int? totalRamMb;
  final int? cpuCores;
  final int maxRefreshHz;
  final bool isLowRam;
  final bool hasHardwareGyro;
  final bool wifi5Or6Ghz;
  final bool wifi24Ghz;
  final bool bleOnly;
  final int thermalLevel;

  bool get isModestOrConstrained =>
      isLowRam ||
      (totalRamMb != null && totalRamMb! <= 6144) ||
      thermalLevel >= 2;

  factory VrMobileNodeCapabilities.fromDeviceCapabilities(
    VrDeviceCapabilities? caps, {
    required String role,
    bool bleOnly = false,
  }) {
    if (caps == null) {
      return VrMobileNodeCapabilities(role: role, bleOnly: bleOnly);
    }
    final label = '${caps.manufacturer} ${caps.model}'.trim();
    final maxHz = (caps.maxSupportedRefreshHz ?? 60.0).round().clamp(30, 144);
    final ram = caps.totalRamMb;
    final lowRam = caps.isLowRamDevice == true || (ram != null && ram <= 4200);
    return VrMobileNodeCapabilities(
      role: role,
      modelLabel: label.isEmpty ? 'Smartphone' : label,
      totalRamMb: ram,
      cpuCores: caps.cpuCores,
      maxRefreshHz: maxHz,
      isLowRam: lowRam,
      hasHardwareGyro: caps.hasHardwareGyroscope ?? true,
      wifi5Or6Ghz: caps.isOn5GhzOr6GhzWifi || (caps.supportsWifi5Ghz ?? true),
      wifi24Ghz: caps.isOn24GhzWifi,
      bleOnly: bleOnly,
      thermalLevel: (caps.thermalStatus ?? 0).clamp(0, 3),
    );
  }

  String get shortSummaryEs {
    final ramPart = totalRamMb != null
        ? ' · ${(totalRamMb! / 1024).toStringAsFixed(0)}GB'
        : '';
    final gyroPart = hasHardwareGyro ? '' : ' · sin giroscopio';
    return '$modelLabel$ramPart · ${maxRefreshHz}Hz$gyroPart';
  }

  Map<String, Object?> toJson() => {
    'r': role,
    'm': modelLabel.length > 32 ? modelLabel.substring(0, 32) : modelLabel,
    if (totalRamMb != null) 'ram': totalRamMb,
    if (cpuCores != null) 'c': cpuCores,
    'hz': maxRefreshHz,
    if (isLowRam) 'low': true,
    if (!hasHardwareGyro) 'noGyro': true,
    if (!wifi5Or6Ghz) 'w5': false,
    if (wifi24Ghz) 'w24': true,
    if (bleOnly) 'ble': true,
    if (thermalLevel > 0) 'th': thermalLevel,
  };

  static VrMobileNodeCapabilities? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final role = (raw['r'] as String?) ?? 'visor';
    return VrMobileNodeCapabilities(
      role: role,
      modelLabel: ((raw['m'] as String?) ?? 'Smartphone').trim(),
      totalRamMb: (raw['ram'] as num?)?.toInt(),
      cpuCores: (raw['c'] as num?)?.toInt(),
      maxRefreshHz: (((raw['hz'] as num?)?.toInt()) ?? 60).clamp(30, 144),
      isLowRam: raw['low'] == true,
      hasHardwareGyro: raw['noGyro'] != true,
      wifi5Or6Ghz: raw['w5'] != false,
      wifi24Ghz: raw['w24'] == true,
      bleOnly: raw['ble'] == true,
      thermalLevel: (((raw['th'] as num?)?.toInt()) ?? 0).clamp(0, 3),
    );
  }
}

/// Complete capability-aware execution plan across Computer, Visor, and Joystick.
@immutable
class VrTriDeviceExecutionPlan {
  const VrTriDeviceExecutionPlan({
    required this.mode,
    required this.desktopTier,
    required this.pcRendersStereoFrame,
    required this.pcHostsLocalAiAgents,
    required this.offloadCastToPcMonitor,
    required this.offloadJoystickCvToPc,
    required this.offloadVisorSlamToPc,
    required this.substituteJoystickGyroWithPcVision,
    required this.targetVisorRefreshHz,
    required this.targetJoystickHz,
    required this.recommendedVisorQualityScale,
    required this.summaryEs,
  });

  final VrTriDeviceTopologyMode mode;
  final VrDesktopComputeTier desktopTier;
  final bool pcRendersStereoFrame;
  final bool pcHostsLocalAiAgents;
  final bool offloadCastToPcMonitor;
  final bool offloadJoystickCvToPc;
  final bool offloadVisorSlamToPc;
  final bool substituteJoystickGyroWithPcVision;
  final int targetVisorRefreshHz;
  final int targetJoystickHz;
  final double recommendedVisorQualityScale;
  final String summaryEs;

  /// Connecting a Computer upgrades the session to `Three-Devices VR (3D-VR)`.
  VrEcosystemDeviceTier get ecosystemTier =>
      VrEcosystemDeviceTier.threeDevices3dVr;
}

/// Cross-platform Desktop hardware capability detector (macOS, Linux, Windows).
class VrDesktopHardwareProbe {
  static Future<VrDesktopCapabilities> probe({
    VrDesktopVisionPlatform? visionPlatform,
    bool? hasWebcamFallback,
  }) async {
    if (!kIsWeb && visionPlatform != null) {
      final nativeMap = await visionPlatform.readCapabilities();
      final parsed = VrDesktopCapabilities.fromMap(nativeMap);
      if (parsed != null) return parsed;
    }

    if (kIsWeb) {
      return const VrDesktopCapabilities(
        os: 'web',
        arch: 'wasm',
        cpuCores: 4,
        totalRamMb: 8192,
      );
    }

    final os = Platform.operatingSystem;
    final cores = Platform.numberOfProcessors.clamp(1, 256);
    var ramMb = _estimateFallbackRamMb(cores);
    var gpuName = switch (os) {
      'macos' => 'Apple / Metal GPU',
      'windows' => 'Direct3D / Vulkan GPU',
      'linux' => 'Vulkan / OpenGL GPU',
      _ => 'Desktop GPU',
    };

    if (os == 'linux') {
      ramMb = _readLinuxMemInfoMb() ?? ramMb;
      gpuName = _readLinuxCpuModel() ?? gpuName;
    }

    final arch = Platform.version.contains('arm64') ? 'arm64' : 'x86_64';
    final unified = os == 'macos' && arch == 'arm64';
    return VrDesktopCapabilities(
      os: os,
      arch: arch,
      cpuCores: cores,
      totalRamMb: ramMb,
      gpuName: gpuName,
      gpuWorkingSetMb: unified ? (ramMb * 3) ~/ 4 : ramMb ~/ 3,
      hasUnifiedMemory: unified,
      supportsRaytracing: cores >= 8 && ramMb >= 16384,
      hasHardwareVideoEncoder: cores >= 4 && ramMb >= 8192,
      hasWebcam: hasWebcamFallback ?? false,
    );
  }

  static int _estimateFallbackRamMb(int cores) {
    if (cores >= 12) return 32768;
    if (cores >= 8) return 16384;
    if (cores >= 4) return 8192;
    return 4096;
  }

  static int? _readLinuxMemInfoMb() {
    try {
      final file = File('/proc/meminfo');
      if (!file.existsSync()) return null;
      for (final line in file.readAsLinesSync()) {
        if (line.startsWith('MemTotal:')) {
          final match = RegExp(r'(\d+)').firstMatch(line);
          if (match != null) {
            final kb = int.tryParse(match.group(1)!);
            if (kb != null && kb > 0) return kb ~/ 1024;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _readLinuxCpuModel() {
    try {
      final file = File('/proc/cpuinfo');
      if (!file.existsSync()) return null;
      for (final line in file.readAsLinesSync()) {
        if (line.startsWith('model name')) {
          final idx = line.indexOf(':');
          if (idx != -1) {
            final name = line.substring(idx + 1).trim();
            if (name.isNotEmpty) return name;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

/// Evaluates the real capabilities of all 3 heterogeneous devices (`Computadora`,
/// `Smartphone Visor`, and `Smartphone Joystick`) + live link latency/FPS to
/// pick the optimal, comfort-safe execution split.
class VrTriDeviceTopologyOptimizer {
  static VrTriDeviceExecutionPlan optimize({
    required VrDesktopCapabilities desktop,
    VrMobileNodeCapabilities? visor,
    VrMobileNodeCapabilities? joystick,
    double? rttMs,
    double? visorFps,
    bool webcamAiConfident = false,
    bool castToDesktopEnabled = true,
    bool preferPcProjector = false,
  }) {
    final pcTier = desktop.computeTier;
    final visorMaxHz = (visor?.maxRefreshHz ?? 60).clamp(60, 120);
    final joystickBleOnly = joystick?.bleOnly ?? false;
    final joystickMissingGyro = joystick != null && !joystick.hasHardwareGyro;
    final substituteGyro = joystickMissingGyro && webcamAiConfident;

    // 1. Entry-level or thermally constrained PC: keep Visor sovereign and avoid
    // overloading the laptop/PC with heavy AI or streaming.
    if (pcTier == VrDesktopComputeTier.entryAssist) {
      return VrTriDeviceExecutionPlan(
        mode: VrTriDeviceTopologyMode.visorStandaloneLightBeacon,
        desktopTier: pcTier,
        pcRendersStereoFrame: false,
        pcHostsLocalAiAgents: false,
        offloadCastToPcMonitor: castToDesktopEnabled,
        offloadJoystickCvToPc: false,
        offloadVisorSlamToPc: false,
        substituteJoystickGyroWithPcVision: false,
        targetVisorRefreshHz: 60,
        targetJoystickHz: 60,
        recommendedVisorQualityScale:
            (visorFps != null && visorFps < 46.0) ? 0.80 : 0.92,
        summaryEs:
            'PC modesta/térmica: Visor corre .vrlz local + PC aporta ancla ligera',
      );
    }

    // Check if the Wi-Fi link between PC and Visor is clean enough for comfort-safe
    // stereo PC-VR projection (never project over 2.4 GHz or high RTT > 18 ms).
    final visorWifiFast = !(visor?.wifi24Ghz ?? false) && !(visor?.bleOnly ?? false);
    final rttSafeForProjector = rttMs == null || rttMs <= 18.0;
    final linkSupportsPcProjector = visorWifiFast && rttSafeForProjector;

    final visorBenefitsFromPcRender =
        preferPcProjector ||
        (visor?.isModestOrConstrained ?? false) ||
        (visorFps != null && visorFps < 48.0);

    final joyHz = (!joystickBleOnly && (castToDesktopEnabled || webcamAiConfident))
        ? 120
        : 60;

    // 2. Full PC-VR Projector Mode: PC has GPU + HW Video Encoder + clean 5/6 GHz
    // link, and either user requested PC-VR mode or the Visor phone is modest/hot.
    if (pcTier == VrDesktopComputeTier.fullPcVrProjectorCapable &&
        linkSupportsPcProjector &&
        visorBenefitsFromPcRender) {
      final targetHz = visorMaxHz >= 90 ? visorMaxHz : 60;
      return VrTriDeviceExecutionPlan(
        mode: VrTriDeviceTopologyMode.pcRenderVisorProjector,
        desktopTier: pcTier,
        pcRendersStereoFrame: true,
        pcHostsLocalAiAgents: desktop.canHostLocalAiModels,
        offloadCastToPcMonitor: true,
        offloadJoystickCvToPc: webcamAiConfident,
        offloadVisorSlamToPc: true,
        substituteJoystickGyroWithPcVision: substituteGyro,
        targetVisorRefreshHz: targetHz,
        targetJoystickHz: joyHz,
        recommendedVisorQualityScale: 1.0,
        summaryEs: desktop.canHostLocalAiModels
            ? 'Modo Visor PC-VR (${targetHz}Hz TimeWarp) + IA Local en PC + Joy ${joyHz}Hz'
            : 'Modo Visor PC-VR: PC renderiza 3D → Visor proyecta (${targetHz}Hz)',
      );
    }

    // 3. Hybrid Split Compute: PC is powerful (hybridSplitCompute, or
    // fullPcVrProjectorCapable when Visor is already flagship/smooth or on 2.4 GHz).
    if (pcTier == VrDesktopComputeTier.hybridSplitCompute ||
        pcTier == VrDesktopComputeTier.fullPcVrProjectorCapable) {
      final scale = (visorFps != null && visorFps < 45.0)
          ? 0.78
          : ((visorFps != null && visorFps < 54.0) ? 0.90 : 1.0);
      final blockedByWifi =
          pcTier == VrDesktopComputeTier.fullPcVrProjectorCapable &&
          visorBenefitsFromPcRender &&
          !linkSupportsPcProjector;
      return VrTriDeviceExecutionPlan(
        mode: VrTriDeviceTopologyMode.hybridSplitCompute,
        desktopTier: pcTier,
        pcRendersStereoFrame: false,
        pcHostsLocalAiAgents: desktop.canHostLocalAiModels,
        offloadCastToPcMonitor: castToDesktopEnabled,
        offloadJoystickCvToPc: webcamAiConfident,
        offloadVisorSlamToPc: webcamAiConfident,
        substituteJoystickGyroWithPcVision: substituteGyro,
        targetVisorRefreshHz: visorMaxHz,
        targetJoystickHz: joyHz,
        recommendedVisorQualityScale: scale,
        summaryEs: blockedByWifi
            ? 'Cómputo Híbrido (Wi-Fi lento/2.4GHz bloquea proyector para evitar mareo)'
            : 'Cómputo Híbrido: Visor ${visorMaxHz}Hz + PC IA/6-DoF + Joy ${joyHz}Hz',
      );
    }

    // 4. Standard Sensor + AI + Cast Bridge (`sensorAndAiBridge`).
    final scale = (visorFps != null && visorFps < 45.0)
        ? 0.75
        : ((visorFps != null && visorFps < 54.0) ? 0.88 : 1.0);
    return VrTriDeviceExecutionPlan(
      mode: VrTriDeviceTopologyMode.sensorAiAndCastBridge,
      desktopTier: pcTier,
      pcRendersStereoFrame: false,
      pcHostsLocalAiAgents: false,
      offloadCastToPcMonitor: castToDesktopEnabled,
      offloadJoystickCvToPc: webcamAiConfident,
      offloadVisorSlamToPc: webcamAiConfident,
      substituteJoystickGyroWithPcVision: substituteGyro,
      targetVisorRefreshHz: visorMaxHz,
      targetJoystickHz: joyHz,
      recommendedVisorQualityScale: scale,
      summaryEs: substituteGyro
          ? 'Puente IA: PC suple giroscopio de Joystick + Cast en PC'
          : 'Puente Sensores/IA: Cast en PC + Visor descargado + Joy ${joyHz}Hz',
    );
  }
}
