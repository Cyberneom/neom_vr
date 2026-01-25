// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:neom_commons/ui/theme/app_color.dart';
// import 'package:neom_commons/ui/widgets/appbar_child.dart';
// import 'package:neom_commons/utils/constants/translations/app_translation_constants.dart';
// import 'package:video_360/video_360.dart';
//
// import '../../utils/constants/vr_constants.dart';
// import '../../utils/constants/vr_translation_constants.dart';
// import 'neom_360_viewer_controller.dart';
//
// ///TOTALLY EXPERIMENTAL YET - JUST PLAYING AS VR MUST BE EVEN FOR SMARTPHONE VR USERS
// class Neom360ViewerPage extends StatelessWidget {
//   const Neom360ViewerPage({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//
//     var width = MediaQuery.of(context).size.width;
//     var height = MediaQuery.of(context).size.height;
//
//     return GetBuilder<Neom360ViewerController>(
//         builder: (controller) => Scaffold(
//       appBar: AppBarChild(title: VrTranslationConstants.viewerTitle.tr),
//       body: Stack(
//         children: [
//           Center(
//             child: SizedBox(
//               width: width,
//               height: height,
//               child: Video360View(
//                 onVideo360ViewCreated: controller.onVideo360ViewCreated,
//                 url: VrConstants.vrVideoUrl,
//                 onPlayInfo: (Video360PlayInfo info) {
//                   controller.setPlayInfoValue(info);
//                 },
//               ),
//             ),
//           ),
//           Column(
//             children: [
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                 children: [
//                   MaterialButton(
//                     onPressed: () {
//                       controller.controller.play();
//                     },
//                     color: AppColor.darkViolet,
//                     child: Text(AppTranslationConstants.toPlay.tr),
//                   ),
//                   MaterialButton(
//                     onPressed: () {
//                       controller.controller.stop();
//                     },
//                     color: AppColor.darkViolet,
//                     child: Text(AppTranslationConstants.toStop.tr),
//                   ),
//                   MaterialButton(
//                     onPressed: () {
//                       controller.controller.reset();
//                     },
//                     color: AppColor.darkViolet,
//                     child: Text(AppTranslationConstants.reset.tr),
//                   ),
//                   MaterialButton(
//                     onPressed: () {
//                       controller.controller.jumpTo(80000);
//                     },
//                     color: AppColor.darkViolet,
//                     child: Text('1:20'),
//                   ),
//                 ],
//               ),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                 children: [
//                   MaterialButton(
//                     onPressed: () {
//                       controller.controller.seekTo(-2000);
//                     },
//                     color: AppColor.darkViolet,
//                     child: Text('<<'),
//                   ),
//                   MaterialButton(
//                     onPressed: () {
//                       controller.controller.seekTo(2000);
//                     },
//                     color: AppColor.darkViolet,
//                     child: Text('>>'),
//                   ),
//                   Flexible(
//                     child: MaterialButton(
//                       onPressed: () {},
//                       color: AppColor.darkViolet,
//                       child: Text('${controller.durationText} / ${controller.totalText.value}'),
//                     ),
//                   ),
//                 ],
//               )
//             ],
//           )
//         ],
//       ),),
//     );
//   }
//
// }
