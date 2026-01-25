import 'package:get/get.dart';
import 'package:neom_core/utils/constants/app_route_constants.dart';

import 'ui/neom_vr360_stereo_page.dart';
import 'ui/spatial/neom_spatial_360_fullscreen_page.dart';
import 'ui/vr_stereo/neom_vr360_stereo_page.dart';

class VrRoutes {

  static final List<GetPage<dynamic>> routes = [
    GetPage(
        name: AppRouteConstants.vr360StereoFullscreen,
        page: () => const NeomVR360StereoPage(),
        transition: Transition.fadeIn
    ),
    GetPage(
        name: AppRouteConstants.spatial360Fullscreen,
        page: () => const NeomSpatial360FullscreenPage(),
        transition: Transition.fadeIn
    ),
  ];

}
