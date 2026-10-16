import 'package:flutter/widgets.dart';
import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

import 'neom_vr_session_controller.dart';

typedef NeomVrSessionWidgetBuilder = Widget Function(
  BuildContext context,
  NeomVrSessionController controller,
  bool active,
);

/// Adds scoped SINT registration to vrlizate's renderer session host.
///
/// Each host registers a separate bridge under a unique tag. The core host owns
/// the session and handles route visibility, lifecycle and rendering; this
/// wrapper only borrows that session and owns its SINT registration.
class NeomVrSessionHost extends StatefulWidget {
  const NeomVrSessionHost({
    super.key,
    required this.adapter,
    required this.builder,
    this.onError,
    this.onCreated,
    this.onDisposed,
  });

  final VrSessionAdapter adapter;
  final NeomVrSessionWidgetBuilder builder;
  final void Function(Object error, StackTrace stack)? onError;
  final ValueChanged<NeomVrSessionController>? onCreated;
  final ValueChanged<NeomVrSessionController>? onDisposed;

  static NeomVrSessionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_NeomVrSessionScope>()
      ?.controller;

  static NeomVrSessionController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw FlutterError(
        'NeomVrSessionHost.of requires a NeomVrSessionHost ancestor.',
      );
    }
    return controller;
  }

  @override
  State<NeomVrSessionHost> createState() => _NeomVrSessionHostState();
}

class _NeomVrSessionHostState extends State<NeomVrSessionHost> {
  static int _nextId = 0;
  NeomVrSessionController? _controller;

  void _register(VrSessionController session) {
    String tag;
    do {
      tag = 'neom_vr.session.${_nextId++}';
    } while (Sint.isRegistered<NeomVrSessionController>(tag: tag));
    final controller = NeomVrSessionController(
      session: session,
      registrationTag: tag,
    );
    _controller = controller;
    Sint.put<NeomVrSessionController>(controller, tag: tag, permanent: true);
    widget.onCreated?.call(controller);
  }

  void _unregister(VrSessionController session) {
    final controller = _controller;
    if (controller == null || !identical(controller.session, session)) return;
    _controller = null;
    final tag = controller.registrationTag;
    if (Sint.isRegistered<NeomVrSessionController>(tag: tag) &&
        identical(Sint.find<NeomVrSessionController>(tag: tag), controller)) {
      Sint.delete<NeomVrSessionController>(tag: tag, force: true);
    } else {
      // External deletion/replacement must not let this host delete a newer
      // registration. Close only the bridge that this host originally created.
      controller.onDelete();
    }
    widget.onDisposed?.call(controller);
  }

  @override
  Widget build(BuildContext context) => VrSessionHost(
    adapter: widget.adapter,
    onError: widget.onError,
    onCreated: _register,
    onDisposed: _unregister,
    builder: (context, session, active) {
      final controller = _controller!;
      return _NeomVrSessionScope(
        controller: controller,
        child: Builder(
          builder: (context) => widget.builder(context, controller, active),
        ),
      );
    },
  );
}

class _NeomVrSessionScope extends InheritedWidget {
  const _NeomVrSessionScope({required this.controller, required super.child});

  final NeomVrSessionController controller;

  @override
  bool updateShouldNotify(_NeomVrSessionScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}
