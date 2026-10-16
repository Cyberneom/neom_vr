import 'dart:async';

import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

/// SINT bridge for one borrowed renderer session.
///
/// Registration observes state but never starts rendering. SINT deletion closes
/// the session; its owner remains responsible for [VrSessionController.dispose].
/// Hosts create this bridge around their existing core controller, so the
/// renderer state machine and resource ownership have a single implementation.
class NeomVrSessionController extends SintController {
  NeomVrSessionController({required this.session, this.registrationTag})
    : status = session.status.value.obs;

  final VrSessionController session;

  /// The unique SINT tag assigned by NeomVrSessionHost, if hosted.
  final String? registrationTag;
  final Rx<VrSessionStatus> status;
  bool _listening = false;
  bool _didClose = false;

  VrSessionAdapter get adapter => session.adapter;
  String get rendererId => session.rendererId;
  Object? get lastError => session.lastError;
  StackTrace? get lastStackTrace => session.lastStackTrace;

  @override
  bool get isClosed => _didClose || session.isClosed || super.isClosed;

  @override
  void onInit() {
    if (_listening || _didClose) return;
    super.onInit();
    session.status.addListener(_synchronizeStatus);
    _listening = true;
    _synchronizeStatus();
  }

  void _synchronizeStatus() => status.value = session.status.value;

  Future<void> start() => session.start();
  Future<void> pause() => session.pause();
  Future<void> resume() => session.resume();
  Future<void> closeSession() => session.closeSession();

  @override
  void onClose() {
    if (_didClose) return;
    _didClose = true;
    if (_listening) {
      session.status.removeListener(_synchronizeStatus);
      _listening = false;
    }
    final closing = session.closeSession();
    _synchronizeStatus();
    // SINT deletion is synchronous. Keep cleanup errors on the borrowed core
    // controller and handle the Future here to prevent unhandled exceptions.
    unawaited(
      closing.then<void>(
        (_) => _finishClose(),
        onError: (Object _, StackTrace __) => _finishClose(),
      ),
    );
    super.onClose();
  }

  void _finishClose() {
    _synchronizeStatus();
    status.close();
  }
}
