
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/auth/ui/login/login_controller.dart';
import 'package:neom_commons/core/app_flavour.dart';
import 'package:neom_commons/core/utils/app_color.dart';
import 'package:neom_commons/core/utils/app_theme.dart';
import 'package:neom_commons/core/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/core/utils/constants/app_route_constants.dart';
import 'package:neom_commons/core/utils/constants/app_translation_constants.dart';
import 'package:neom_commons/core/utils/enums/app_in_use.dart';
import 'package:neom_commons/core/utils/enums/owner_type.dart';
import 'package:rflutter_alert/rflutter_alert.dart';

import '../widgets/chamber_widgets.dart';
import 'chamber_controller.dart';

class ChamberPage extends StatelessWidget {
  const ChamberPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ChamberController>(
        id: AppPageIdConstants.chamber,
        init: ChamberController(),
        builder: (_) => Scaffold(
          backgroundColor: AppColor.main75,
          body: Container(
            decoration: AppTheme.appBoxDecoration,
            padding: EdgeInsets.only(bottom: _.ownerType == OwnerType.profile ? 80 : 0),
            child: _.isLoading.value ? const Center(child: CircularProgressIndicator())
            : Column(
              children: [
                ListTile(
                  title: Text(AppTranslationConstants.createItemlist.tr),
                  leading: SizedBox.square(
                    dimension: 40,
                    child: Center(
                      child: Icon(
                        Icons.add_rounded,
                        color: Theme.of(context).iconTheme.color,
                      ),
                    ),
                  ),
                  onTap: () async {
                    (await showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColor.main75,
                        title: Text(AppTranslationConstants.addNewItemlist.tr,),
                        content: Obx(() => SizedBox(
                          height: AppTheme.fullHeight(context)*0.3,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              //TODO Change lines colors to white.
                              TextField(
                                controller: _.newChamberNameController,
                                decoration: InputDecoration(
                                  labelText: AppTranslationConstants.itemlistName.tr,
                                ),
                              ),
                              TextField(
                                controller: _.newChamberDescController,
                                minLines: 2,
                                maxLines: 5,
                                decoration: InputDecoration(
                                  labelText: AppTranslationConstants.description.tr,
                                ),
                              ),
                              AppTheme.heightSpace5,
                              Align(
                                alignment: Alignment.center,
                                child: GestureDetector(
                                  child: Row(
                                    children: <Widget>[
                                      Checkbox(
                                        value: _.isPublicNewChamber.value,
                                        onChanged: (bool? newValue) => _.setPrivacyOption(),
                                      ),
                                      Text(AppTranslationConstants.publicList.tr, style: const TextStyle(fontSize: 15)),
                                    ],
                                  ),
                                  onTap: () => _.setPrivacyOption(),
                                ),
                              ),
                              _.errorMsg.isNotEmpty ? Column(
                                children: [
                                  Align(
                                    alignment: Alignment.center,
                                    child: Text(_.errorMsg.value.tr, style: const TextStyle(fontSize: 12, color: AppColor.red)),
                                  ),
                                ],) : const SizedBox.shrink()
                            ],
                          ),
                        ),),
                        actions: <Widget>[
                          DialogButton(
                            height: 50,
                            color: AppColor.bondiBlue75,
                            onPressed: () async {
                              await _.createChamber();
                              if(_.errorMsg.value.isEmpty) Navigator.pop(ctx);
                            },
                            child: Text(
                              AppTranslationConstants.add.tr,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    )) ?? false;
                  },
                ),
                Expanded(
                  child: buildChamberList(context, _),
                ),
              ],
            )
          ),
          floatingActionButton: _.isLoading.value ? const SizedBox.shrink() : Container(
            margin: const EdgeInsets.only(bottom: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                        child: AnimatedTextKit(
                          repeatForever: true,
                          animatedTexts: [
                            FlickerAnimatedText(
                                AppFlavour.appInUse == AppInUse.g ?
                                AppTranslationConstants.synchronizeSpotifyPlaylists.tr
                                : AppTranslationConstants.suggestedReading.tr),
                          ],
                          onTap: () {
                            Get.toNamed(AppRouteConstants.pdfViewer,
                                arguments: [Get.find<LoginController>().appInfo.value.suggestedUrl, 0, 150]);
                            },
                        ),
                      ),
                    ),
                    const SizedBox(width: 5,),
                    FloatingActionButton(
                      heroTag: AppPageIdConstants.spotifySync,
                      elevation: AppTheme.elevationFAB,
                      child: Icon(AppFlavour.getSyncIcon()),
                      onPressed: () => {
                        Get.toNamed(AppRouteConstants.pdfViewer,
                            arguments: [Get.find<LoginController>().appInfo.value.suggestedUrl, true, 0, 250]
                        )
                      },
                    ),
                  ],
                ),
                if(_.ownerType == OwnerType.profile) AppTheme.heightSpace75,
              ]
          ),
          ),

      ),
    );
  }
}
