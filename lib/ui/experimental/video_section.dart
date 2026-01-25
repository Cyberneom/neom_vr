// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
// import 'package:neom_core/app_config.dart';
// import 'package:split_view/split_view.dart';
// import 'package:video_360/video_360.dart';
//
// import '../../utils/constants/vr_constants.dart';
// import 'neom_360_viewer_controller.dart';
//
// ///TOTALLY EXPERIMENTAL YET - JUST PLAYING AS VR MUST BE EVEN FOR SMARTPHONE VR USERS
// class VideoSection extends StatelessWidget {
//   const VideoSection({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return GetBuilder<Neom360ViewerController>(
//       id: AppPageIdConstants.viewer360,
//       init: Neom360ViewerController(),
//     builder: (controller) => Scaffold(
//       body: Center(
//         child: SplitView(
//               viewMode: SplitViewMode.Vertical,
//               children: [
//                 Video360View(
//                   onVideo360ViewCreated: controller.onVideo360ViewCreated,
//                   url: VrConstants.vrVideoUrl2,
//                   onPlayInfo: (Video360PlayInfo info) {
//                     controller.durationText.value = info.duration.toString();
//                     controller.totalText.value = info.total.toString();
//                   },
//                 ),
//                 Video360View(
//                   onVideo360ViewCreated: controller.onVideo360ViewCreated,
//                   url: VrConstants.vrVideoUrl2,
//                   onPlayInfo: (Video360PlayInfo info) {
//                     controller.durationText.value = info.duration.toString();
//                     controller.totalText.value = info.total.toString();
//                   },
//                 ),
//               ],
//               onWeightChanged: (w) => AppConfig.logger.d("Horizon: $w"),
//               // controller: SplitViewController(limits: [null, WeightLimit(max: 0.5)]),
//             ),
//         ),
//       ),
//     );
//   }
//
// }
