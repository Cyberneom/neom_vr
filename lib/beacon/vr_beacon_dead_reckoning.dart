import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'vr_desktop_beacon_models.dart';

/// Shared kinematic Dead-Reckoning predictor & Kalman-innovation transmission
/// gate for **Estación Faro (`PC ↔ Visor`)** `VRB1` spatial state streams.
///
/// Both sender (`VrDesktopBeaconStation`) and receiver (`VrDesktopBeaconClient`)
/// run the identical damped first-order kinematic model:
///
/// $$\hat{\mathbf{p}}(t) = \mathbf{p}_0 + \mathbf{v}_0 \tau \left(1 - e^{-\Delta t / \tau}\right)$$
///
/// - **Sender side (`shouldTransmit`):** suppresses redundant `140 B` `62.5 Hz`
///   UDP broadcasts whenever the newly solved 3-node pose lies within sub-2mm
///   innovation tolerance of what the Visor is already predicting locally,
///   dropping idle/smooth Wi-Fi packet rate down to a `6.25 Hz` (`160 ms`)
///   anti-drift heartbeat while preserving `0 ms` immediate transmission on
///   sudden motion, pinch, or gesture transitions.
/// - **Receiver side (`ingestReceived` + `predictAt`):** reconstructs smooth
///   `120 Hz` head and 3D hand trajectories between `12–20 Hz` webcam frames
///   without overshoot if a packet is delayed.
class VrBeaconDeadReckoningGate {
  VrBeaconDeadReckoningGate({
    this.dampingTauSeconds = 0.12,
    this.maxExtrapolationSeconds = 0.20,
    this.headInnovationThresholdMeters = 0.0015,
    this.handInnovationThresholdMeters = 0.0025,
    this.joystickInnovationThresholdMeters = 0.0040,
    this.angleInnovationThresholdRad = 0.0040,
    this.pinchInnovationThreshold = 0.030,
    this.maxHeartbeatIntervalMicros = 160000,
  });

  /// Exponential velocity damping time constant $\tau$ (`seconds`).
  final double dampingTauSeconds;

  /// Hard cap on forward extrapolation horizon (`seconds`).
  final double maxExtrapolationSeconds;

  /// Head 3D position innovation threshold (`1.5 mm` default).
  final double headInnovationThresholdMeters;

  /// Hand 3D head-relative position innovation threshold (`2.5 mm` default).
  final double handInnovationThresholdMeters;

  /// Joystick 3D room position innovation threshold (`4.0 mm` default).
  final double joystickInnovationThresholdMeters;

  /// Azimuth / yaw-anchor innovation threshold (`~0.23°` default).
  final double angleInnovationThresholdRad;

  /// Analog pinch strength innovation threshold (`3%` default).
  final double pinchInnovationThreshold;

  /// Maximum silence interval (`160 ms` = `6.25 Hz` default) before forcing a
  /// state sync packet even when innovation is zero.
  final int maxHeartbeatIntervalMicros;

  // Sender tracking state
  VrTriNodeDepthSolution? _lastTransmitted;
  int _lastTransmittedUs = -10000000;
  final vm.Vector3 _lastTransmittedHeadVel = vm.Vector3.zero();

  VrTriNodeDepthSolution? _prevCandidate;
  int _prevCandidateUs = -10000000;
  final vm.Vector3 _smoothedCandidateHeadVel = vm.Vector3.zero();

  int _evaluatedCount = 0;
  int _transmittedCount = 0;
  int _suppressedCount = 0;

  // Receiver tracking state
  VrTriNodeDepthSolution? _latestReceived;
  int _latestReceivedUs = -10000000;
  final vm.Vector3 _receivedHeadVel = vm.Vector3.zero();

  int get evaluatedCount => _evaluatedCount;
  int get transmittedCount => _transmittedCount;
  int get suppressedCount => _suppressedCount;

  /// Fraction (`0.0 .. 1.0`) of `62.5 Hz` solver ticks suppressed on the wire
  /// because local Dead-Reckoning already predicted them within tolerance.
  double get suppressionRatio =>
      _evaluatedCount == 0 ? 0.0 : _suppressedCount / _evaluatedCount;

  void reset() {
    _lastTransmitted = null;
    _lastTransmittedUs = -10000000;
    _lastTransmittedHeadVel.setZero();
    _prevCandidate = null;
    _prevCandidateUs = -10000000;
    _smoothedCandidateHeadVel.setZero();
    _evaluatedCount = 0;
    _transmittedCount = 0;
    _suppressedCount = 0;
    _latestReceived = null;
    _latestReceivedUs = -10000000;
    _receivedHeadVel.setZero();
  }

  double _effectiveDt(double rawDtSeconds) {
    if (!rawDtSeconds.isFinite || rawDtSeconds <= 0.0) return 0.0;
    final clamped = rawDtSeconds.clamp(0.0, maxExtrapolationSeconds);
    if (dampingTauSeconds <= 1e-4) return clamped;
    return dampingTauSeconds * (1.0 - math.exp(-clamped / dampingTauSeconds));
  }

  double _velocityDecay(double rawDtSeconds) {
    if (!rawDtSeconds.isFinite || rawDtSeconds <= 0.0) return 1.0;
    final clamped = rawDtSeconds.clamp(0.0, maxExtrapolationSeconds);
    if (dampingTauSeconds <= 1e-4) return 0.0;
    return math.exp(-clamped / dampingTauSeconds);
  }

  vm.Vector3 _extrapolatePos(
    vm.Vector3 origin,
    vm.Vector3 velocity,
    double effDt,
  ) => vm.Vector3(
    origin.x + velocity.x * effDt,
    origin.y + velocity.y * effDt,
    origin.z + velocity.z * effDt,
  );

  /// Evaluates whether [candidate] carries non-predictable innovation relative
  /// to the Visor's local Dead-Reckoning state, updating transmission counters.
  bool shouldTransmit(
    VrTriNodeDepthSolution candidate, {
    required int nowMicros,
  }) {
    _evaluatedCount++;

    // Update continuous head velocity estimate on the station
    final prevCand = _prevCandidate;
    if (prevCand != null && nowMicros > _prevCandidateUs) {
      final dt = (nowMicros - _prevCandidateUs) * 1e-6;
      if (dt >= 0.004 && dt <= 0.25) {
        final cPos = candidate.visorRoomPosition;
        final pPos = prevCand.visorRoomPosition;
        final vx = ((cPos.x - pPos.x) / dt).clamp(-4.0, 4.0);
        final vy = ((cPos.y - pPos.y) / dt).clamp(-3.0, 3.0);
        final vz = ((cPos.z - pPos.z) / dt).clamp(-4.0, 4.0);
        const alpha = 0.35;
        _smoothedCandidateHeadVel.setValues(
          _smoothedCandidateHeadVel.x +
              (vx - _smoothedCandidateHeadVel.x) * alpha,
          _smoothedCandidateHeadVel.y +
              (vy - _smoothedCandidateHeadVel.y) * alpha,
          _smoothedCandidateHeadVel.z +
              (vz - _smoothedCandidateHeadVel.z) * alpha,
        );
      }
    }
    _prevCandidate = candidate;
    _prevCandidateUs = nowMicros;

    final last = _lastTransmitted;
    if (last == null) {
      return _commitTransmit(candidate, nowMicros);
    }

    final elapsedUs = nowMicros - _lastTransmittedUs;
    if (elapsedUs < 0 || elapsedUs >= maxHeartbeatIntervalMicros) {
      return _commitTransmit(candidate, nowMicros);
    }

    // Immediate 0-latency pass-through on discrete semantic/modality changes
    final candLeftTracked = candidate.leftHandConfidence >= 0.25;
    final lastLeftTracked = last.leftHandConfidence >= 0.25;
    final candRightTracked = candidate.rightHandConfidence >= 0.25;
    final lastRightTracked = last.rightHandConfidence >= 0.25;
    if (candidate.gesture != last.gesture ||
        candidate.facialExpression != last.facialExpression ||
        candidate.leftHandRaised != last.leftHandRaised ||
        candidate.rightHandRaised != last.rightHandRaised ||
        candidate.visorFiducialLocked != last.visorFiducialLocked ||
        candidate.joystickFiducialLocked != last.joystickFiducialLocked ||
        candidate.activeModalitiesMask != last.activeModalitiesMask ||
        candLeftTracked != lastLeftTracked ||
        candRightTracked != lastRightTracked ||
        (candidate.estimatedUserIpdMeters != null) !=
            (last.estimatedUserIpdMeters != null)) {
      return _commitTransmit(candidate, nowMicros);
    }

    // Analog scalar innovations
    if ((candidate.leftPinchStrength - last.leftPinchStrength).abs() >=
            pinchInnovationThreshold ||
        (candidate.rightPinchStrength - last.rightPinchStrength).abs() >=
            pinchInnovationThreshold ||
        (candidate.visorAzimuthRadians - last.visorAzimuthRadians).abs() >=
            angleInnovationThresholdRad ||
        (candidate.yawAnchorCorrectionRadians -
                    last.yawAnchorCorrectionRadians)
                .abs() >=
            angleInnovationThresholdRad) {
      return _commitTransmit(candidate, nowMicros);
    }

    // 3D kinematic innovation gate against receiver's damped prediction
    final dtSec = elapsedUs * 1e-6;
    final effDt = _effectiveDt(dtSec);

    final predHead = _extrapolatePos(
      last.visorRoomPosition,
      _lastTransmittedHeadVel,
      effDt,
    );
    if ((candidate.visorRoomPosition - predHead).length2 >=
        headInnovationThresholdMeters * headInnovationThresholdMeters) {
      return _commitTransmit(candidate, nowMicros);
    }

    if (candLeftTracked) {
      final predLeft = _extrapolatePos(
        last.leftHandRelHead,
        last.leftHandVelocity,
        effDt,
      );
      if ((candidate.leftHandRelHead - predLeft).length2 >=
          handInnovationThresholdMeters * handInnovationThresholdMeters) {
        return _commitTransmit(candidate, nowMicros);
      }
    }

    if (candRightTracked) {
      final predRight = _extrapolatePos(
        last.rightHandRelHead,
        last.rightHandVelocity,
        effDt,
      );
      if ((candidate.rightHandRelHead - predRight).length2 >=
          handInnovationThresholdMeters * handInnovationThresholdMeters) {
        return _commitTransmit(candidate, nowMicros);
      }
    }

    if ((candidate.joystickRoomPosition - last.joystickRoomPosition).length2 >=
        joystickInnovationThresholdMeters *
            joystickInnovationThresholdMeters) {
      return _commitTransmit(candidate, nowMicros);
    }

    _suppressedCount++;
    return false;
  }

  bool _commitTransmit(VrTriNodeDepthSolution candidate, int nowMicros) {
    _lastTransmitted = candidate;
    _lastTransmittedUs = nowMicros;
    _lastTransmittedHeadVel.setFrom(_smoothedCandidateHeadVel);
    _transmittedCount++;
    return true;
  }

  /// Registers a newly received [solution] on the Visor (`VrDesktopBeaconClient`).
  void ingestReceived(
    VrTriNodeDepthSolution solution, {
    required int receivedAtMicros,
  }) {
    final prev = _latestReceived;
    if (prev != null) {
      final dtSender = (solution.timestampMicros - prev.timestampMicros) * 1e-6;
      final dtWall = (receivedAtMicros - _latestReceivedUs) * 1e-6;
      final dt = (dtSender > 0.004 && dtSender <= 0.50) ? dtSender : dtWall;
      if (dt > 0.004 && dt <= 0.50) {
        final curPos = solution.visorRoomPosition;
        final prevPos = prev.visorRoomPosition;
        final vx = ((curPos.x - prevPos.x) / dt).clamp(-4.0, 4.0);
        final vy = ((curPos.y - prevPos.y) / dt).clamp(-3.0, 3.0);
        final vz = ((curPos.z - prevPos.z) / dt).clamp(-4.0, 4.0);
        const alpha = 0.45;
        _receivedHeadVel.setValues(
          _receivedHeadVel.x + (vx - _receivedHeadVel.x) * alpha,
          _receivedHeadVel.y + (vy - _receivedHeadVel.y) * alpha,
          _receivedHeadVel.z + (vz - _receivedHeadVel.z) * alpha,
        );
      } else {
        _receivedHeadVel.setZero();
      }
    } else {
      _receivedHeadVel.setZero();
    }
    _latestReceived = solution;
    _latestReceivedUs = receivedAtMicros;
  }

  /// Extrapolates the latest received [VrTriNodeDepthSolution] smoothly to
  /// [nowMicros] (`120 Hz` Visor render loop).
  VrTriNodeDepthSolution? predictAt(int nowMicros) {
    final base = _latestReceived;
    if (base == null) return null;
    final dtSec = (nowMicros - _latestReceivedUs) * 1e-6;
    if (!dtSec.isFinite || dtSec <= 0.0005) {
      return base;
    }
    final effDt = _effectiveDt(dtSec);
    final decay = _velocityDecay(dtSec);
    final baseLv = base.leftHandVelocity;
    final baseRv = base.rightHandVelocity;
    return VrTriNodeDepthSolution(
      timestampMicros: base.timestampMicros + (dtSec * 1e6).round(),
      sequence: base.sequence,
      computerToVisorMeters: base.computerToVisorMeters,
      computerToJoystickMeters: base.computerToJoystickMeters,
      visorToJoystickMeters: base.visorToJoystickMeters,
      visorRoomPosition: _extrapolatePos(
        base.visorRoomPosition,
        _receivedHeadVel,
        effDt,
      ),
      joystickRoomPosition: base.joystickRoomPosition,
      deskClearanceMeters: base.deskClearanceMeters,
      visorAzimuthRadians: base.visorAzimuthRadians,
      yawAnchorCorrectionRadians: base.yawAnchorCorrectionRadians,
      leftHandRelHead: base.leftHandConfidence >= 0.25
          ? _extrapolatePos(base.leftHandRelHead, baseLv, effDt)
          : base.leftHandRelHead,
      rightHandRelHead: base.rightHandConfidence >= 0.25
          ? _extrapolatePos(base.rightHandRelHead, baseRv, effDt)
          : base.rightHandRelHead,
      leftHandVelocity: baseLv * decay,
      rightHandVelocity: baseRv * decay,
      leftHandConfidence: base.leftHandConfidence,
      rightHandConfidence: base.rightHandConfidence,
      leftHandRaised: base.leftHandRaised,
      rightHandRaised: base.rightHandRaised,
      leftPinchStrength: base.leftPinchStrength,
      rightPinchStrength: base.rightPinchStrength,
      gesture: base.gesture,
      confidence: base.confidence,
      activeModalitiesMask: base.activeModalitiesMask,
      visorFiducialLocked: base.visorFiducialLocked,
      joystickFiducialLocked: base.joystickFiducialLocked,
      visorFiducialReprojectionRmsPx: base.visorFiducialReprojectionRmsPx,
      estimatedUserIpdMeters: base.estimatedUserIpdMeters,
      facialExpression: base.facialExpression,
      facialConfidence: base.facialConfidence,
    );
  }
}
