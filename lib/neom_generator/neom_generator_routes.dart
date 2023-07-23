import 'package:get/get.dart';
import 'package:neom_commons/core/utils/constants/app_route_constants.dart';
import 'package:neom_generator/neom_generator/neom_generator_page.dart';

class NeomGeneratorRoutes {

  static final List<GetPage<dynamic>> routes = [
    GetPage(
        name: AppRouteConstants.generator,
        page: () => NeomGeneratorPage(),
        transition: Transition.zoom
    ),
  ];

}
