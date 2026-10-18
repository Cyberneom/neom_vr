import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

/// Platform seam keeps native camera acquisition outside the renderer package.
abstract interface class VrSpatialTrackingPlatform {
  Future<Map<dynamic, dynamic>> availability();
  Future<bool> cameraPermission({required bool request});
  Stream<dynamic> get events;
  Future<Map<dynamic, dynamic>> start();
  Future<void> stop();
}

class AndroidVrSpatialTrackingPlatform implements VrSpatialTrackingPlatform {
  static const _methods = MethodChannel('vrlizate/spatial_tracking');
  static const _events = EventChannel('vrlizate/spatial_tracking/poses');

  @override
  Future<Map<dynamic, dynamic>> availability() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return {'supported': false, 'installed': false, 'reason': 'unsupported'};
    }
    return await _methods.invokeMapMethod('availability') ?? {};
  }

  @override
  Future<bool> cameraPermission({required bool request}) async {
    final status = request
        ? await Permission.camera.request()
        : await Permission.camera.status;
    return status.isGranted;
  }

  @override
  Stream<dynamic> get events => _events.receiveBroadcastStream();

  @override
  Future<Map<dynamic, dynamic>> start() async =>
      await _methods.invokeMapMethod('start') ?? {};

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}

/// Opt-in, foreground-only native pose source shared by visible scene leases.
/// No camera capture is started by constructing this object or enabling it on
/// the role selector. At least one visible scene must acquire a lease.
class VrSpatialTrackingService extends ChangeNotifier
    with WidgetsBindingObserver
    implements VrSpatialPoseSource {
  VrSpatialTrackingService({
    VrSpatialTrackingPlatform? platform,
    this.observeLifecycle = true,
    this.monotonicMicroseconds,
  }) : _platform = platform ?? AndroidVrSpatialTrackingPlatform() {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  final VrSpatialTrackingPlatform _platform;
  final bool observeLifecycle;
  final int Function()? monotonicMicroseconds;
  final _poses = StreamController<VrSpatialPose>.broadcast(sync: true);
  final _clock = Stopwatch()..start();
  int get _nowUs =>
      monotonicMicroseconds?.call() ?? _clock.elapsedMicroseconds;
  StreamSubscription<dynamic>? _events;
  Future<void> _operations = Future<void>.value();
  Timer? _watchdog;
  Timer? _save;
  bool _enabled = false;
  bool _foreground = true;
  bool _nativeRunning = false;
  bool _disposed = false;
  bool _enabling = false;
  int _enableRevision = 0;
  int _leases = 0;
  int _cameraSuspensions = 0;
  int _lastTimestamp = -1;
  int _lastPublishedTimestamp = -1;
  int _lastFrameTimestamp = -1;
  int _streamEpoch = 0;
  bool _streamRecoveryUsed = false;
  int _calibrationRevision = 0;
  int _lastReceiptUs = 0;
  String _reason = 'disabled';
  bool _tracking = false;
  vm.Vector3 _cameraToEye = vm.Vector3.zero();

  @override
  Stream<VrSpatialPose> get poses => _poses.stream;
  bool get enabled => _enabled;
  bool get enabling => _enabling;
  bool get tracking => _tracking;
  bool get hasVisibleScene => _leases > 0 && _foreground;
  String get reason => _reason;
  vm.Vector3 get cameraToEyeTranslation => _cameraToEye.clone();

  String get statusText {
    if (_enabling) return 'Comprobando cámara y compatibilidad…';
    if (_tracking) return '6DoF activo · movimiento físico de cabeza';
    return switch (_reason.toLowerCase()) {
      'disabled' => '3DoF · orientación y mando',
      'ready' ||
      'no_visible_scene' => 'Preparado · se activa al abrir el visor',
      'starting' ||
      'initializing' ||
      'none' => 'Buscando referencias del entorno…',
      'permission_denied' || 'camera_permission_required' =>
        'Se necesita permiso de cámara para medir posición',
      'unsupported' => 'Seguimiento espacial no disponible en este dispositivo',
      'arcore_not_installed' ||
      'arcore_update_required' ||
      'not_installed' => 'Instala o actualiza Servicios de Google Play para RA',
      'insufficient_light' => '3DoF · descubre la cámara y busca más luz',
      'insufficient_features' => '3DoF · apunta hacia un entorno con detalles',
      'excessive_motion' => '3DoF · mueve la cabeza más despacio',
      'background' || 'camera_in_use' => 'Seguimiento en pausa',
      'stale' => '3DoF · esperando datos de posición recientes',
      _ => '3DoF · posición física no disponible',
    };
  }

  /// The setting is session-local; opening the app never prompts for a camera.
  Future<bool> enable({bool requestPermission = true}) async {
    if (_disposed || _enabling) return false;
    final revision = ++_enableRevision;
    _enabling = true;
    notifyListeners();
    try {
      final support = await _platform.availability();
      if (_disposed || revision != _enableRevision) return false;
      if (support['supported'] != true || support['installed'] != true) {
        _setStatus(false, support['reason'] as String? ?? 'unsupported');
        return false;
      }
      final granted = await _platform.cameraPermission(
        request: requestPermission,
      );
      if (_disposed || revision != _enableRevision) return false;
      if (!granted) {
        _setStatus(false, 'permission_denied');
        return false;
      }
      _enabled = true;
      _streamRecoveryUsed = false;
      _setStatus(false, 'ready');
      await _reconcile();
      return true;
    } catch (error) {
      _setStatus(
        false,
        error is MissingPluginException ? 'unsupported' : 'unavailable',
      );
      return false;
    } finally {
      _enabling = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> disable() async {
    _enableRevision++;
    _enabled = false;
    _unavailable('disabled');
    await _reconcile();
  }

  @override
  Future<void> start() {
    if (_disposed) return Future<void>.value();
    _leases++;
    return _reconcile();
  }

  @override
  Future<void> stop() {
    if (_leases > 0) _leases--;
    return _reconcile();
  }

  /// Scanner routes await this before opening their own camera client.
  Future<void> suspendForCamera() {
    _cameraSuspensions++;
    return _reconcile();
  }

  Future<void> resumeAfterCamera() {
    if (_cameraSuspensions > 0) _cameraSuspensions--;
    return _reconcile();
  }

  bool get _shouldRun =>
      !_disposed &&
      _enabled &&
      _foreground &&
      _leases > 0 &&
      _cameraSuspensions == 0;

  Future<void> _reconcile() {
    _operations = _operations
        .then((_) async {
          if (_shouldRun && !_nativeRunning) {
            _lastFrameTimestamp = -1;
            _subscribeEvents();
            final epoch = _streamEpoch;
            _setStatus(false, 'starting');
            // Mark before awaiting: native frames may precede the method response.
            _nativeRunning = true;
            try {
              final response = await _platform.start();
              if (epoch != _streamEpoch) {
                // The old Activity's stream ended while start was pending.
                // Its queued cleanup owns stop; do not revive its watchdog.
              } else if (response['started'] != true) {
                _nativeRunning = false;
                await _cancelEvents();
                _unavailable(response['reason'] as String? ?? 'unavailable');
              } else {
                _lastReceiptUs = _nowUs;
                _watchdog ??= Timer.periodic(
                  const Duration(milliseconds: 250),
                  (_) {
                    if (_shouldRun &&
                        _nativeRunning &&
                        _tracking &&
                        _nowUs - _lastReceiptUs > 750000) {
                      _unavailable('stale');
                    }
                  },
                );
              }
            } catch (_) {
              _nativeRunning = false;
              await _cancelEvents();
              _unavailable('unavailable');
            }
          }
          // Recheck after awaiting start so a concurrent disable/pause wins.
          if (!_shouldRun) {
            _watchdog?.cancel();
            _watchdog = null;
            if (_nativeRunning) {
              _nativeRunning = false;
              try {
                await _platform.stop();
              } catch (_) {
                /* Already stopped natively. */
              }
            }
            _unavailable(
              !_enabled
                  ? 'disabled'
                  : !_foreground
                  ? 'background'
                  : _cameraSuspensions > 0
                  ? 'camera_in_use'
                  : 'no_visible_scene',
            );
          }
        })
        .catchError((Object _) {
          _nativeRunning = false;
          _watchdog?.cancel();
          _watchdog = null;
          _unavailable('unavailable');
        });
    return _operations;
  }

  void _subscribeEvents() {
    if (_events != null) return;
    final epoch = ++_streamEpoch;
    _events = _platform.events.listen(
      (event) {
        if (epoch == _streamEpoch) _onEvent(event);
      },
      onError: (Object _) => _endEventStream(epoch),
      onDone: () => _endEventStream(epoch, recover: true),
    );
  }

  Future<void> _cancelEvents() async {
    // EventChannel can remain open when its native listen handler is absent.
    // A failed start must not reuse that silent subscription on the next resume.
    _streamEpoch++;
    final subscription = _events;
    _events = null;
    await subscription?.cancel();
  }

  void _endEventStream(int epoch, {bool recover = false}) {
    if (_disposed || epoch != _streamEpoch) return;
    final restart = recover && _shouldRun && !_streamRecoveryUsed;
    if (restart) _streamRecoveryUsed = true;
    _streamEpoch++;
    final subscription = _events;
    _events = null;
    _nativeRunning = false;
    _watchdog?.cancel();
    _watchdog = null;
    _unavailable('unavailable');
    // Keep stop ordered after any pending start and before the next retry.
    _operations = _operations.then((_) async {
      await subscription?.cancel();
      try {
        await _platform.stop();
      } catch (_) {
        /* Native stream already ended. */
      }
    });
    // A retained engine may already have its replacement Activity attached.
    // Try once after cleanup. Repeated endings/errors cannot spin retries;
    // another valid pose, explicit enable, or lifecycle resume rearms recovery.
    if (restart) unawaited(_reconcile());
  }

  int _publicationTimestamp() {
    _lastPublishedTimestamp = _lastTimestamp > _lastPublishedTimestamp
        ? _lastTimestamp
        : _lastPublishedTimestamp + 1;
    return _lastPublishedTimestamp;
  }

  void _onEvent(dynamic raw) {
    if (!_shouldRun || !_nativeRunning || raw is! Map) return;
    final timestamp = raw['timestampNs'];
    if (timestamp is! int || timestamp <= _lastTimestamp) return;
    _lastTimestamp = timestamp;
    final state = raw['state'];
    if (state != 'tracking') {
      _lastReceiptUs = _nowUs;
      if (state == 'stopped' || state == 'error') {
        _nativeRunning = false;
        _watchdog?.cancel();
        _watchdog = null;
      }
      _unavailable(raw['reason'] as String? ?? 'unavailable');
      return;
    }
    final frame = raw['frameTimestampNs'];
    if (frame is! int || frame <= _lastFrameTimestamp) return;
    final p = _finiteValues(raw['position'], 3);
    final q = _finiteValues(raw['orientation'], 4);
    if (p == null || q == null) {
      _unavailable('invalid_pose');
      return;
    }
    final orientation = vm.Quaternion(q[0], q[1], q[2], q[3]);
    if (orientation.length2 < 1e-12) {
      _unavailable('invalid_pose');
      return;
    }
    orientation.normalize();
    _lastFrameTimestamp = frame;
    _lastReceiptUs = _nowUs;
    _streamRecoveryUsed = false;
    _setStatus(true, 'tracking');
    _poses.add(
      VrSpatialPose.tracking(
        position: vm.Vector3(p[0], p[1], p[2]),
        orientation: orientation,
        timestampNanos: _publicationTimestamp(),
      ),
    );
  }

  static List<double>? _finiteValues(dynamic raw, int length) {
    if (raw is! List ||
        raw.length != length ||
        raw.any((v) => v is! num || !v.isFinite)) {
      return null;
    }
    return raw.cast<num>().map((v) => v.toDouble()).toList();
  }

  void _unavailable(String reason) {
    if (_disposed) return;
    _setStatus(false, reason);
    _poses.add(
      VrSpatialPose.unavailable(
        state: VrSpatialTrackingState.paused,
        timestampNanos: _publicationTimestamp(),
        reason: reason,
      ),
    );
  }

  void _setStatus(bool tracking, String reason) {
    if (_disposed || (_tracking == tracking && _reason == reason)) return;
    _tracking = tracking;
    _reason = reason;
    if (const bool.fromEnvironment('VRLIZATE_SPATIAL_LOG')) {
      debugPrint(
        'VR_SPATIAL source tracking=$tracking reason=$reason leases=$_leases',
      );
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_foreground && state == AppLifecycleState.resumed) {
      _streamRecoveryUsed = false;
    }
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _unavailable('background');
    unawaited(_reconcile());
  }

  Future<void> loadCalibration() async {
    final revision = _calibrationRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList('vrlizate_camera_to_eye_m_v1');
      if (_disposed ||
          revision != _calibrationRevision ||
          values == null ||
          values.length != 3) {
        return;
      }
      final parsed = values.map(double.tryParse).toList();
      if (parsed.any((v) => v == null || !v.isFinite || v.abs() > 0.2)) return;
      _cameraToEye = vm.Vector3(parsed[0]!, parsed[1]!, parsed[2]!);
      notifyListeners();
    } catch (_) {
      /* Use the explicitly uncalibrated zero offset. */
    }
  }

  void setCameraToEyeTranslation(vm.Vector3 value) {
    if ([value.x, value.y, value.z].any((v) => !v.isFinite || v.abs() > 0.2)) {
      throw ArgumentError(
        'Camera-to-eye translation must be finite within ±0.2 m.',
      );
    }
    _calibrationRevision++;
    _cameraToEye = value.clone();
    notifyListeners();
    _save?.cancel();
    final encoded = [
      value.x,
      value.y,
      value.z,
    ].map((v) => v.toString()).toList();
    _save = Timer(const Duration(milliseconds: 250), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('vrlizate_camera_to_eye_m_v1', encoded);
      } catch (_) {
        /* The current session still uses the selected offset. */
      }
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _enableRevision++;
    _save?.cancel();
    _watchdog?.cancel();
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _reconcile().whenComplete(() async {
        await _events?.cancel();
        await _poses.close();
      }),
    );
    super.dispose();
  }
}

class VrSpatialSettingsScope
    extends InheritedNotifier<VrSpatialTrackingService> {
  const VrSpatialSettingsScope({
    super.key,
    required VrSpatialTrackingService service,
    required super.child,
  }) : super(notifier: service);
  static VrSpatialTrackingService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<VrSpatialSettingsScope>()
      ?.notifier;
}

/// Prevents a scanner from racing the asynchronous ARCore camera shutdown.
class VrSpatialCameraPause extends StatefulWidget {
  const VrSpatialCameraPause({super.key, required this.child});
  final Widget child;

  @override
  State<VrSpatialCameraPause> createState() => _VrSpatialCameraPauseState();
}

class _VrSpatialCameraPauseState extends State<VrSpatialCameraPause> {
  VrSpatialTrackingService? _service;
  bool _ready = false;
  int _revision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = VrSpatialSettingsScope.maybeOf(context);
    if (service == null) {
      _ready = true;
      return;
    }
    if (identical(service, _service)) return;
    unawaited(_service?.resumeAfterCamera());
    _service = service;
    _ready = false;
    final revision = ++_revision;
    unawaited(
      service.suspendForCamera().then((_) {
        if (mounted && revision == _revision) setState(() => _ready = true);
      }),
    );
  }

  @override
  void dispose() {
    _revision++;
    unawaited(_service?.resumeAfterCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const Center(child: Text('Preparando cámara…'));
}
