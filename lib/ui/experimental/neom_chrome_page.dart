// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:neom_commons/utils/constants/translations/app_translation_constants.dart';
//
// import '../../utils/constants/vr_translation_constants.dart';
// import 'neom_360_viewer_controller.dart';
//
// ///TOTALLY EXPERIMENTAL YET - JUST PLAYING AS VR MUST BE EVEN FOR SMARTPHONE VR USERS
// class NeomChromePage extends StatelessWidget {
//   const NeomChromePage({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return GetBuilder<Neom360ViewerController>(
//         builder: (controller) => Scaffold(
//         body: Container(
//           color: Colors.blue,
//           child: Column(
//               mainAxisSize: MainAxisSize.max,
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: <Widget>[
//               Row(),
//           Text(VrTranslationConstants.chromeVrTitle,
//           style: TextStyle(
//           fontSize: 60,
//           color: Colors.white,
//           fontWeight: FontWeight.bold
//           ),
//         ),
//         SizedBox(height: 20),
//         TextButton(
//           child: Padding(
//             padding: const EdgeInsets.all(10),
//             child: Text(AppTranslationConstants.enter.tr,
//             style: TextStyle(
//             fontSize: 25,
//             color: Colors.white,
//             ),
//           ),
//         ),
//         onPressed: () => controller.launchChromeVRView(context),
//       ),
//       ],
//     ),
//     ),
//         ),
//     );
//   }
//
// }
