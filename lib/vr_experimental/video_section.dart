import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_core/core/app_config.dart';
import 'package:split_view/split_view.dart';
import 'package:video_360/video_360.dart';

import 'neom_360_viewer_controller.dart';


class VideoSection extends StatelessWidget {
  const VideoSection({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<Neom360ViewerController>(
      id: AppPageIdConstants.viewer360,
      init: Neom360ViewerController(),
    builder: (_) => Scaffold(
      body: Center(
        child: SplitView(
              viewMode: SplitViewMode.Vertical,
              children: [
                Video360View(
                  onVideo360ViewCreated: _.onVideo360ViewCreated,
                  url: "https://github.com/stephangopaul/video_samples/blob/master/gb.mp4?raw=true",
                  onPlayInfo: (Video360PlayInfo info) {
                    _.durationText.value = info.duration.toString();
                    _.totalText.value = info.total.toString();
                  },
                ),
                Video360View(
                  onVideo360ViewCreated: _.onVideo360ViewCreated,
                  url: "https://github.com/stephangopaul/video_samples/blob/master/gb.mp4?raw=true",
                  onPlayInfo: (Video360PlayInfo info) {
                    _.durationText.value = info.duration.toString();
                    _.totalText.value = info.total.toString();
                  },
                ),
              ],
              onWeightChanged: (w) => AppConfig.logger.d("Horizon: $w"),
              // controller: SplitViewController(limits: [null, WeightLimit(max: 0.5)]),
            ),
        ),
      ),
    );
  }

}
