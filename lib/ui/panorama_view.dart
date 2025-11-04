import 'package:flutter/material.dart';
import 'package:neom_core/app_config.dart';
import 'package:panorama/panorama.dart';
import 'package:split_view/split_view.dart';

import '../utils/constants/vr_constants.dart';

///TOTALLY EXPERIMENTAL YET - JUST PLAYING AS VR MUST BE EVEN FOR SMARTPHONE VR USERS
class PanoramaView extends StatelessWidget {
  const PanoramaView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
      child:
      SplitView(
        viewMode: SplitViewMode.Vertical,
        activeIndicator: SplitIndicator(
          viewMode: SplitViewMode.Vertical,
          isActive: true,
        ),
        onWeightChanged: (w) => AppConfig.logger.d("Horizon: $w"),
        controller: SplitViewController(limits: [null, WeightLimit(max: 0.5)]),
        children: [
          Panorama(
            child: Image.network(VrConstants.panoramaImageUrl1),
          ),
          Panorama(
            child: Image.network(VrConstants.panoramaImageUrl2),
          ),
        ],
      ),
      ),
    );
  }
}
