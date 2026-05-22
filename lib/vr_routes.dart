import 'package:neom_core/ui/deferred_loader.dart';
import 'package:neom_core/utils/constants/app_route_constants.dart';
import 'package:sint/sint.dart';

import 'ui/spatial/neom_spatial_360_fullscreen_page.dart' deferred as spatial;
import 'ui/vr_stereo/neom_vr360_stereo_page.dart' deferred as vrStereo;

class VrRoutes {

  static final List<SintPage<dynamic>> routes = [
    SintPage(
        name: AppRouteConstants.vr360StereoFullscreen,
        page: () => DeferredLoader(vrStereo.loadLibrary, () => vrStereo.NeomVR360StereoPage()),
        transition: Transition.fadeIn
    ),
    SintPage(
        name: AppRouteConstants.spatial360Fullscreen,
        page: () => DeferredLoader(spatial.loadLibrary, () => spatial.NeomSpatial360FullscreenPage()),
        transition: Transition.fadeIn
    ),
  ];

}
