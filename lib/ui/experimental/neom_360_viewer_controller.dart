// import 'dart:async';
//
// import 'package:flutter/material.dart';
// import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
// import 'package:get/get.dart';
// import 'package:neom_core/app_config.dart';
// import 'package:neom_core/data/implementations/user_controller.dart';
// import 'package:video_360/video_360.dart';
//
// import '../../domain/use_cases/neom_360_viewer_service.dart';
// import '../../utils/constants/vr_constants.dart';
//
// ///TOTALLY EXPERIMENTAL YET - JUST PLAYING AS VR MUST BE EVEN FOR SMARTPHONE VR USERS
// class Neom360ViewerController extends GetxController implements Neom360ViewerService {
//
//   final neomUserController = Get.find<UserController>();
//
//   late Video360Controller controller;
//   late Video360Controller controller2;
//
//   RxString durationText = "".obs;
//   RxString totalText = "".obs;
//   RxBool isPlaying = false.obs;
//   RxBool isLoading = true.obs;
//
//   @override
//   void onInit() async {
//     super.onInit();
//   }
//
//   @override
//   void onVideo360ViewCreated(Video360Controller controller) {
//     this.controller = controller;
//     controller2 = controller;
//   }
//
//   @override
//   FutureOr onClose() {
//     super.onClose();
//   }
//
//   @override
//   Future<void> launchChromeVRView(BuildContext context, {String url = ''}) async {
//
//     try {
//       if(url.isEmpty) url = VrConstants.vrDemoUrl;
//
//       await launchUrl(
//         Uri.parse(url),
//         customTabsOptions: CustomTabsOptions(
//           // toolbarColor: Theme.of(context).primaryColor,
//           urlBarHidingEnabled: true,
//           showTitle: false,
//           animations: CustomTabsSystemAnimations.slideIn(),
//           // extraCustomTabs: const <String>[
//           //   // ref.
//           //   'https://play.google.com/store/apps/details?id=org.mozilla.firefox',
//           //   'org.mozilla.firefox',
//           //   // ref.
//           //   'https://play.google.com/store/apps/details?id=com.microsoft.emmx',
//           //   'com.microsoft.emmx',
//           // ],
//         ),
//       );
//     } catch (e) {
//       // An exception is thrown if browser app is not installed on Android device.
//       AppConfig.logger.e(e.toString());
//     }
//   }
//
//   @override
//   void setPlayInfoValue(Video360PlayInfo info) {
//     durationText.value = info.duration.toString();
//     totalText.value = info.total.toString();
//   }
//
// }
