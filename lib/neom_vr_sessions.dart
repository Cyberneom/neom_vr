/// Optional SINT integration for the renderer lifecycle owned by vrlizate.
///
/// This entrypoint avoids importing Open Neom's application-specific pages.
/// The package still declares its Open Neom dependencies in pubspec.yaml.
library;

export 'package:vrlizate/vrlizate.dart'
    show
        VREngineSessionAdapter,
        VrCallbackSessionAdapter,
        VrSessionAdapter,
        VrSessionCallback,
        VrSessionController,
        VrSessionHost,
        VrSessionStatus,
        VrSessionWidgetBuilder,
        VrWidgetSessionAdapter;

export 'beacon/vr_beacon_dead_reckoning.dart';
export 'beacon/vr_beacon_joystick_link.dart';
export 'beacon/vr_desktop_autonomous_bridge.dart';
export 'beacon/vr_desktop_beacon_client.dart';
export 'beacon/vr_desktop_beacon_models.dart';
export 'beacon/vr_desktop_beacon_page.dart';
export 'beacon/vr_desktop_beacon_station.dart';
export 'beacon/vr_desktop_beacon_wire.dart';
export 'beacon/vr_desktop_capabilities.dart';
export 'beacon/vr_desktop_media_vault.dart';
export 'beacon/vr_desktop_vision_platform.dart';
export 'beacon/vr_fiducial_tag_codec.dart';
export 'beacon/vr_private_lan_loopback_relay.dart';
export 'beacon/vr_tri_node_depth_solver.dart';
export 'injection/vr_bindings.dart';
export 'navigation/vr_navigator.dart';
export 'navigation/vr_routes.dart';
export 'session/neom_vr_session_controller.dart';
export 'session/neom_vr_session_host.dart';
export 'session/vr_device_profiler.dart';
export 'session/vr_joystick_mini_frame_painter.dart';
export 'session/vr_passthrough_camera_feed.dart';
export 'session/vr_spatial_tracking_service.dart';
export 'session/vr_spatial_tracking_settings.dart';
export 'session/vr_stereo_spatial_inspector_hud.dart';
export 'session/vr_tri_camera_frustum_painter.dart';
export 'session/vr_tri_camera_live_inspector_card.dart';
export 'session/vr_visual_marker_pose.dart';
export 'session/vr_visual_tracking_session.dart';
export 'state/vr_controller.dart';
export 'state/vr_scene_state.dart';
export 'translation/vr_translations.dart';
