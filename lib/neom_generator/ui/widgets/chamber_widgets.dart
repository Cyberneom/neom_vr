import 'package:enum_to_string/enum_to_string.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/core/domain/model/chamber.dart';
import 'package:neom_commons/core/domain/model/neom/chamber_preset.dart';
import 'package:neom_commons/core/ui/widgets/handled_cached_network_image.dart';
import 'package:neom_commons/core/ui/widgets/rating_heart_bar.dart';
import 'package:neom_commons/core/utils/enums/chamber_preset_state.dart';
import 'package:neom_commons/neom_commons.dart';
import 'package:rflutter_alert/rflutter_alert.dart';

import '../chamber/chamber_controller.dart';
import '../chamber/chamber_preset_controller.dart';

Widget buildChamberList(BuildContext context, ChamberController _) {
  return ListView.separated(
    separatorBuilder: (context, index) => const Divider(),
    itemCount: _.chambers.length,
    shrinkWrap: true,
    itemBuilder: (context, index) {
      Chamber chamber = _.chambers.values.elementAt(index);
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: SizedBox(
            width: 50,
            child: HandledCachedNetworkImage(chamber.imgUrl.isNotEmpty ? chamber.imgUrl : AppFlavour.getAppLogoUrl())
        ),
        title: Row(
            children: <Widget>[
              Text(chamber.name.length > AppConstants.maxItemlistNameLength
                  ? "${chamber.name.substring(0,AppConstants.maxItemlistNameLength).capitalizeFirst}..."
                  : chamber.name.capitalizeFirst),
              ///DEPRECATE .isFav ? const Icon(Icons.favorite, size: 10,) : SizedBox.shrink()
            ]),
        subtitle: chamber.description.isNotEmpty ? Text(chamber.description.capitalizeFirst, maxLines: 3, overflow: TextOverflow.ellipsis,) : null,
        trailing: ActionChip(
          labelPadding: EdgeInsets.zero,
          backgroundColor: AppColor.main25,
          avatar: CircleAvatar(
            backgroundColor: AppColor.white80,
            child: Text(((chamber.chamberPresets?.length ?? 0)).toString(),
                style: const TextStyle(color: Colors.black87),
            ),
          ),
          label: Icon(AppFlavour.getAppItemIcon(), color: AppColor.white80),
          onPressed: () async {
            await _.gotoChamberPresets(chamber);
            ///ADD CHAMBERPRESET SEARCH HERE
            // if(!chamber.isModifiable) {
            //   await _.gotoChamberPresets(chamber);
            // } else {
            //   Get.toNamed(AppRouteConstants.itemSearch,
            //       arguments: [SpotifySearchType.song, chamber]
            //   );
            // }
          },
        ),
        onTap: () async {
          await _.gotoChamberPresets(chamber);
        },
        onLongPress: () async {
          (await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
            backgroundColor: AppColor.main75,
            title: Text(AppTranslationConstants.itemlistName.tr,),
            content: SizedBox(
              height: AppTheme.fullHeight(context)*0.25,
              child: Obx(()=> _.isLoading.value ? const Center(child: CircularProgressIndicator())
                : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    TextField(
                      controller: _.newChamberNameController,
                      decoration: InputDecoration(
                        labelText: '${AppTranslationConstants.changeName.tr}: ',
                        hintText: chamber.name,
                      ),
                    ),
                    TextField(
                      controller: _.newChamberDescController,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: '${AppTranslationConstants.changeDesc.tr}: ',
                        hintText: chamber.description,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              DialogButton(
                color: AppColor.bondiBlue75,
                onPressed: () async {
                  await _.updateChamber(chamber.id, chamber);
                  Navigator.pop(ctx);
                },
                child: Text(AppTranslationConstants.update.tr,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              DialogButton(
                color: AppColor.bondiBlue75,
                child: Text(AppTranslationConstants.remove.tr,
                  style: const TextStyle(fontSize: 14),
                ),
                onPressed: () async {
                  if(_.chambers.length == 1) {
                    AppUtilities.showAlert(context,
                        title: AppTranslationConstants.itemlistPrefs.tr,
                        message: AppTranslationConstants.cantRemoveMainItemlist.tr);
                  } else {
                    await _.deleteChamber(chamber);
                    Navigator.pop(ctx);
                  }
                },
              ),
            ],
          ),
          )) ?? false;
        },
      );
    },
  );
}

Widget buildPresetsList(BuildContext context, ChamberPresetController _) {
  return ListView.separated(
    separatorBuilder: (context, index) => const Divider(),
    itemCount: _.chamberPresets.length,
    itemBuilder: (context, index) {
      ChamberPreset chamberPreset = _.chamberPresets.values.elementAt(index);
      return ListTile(
          leading: HandledCachedNetworkImage(chamberPreset.imgUrl.isNotEmpty
              ? chamberPreset.imgUrl : _.chamber.imgUrl, enableFullScreen: false,
            width: 40,
          ),
          title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(chamberPreset.name.isEmpty ? ""
                    : chamberPreset.name.length > AppConstants.maxAppItemNameLength
                    ? "${chamberPreset.name.substring(0,AppConstants.maxAppItemNameLength)}..."
                    : chamberPreset.name),
                const SizedBox(width:5),
                (AppFlavour.appInUse == AppInUse.c || (_.userController.profile.type == ProfileType.appArtist && !_.isFixed)) ?
                RatingHeartBar(state: chamberPreset.state.toDouble()) : const SizedBox.shrink(),
              ]
          ),
          subtitle: Text(chamberPreset.description, textAlign: TextAlign.justify,),
          trailing: IconButton(
              icon: const Icon(
                  CupertinoIcons.forward
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                ChamberPreset preset = _.chamber.chamberPresets!.firstWhere((element) => element.id == chamberPreset.id);
                Get.toNamed(AppRouteConstants.generator,  arguments: [preset.clone()]);
              }
          ),
          onTap: () {
            if(!_.isFixed) {
              _.getChamberPresetDetails(chamberPreset);
            } else {
              ChamberPreset preset = _.chamber.chamberPresets!.firstWhere((element) => element.id == chamberPreset.id);
              Get.toNamed(AppRouteConstants.generator,  arguments: [preset.clone()]);
            }
          },
          onLongPress: () => _.chamber.isModifiable && (AppFlavour.appInUse != AppInUse.c || !_.isFixed) ? Alert(
              context: context,
              title: AppTranslationConstants.appItemPrefs.tr,
              style: AlertStyle(
                  backgroundColor: AppColor.main50,
                  titleStyle: const TextStyle(color: Colors.white)
              ),
              content: Column(
                children: <Widget>[
                  Obx(() =>
                      DropdownButton<String>(
                        items: AppItemState.values.map((AppItemState appItemState) {
                          return DropdownMenuItem<String>(
                              value: appItemState.name,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(appItemState.name.tr),
                                  appItemState.value == 0 ? const SizedBox.shrink() : const Text(" - "),
                                  appItemState.value == 0 ? const SizedBox.shrink() :
                                  RatingHeartBar(state: appItemState.value.toDouble(),),
                                ],
                              )
                          );
                        }).toList(),
                        onChanged: (String? newItemState) {
                          _.setChamberPresetState(EnumToString.fromString(ChamberPresetState.values, newItemState!) ?? ChamberPresetState.noState);
                        },
                        value: CoreUtilities.getItemState(_.itemState.value).name,
                        icon: const Icon(Icons.arrow_downward),
                        iconSize: 15,
                        elevation: 15,
                        style: const TextStyle(color: Colors.white),
                        dropdownColor: AppColor.getMain(),
                        underline: Container(
                          height: 1,
                          color: Colors.grey,
                        ),
                      ),
                  ),
                ],
              ),
              buttons: [
                DialogButton(
                  color: AppColor.bondiBlue75,
                  child: Text(AppTranslationConstants.update.tr,
                    style: const TextStyle(fontSize: 15),
                  ),
                  onPressed: () => {
                    _.updateChamberPreset(chamberPreset)
                  },
                ),
                DialogButton(
                  color: AppColor.bondiBlue75,
                  child: Text(AppTranslationConstants.remove.tr,
                    style: const TextStyle(fontSize: 15),
                  ),
                  onPressed: () async => {
                    await _.removePresetFromChamber(chamberPreset)
                  },
                ),
              ]
          ).show() : {}
      );
    },
  );
}
