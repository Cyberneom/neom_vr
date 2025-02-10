import 'package:get/get.dart';
import 'package:neom_commons/core/app_flavour.dart';
import 'package:neom_commons/core/data/api_services/push_notification/firebase_messaging_calls.dart';
import 'package:neom_commons/core/data/firestore/chamber_firestore.dart';
import 'package:neom_commons/core/data/implementations/user_controller.dart';
import 'package:neom_commons/core/domain/model/band.dart';
import 'package:neom_commons/core/domain/model/chamber.dart';
import 'package:neom_commons/core/domain/model/neom/chamber_preset.dart';
import 'package:neom_commons/core/utils/app_utilities.dart';
import 'package:neom_commons/core/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/core/utils/enums/app_in_use.dart';
import 'package:neom_commons/core/utils/enums/chamber_preset_state.dart';
import 'package:neom_commons/core/utils/enums/owner_type.dart';
import 'package:neom_commons/core/utils/enums/push_notification_type.dart';

import '../../domain/use_cases/chamber_preset_service.dart';

class ChamberPresetController extends GetxController implements ChamberPresetService {

  var logger = AppUtilities.logger;
  final userController = Get.find<UserController>();

  ChamberPreset chamberPreset = ChamberPreset();
  Chamber chamber = Chamber();

  final RxInt itemState = 0.obs;
  final RxMap<String, ChamberPreset> chamberPresets = <String, ChamberPreset>{}.obs;
  final RxBool isLoading = true.obs;

  bool isFixed = false;

  String profileId = "";
  String chamberId = "";
  Band band = Band();
  int _prevItemState = 0;
  OwnerType chamberOwner = OwnerType.profile;


  @override
  void onInit() async {
    super.onInit();
    logger.d("ItemlistItem Controller init");
    try {
      profileId = userController.profile.id;
      band = userController.band;
      chamberOwner = userController.itemlistOwner;

      if(Get.arguments != null) {
        List<dynamic> arguments = Get.arguments;
        if(arguments[0] is Chamber) {
          chamber =  arguments[0];
        } else if(arguments[0] is String) {
          chamberId = arguments[0];
          chamber = await ChamberFirestore().retrieve(chamberId);
        }

        if(arguments.length > 1) {
          isFixed = arguments[1];
        }
      }

      if(chamber.id.isNotEmpty) {
        logger.i("AppMediaItemController for Chamber: ${chamber.id} ${chamber.name} ");
        logger.d("${chamber.chamberPresets?.length ?? 0} presets in chamber");
        loadPresetsFromChamber();
      } else {
        logger.i("ChamberPresetController Init ready loco with no chamber");
      }

      if(AppFlavour.appInUse == AppInUse.c) {
        isFixed = true;
      }
    } catch (e) {
      logger.e(e.toString());
    }

  }


  @override
  void onReady() {
    super.onReady();
    isLoading.value = false;
    update([AppPageIdConstants.chamberPresets]);
  }

  void clear() {
    chamberPresets.value = <String, ChamberPreset>{};
  }

  @override
  Future<void> updateChamberPreset(ChamberPreset updatedPreset) async {
    logger.d("Preview state ${updatedPreset.state}");
    if(updatedPreset.state == itemState.value) {
      logger.d("Trying to set same status");
    } else {
      _prevItemState = updatedPreset.state;
      updatedPreset.state = itemState.value;
      logger.d("updating itemlistItem ${updatedPreset.toString()}");
      try {

        if (await ChamberFirestore().updatePreset(chamber.id, updatedPreset)) {
          chamberPresets.update(updatedPreset.id, (preset) => preset);
          userController.profile.chambers![chamber.id]!
              .chamberPresets!.add(updatedPreset);
          updatedPreset.state = _prevItemState;
          userController.profile.chambers![chamber.id]!
              .chamberPresets!.remove(updatedPreset);
          if(await ChamberFirestore().deletePreset(chamber.id, updatedPreset)) {
            logger.d("ChamberPreset was updated and old version deleted.");
          } else {
            logger.d("ChamberPreset was updated but old version remains.");
          }
          updatedPreset.state = itemState.value;
        } else {
          logger.e("ChamberPreset not updated");
        }
      } catch (e) {
        logger.e(e.toString());
      }

      Get.back();
      update([AppPageIdConstants.chamberPresets]);
    }
  }

  @override
  Future<bool> addPresetToChamber(ChamberPreset chamberPreset, String chamberId) async {

    logger.d("Item ${chamberPreset.name} would be added as $itemState for Itemlist $chamberId");

    try {
      if(await ChamberFirestore().addPreset(chamberId, chamberPreset)) {
        if (chamberOwner == OwnerType.profile) {
          if (userController.profile.itemlists!.isNotEmpty) {
            logger.d("Adding item to global itemlist from userController");
            userController.profile.chambers![chamberId]!.chamberPresets!.add(chamberPreset);
            chamber = userController.profile.chambers![chamberId]!;
            loadPresetsFromChamber();
          }

          FirebaseMessagingCalls.sendGlobalPushNotification(
              fromProfile: userController.profile,
              notificationType: PushNotificationType.chamberPresetAdded,
              referenceId: chamberPreset.id,
              imgUrl: chamberPreset.imgUrl
          );

          return true;
        } else if (chamberOwner == OwnerType.band) {
          if (userController.band.itemlists!.isNotEmpty) {
            logger.d("Adding item to global itemlist from userController");
            userController.band.chambers![chamberId]!.chamberPresets!.add(chamberPreset);
            chamber = userController.band.chambers![chamberId]!;
            loadPresetsFromChamber();
          }
          return true;
        }
      }
    } catch (e) {
      logger.e(e.toString());
    }

    update([AppPageIdConstants.chamberPresets, AppPageIdConstants.chamber, AppPageIdConstants.chamberPresetDetails]);
    return false;
  }

  @override
  Future<bool> removePresetFromChamber(ChamberPreset chamberPreset) async {
    logger.d("removing itemlistItem ${chamberPreset.toString()}");

    try {
      if(await ChamberFirestore().deletePreset(chamber.id, chamberPreset)) {
        logger.d("Removing item from global itemlist from userController");
        userController.profile.chambers = await ChamberFirestore().fetchAll(ownerId: userController.profile.id);
        chamberPresets.remove(chamberPreset.id);

      } else {
        logger.d("ChamberPreset not removed");
        return false;
      }
    } catch (e) {
      logger.e(e.toString());
      return false;
    }

    Get.back();
    update([AppPageIdConstants.chamberPresets, AppPageIdConstants.chamber]);
    return true;
  }


  @override
  void setChamberPresetState(ChamberPresetState newState){
    logger.d("Setting new chamberPresetState $newState");
    itemState.value = newState.value;
    update([AppPageIdConstants.itemlistItem, AppPageIdConstants.appItem]);
  }

  @override
  Future<void> getChamberPresetDetails(ChamberPreset appMediaItem) async {
    logger.d("getChamberPresetDetails ${appMediaItem.name}");

    if(appMediaItem.imgUrl.isEmpty && chamber.imgUrl.isNotEmpty) appMediaItem.imgUrl = chamber.imgUrl;

    ChamberPreset chamberPreset = chamber.chamberPresets?.firstWhere((element) => element.name == appMediaItem.name) ?? ChamberPreset();
    if(chamberPreset.name.isNotEmpty) {
      Get.toNamed(AppFlavour.getMainItemDetailsRoute(), arguments: [chamberPreset.clone()]
      );
    }

    update([AppPageIdConstants.chamberPresets]);
  }

  @override
  void loadPresetsFromChamber(){
    Map<String, ChamberPreset> presets = {};

    if(chamber.chamberPresets?.isNotEmpty ?? false) {
      chamber.chamberPresets?.forEach((preset) {
        logger.d(preset.name);
        presets[preset.id] = preset;
      });
    }

    chamberPresets.value = presets;
    update([AppPageIdConstants.chamberPresets]);
  }

}
