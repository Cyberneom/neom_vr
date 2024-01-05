import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:neom_commons/core/app_flavour.dart';
import 'package:neom_commons/core/data/firestore/chamber_firestore.dart';
import 'package:neom_commons/core/data/firestore/profile_firestore.dart';
import 'package:neom_commons/core/data/implementations/user_controller.dart';
import 'package:neom_commons/core/domain/model/app_profile.dart';
import 'package:neom_commons/core/domain/model/chamber.dart';
import 'package:neom_commons/core/domain/model/neom/chamber_preset.dart';
import 'package:neom_commons/core/domain/model/neom/neom_frequency.dart';
import 'package:neom_commons/core/domain/model/neom/neom_parameter.dart';
import 'package:neom_commons/core/utils/app_utilities.dart';
import 'package:neom_commons/core/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/core/utils/constants/app_translation_constants.dart';
import 'package:neom_commons/core/utils/enums/app_item_state.dart';
import 'package:neom_frequencies/frequencies/ui/frequency_controller.dart';
import 'package:surround_frequency_generator/surround_frequency_generator.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../domain/use_cases/neom_generator_service.dart';
import '../utils.constants/neom_generator_constants.dart';
import '../vr_experimental/neom_360_viewer_controller.dart';

class NeomGeneratorController extends GetxController implements NeomGeneratorService {

  final userController = Get.find<UserController>();
  final neom360viewerController = Get.put(Neom360ViewerController());
  final frequencyController = Get.put(FrequencyController());

  late SoundController soundController;
  WebViewController webViewAndroidController = WebViewController();
  PlatformWebViewController webViewIosController = PlatformWebViewController(const PlatformWebViewControllerCreationParams());

  AppProfile profile = AppProfile();

  ChamberPreset chamberPreset = ChamberPreset();

  RxBool isPlaying = false.obs;
  RxBool isLoading = true.obs;
  final RxInt frequencyState = 0.obs;
  final RxMap<String, Chamber> chambers = <String, Chamber>{}.obs;
  final Rx<Chamber> chamber = Chamber().obs;
  final RxBool existsInChamber = false.obs;
  final RxBool isUpdate = false.obs;
  final RxBool isButtonDisabled = false.obs;


  RxString frequencyDescription = "".obs;

  bool noItemlists = false;

  @override
  void onInit() async {
    super.onInit();
    List<dynamic> arguments  = Get.arguments ?? [];

    try {
      if(arguments.isNotEmpty) {
        if(arguments.elementAt(0) is ChamberPreset) {
          chamberPreset =  arguments.elementAt(0);
        } else if(arguments.elementAt(0) is NeomFrequency) {
          chamberPreset.neomFrequency = arguments.elementAt(0);
        }
      }

      profile = userController.profile;
      chambers.value = profile.chambers ?? {};
      soundController = SoundController();

      chamberPreset.neomFrequency ??= NeomFrequency();
      chamberPreset.neomParameter ??= NeomParameter();

      settingChamber();
    } catch(e) {
      AppUtilities.logger.e(e.toString());
    }

  }

  @override
  void onReady() async {
    super.onReady();
    try {

      await soundController.init();
      if(chambers.isEmpty) {
        noItemlists = true;
      } else {
        existsInChamber.value = frequencyAlreadyInItemlist();
        if(chamber.value.id.isEmpty) {
          chamber.value = chambers.values.first;
        }
      }

      frequencyDescription.value = chamberPreset.description.isNotEmpty
          ? chamberPreset.description : chamberPreset.neomFrequency!.description.isNotEmpty ? chamberPreset.neomFrequency!.description : "";

    } catch (e) {
      AppUtilities.logger.e(e.toString());
    }

    isLoading.value = false;
    update([AppPageIdConstants.generator]);
  }

  @override
  void dispose() {
    // Dispose the WebViewController

    super.dispose();
    // Dispose of GetX resources
    Get.delete<NeomGeneratorController>();
  }

  @override
  Future<void> settingChamber() async {

    try {
      AudioParam customAudioParam = AudioParam(
          volume: chamberPreset.neomParameter!.volume,
          x: chamberPreset.neomParameter!.x,
          y: chamberPreset.neomParameter!.y,
          z: chamberPreset.neomParameter!.z,
          freq:chamberPreset.neomFrequency!.frequency);
        soundController.value = customAudioParam;
    } catch (e) {
      AppUtilities.logger.e(e.toString());
      Get.back();
    }

    isLoading.value = false;
    update([AppPageIdConstants.generator]);
  }


  @override
  Future<void> setFrequency(double frequency) async {

    double threshold = 0.0000001;
    double freqDifference = (chamberPreset.neomFrequency!.frequency - frequency).abs();
    if(chamberPreset.neomFrequency!.frequency == frequency || (freqDifference < threshold)) return;

    chamberPreset.neomFrequency!.frequency = frequency.ceilToDouble();
    frequencyDescription.value = "";
    for (var element in frequencyController.frequencies.values) {
      if(element.frequency.ceilToDouble() == frequency.ceilToDouble()) {
        frequencyDescription.value = element.description;
      }
    }

    if(existsInChamber.value) isUpdate.value = true;

    await soundController.setFrequency(frequency);
    update([AppPageIdConstants.generator]);
  }


  @override
  void setVolume(double volume) async {
    chamberPreset.neomParameter!.volume = volume;
    soundController.setVolume(volume);
    if(existsInChamber.value) isUpdate.value = true;
    update([AppPageIdConstants.generator]);
  }

  @override
  Future<void> stopPlay() async {

    if(isPlaying.value && await soundController.isPlaying()) {
      await soundController.stop();
      isPlaying.value = false;
    } else {
      await soundController.play().whenComplete(() => isPlaying.value = true);
    }

    AppUtilities.logger.i('isPlaying: $isPlaying');
    update([AppPageIdConstants.generator]);
  }

  void changeControllerStatus(bool status){
    isPlaying.value = status;
    update([AppPageIdConstants.generator]);
  }

  AudioParam getAudioParam()  {
    soundController.init();
    return AudioParam(
          volume: chamberPreset.neomParameter!.volume,
          x: chamberPreset.neomParameter!.x,
          y: chamberPreset.neomParameter!.y,
          z: chamberPreset.neomParameter!.z,
          freq:chamberPreset.neomFrequency!.frequency);

  }

  Future<void> playStopPreview() async {

    AppUtilities.logger.d("Previewing Chamber Preset ${chamberPreset.name}");

    try {
      if(await soundController.isPlaying()) {
        AppUtilities.logger.d("Stopping Chamber Preset ${chamberPreset.name}");
        await soundController.stop();
        await soundController.init();
        changeControllerStatus(false);
      } else {
        AppUtilities.logger.d("Playing Chamber Preset ${chamberPreset.name}");
        settingChamber();
        await soundController.init();
        await soundController.play();
        changeControllerStatus(true);
      }
      // await audioPlayer.play(BytesSource(createSample(240)));
    } catch(e) {
      AppUtilities.logger.e(e.toString());
    }

    update([AppPageIdConstants.generator]);
  }


  void setFrequencyState(AppItemState newState){
    AppUtilities.logger.d("Setting new appItem $newState");
    frequencyState.value = newState.value;
    chamberPreset.state = newState.value;
    update([AppPageIdConstants.generator]);
  }

  void setSelectedItemlist(String selectedItemlist){
    AppUtilities.logger.d("Setting selectedItemlist $selectedItemlist");
    chamber.value.id  = selectedItemlist;
    update([AppPageIdConstants.generator]);
  }

  bool frequencyAlreadyInItemlist() {
    AppUtilities.logger.d("Verifying if Item already exists in chambers");

    bool alreadyInItemlist = false;
    for (var nChamber in chambers.values) {
      for (var presets in nChamber.chamberPresets!) {
        if (chamberPreset.id == presets.id) {
          alreadyInItemlist = true;
          chamber.value = nChamber;
        }
      }
    }

    AppUtilities.logger.d("Frequency already exists in chambers: $alreadyInItemlist");
    return alreadyInItemlist;
  }

  Future<void> addPreset(BuildContext context, {int frequencyPracticeState = 0}) async {

    if(!isButtonDisabled.value) {
      isButtonDisabled.value = true;
      isLoading.value = true;
      update([AppPageIdConstants.generator]);

      AppUtilities.logger.i("ChamberPreset would be added as $frequencyState for Itemlist ${chamber.value.id}");

      if(frequencyPracticeState > 0) frequencyState.value = frequencyPracticeState;

      if(noItemlists) {
        chamber.value.name = AppTranslationConstants.myFavItemlistName.tr;
        chamber.value.description = AppTranslationConstants.myFavItemlistDesc.tr;
        chamber.value.imgUrl = AppFlavour.getAppLogoUrl();
        chamber.value.ownerId = profile.id;
        chamber.value.id = await ChamberFirestore().insert(chamber.value);
      } else {
        if(chamber.value.id.isEmpty) chamber.value.id = chambers.values.first.id;
      }

      if(chamber.value.id.isNotEmpty) {

        try {
          chamberPreset.id = "${chamberPreset.neomFrequency!.frequency.ceilToDouble().toString()}_${chamberPreset.neomParameter!.volume.toString()}"
              "_${chamberPreset.neomParameter!.x.toString()}_${chamberPreset.neomParameter!.y.toString()}_${chamberPreset.neomParameter!.z.toString()}";
          chamberPreset.name = "${AppTranslationConstants.frequency.tr} ${chamberPreset.neomFrequency!.frequency.ceilToDouble().toString()} Hz";
          chamberPreset.imgUrl = AppFlavour.getAppLogoUrl();
          chamberPreset.ownerId = profile.id;
          chamberPreset.neomFrequency!.description = frequencyDescription.value;
          if(await ChamberFirestore().addPreset(chamber.value.id, chamberPreset)) {
            await ProfileFirestore().addChamberPreset(profileId: profile.id, chamberPresetId: chamberPreset.id);
            await userController.reloadProfileItemlists();
            chambers.value = userController.profile.chambers ?? {};
            AppUtilities.logger.d("Preset added to Neom Chamber");
          } else {
            AppUtilities.logger.d("Preset not added to Neom Chamber");
          }
        } catch (e) {
          AppUtilities.logger.e(e.toString());
          AppUtilities.showSnackBar(
              title: AppTranslationConstants.generator.tr,
              message: 'Algo salió mal agregando tu preset a tu cámara Neom.'
          );
        }

        AppUtilities.showSnackBar(
            title: AppTranslationConstants.generator.tr,
            message: 'El preajuste para la frecuencia de "${chamberPreset.neomFrequency!.frequency.ceilToDouble().toString()}"'
                ' Hz fue agregado a la Cámara Neom: ${chamber.value.name}.'
        );
      }
    }

    existsInChamber.value = true;
    isButtonDisabled.value = false;
    isLoading.value = false;

    update([]);
  }

  Future<void> removePreset(BuildContext context) async {


    if(!isButtonDisabled.value) {
      isButtonDisabled.value = true;
      isLoading.value = true;
      update([AppPageIdConstants.generator]);

      AppUtilities.logger.i("ChamberPreset would be removed for Itemlist ${chamber.value.id}");

      if(chamber.value.id.isEmpty) chamber.value.id = chambers.values.first.id;

      if(chamber.value.id.isNotEmpty) {
        try {
          if(await ChamberFirestore().deletePreset(chamber.value.id, chamberPreset)) {
            await userController.reloadProfileItemlists();
            chambers.value = userController.profile.chambers ?? {};
            AppUtilities.logger.d("Preset removed from Neom Chamber");
          } else {
            AppUtilities.logger.d("Preset not removed from Neom Chamber");
          }
        } catch (e) {
          AppUtilities.logger.e(e.toString());
          AppUtilities.showSnackBar(
              title: AppTranslationConstants.frequencyGenerator.tr,
              message: 'Algo salió mal eliminando tu preset de tu cámara Neom.'
          );
        }

        AppUtilities.showSnackBar(
            title: AppTranslationConstants.frequencyGenerator.tr,
            message: 'El preajuste para la frecuencia de "${chamberPreset.neomFrequency!.frequency.ceilToDouble().toString()}"'
                ' Hz fue removido de la Cámara Neom: ${chamber.value.name} satisfactoriamente.'
        );
      }
    }

    existsInChamber.value = false;
    isButtonDisabled.value = false;
    isLoading.value = false;
    update([]);
  }

  @override
  void setParameterPosition({required double x, required double y, required double z}) {

    try {
      chamberPreset.neomParameter!.x = x;
      chamberPreset.neomParameter!.y = y;
      chamberPreset.neomParameter!.z = z;

      soundController.setPosition(x,y,z);
    } catch(e) {
      AppUtilities.logger.e(e.toString());
    }

    if(existsInChamber.value) isUpdate.value = true;
    update([]);
  }

  Future<void> increaseFrequency({double step = 1}) async {
    double newFrequency = chamberPreset.neomFrequency!.frequency + step;
    if(newFrequency <= 0) return;
    AppUtilities.logger.d("Increasing Frequency from ${chamberPreset.neomFrequency!.frequency} to $newFrequency");
    chamberPreset.neomFrequency!.frequency = newFrequency;
    frequencyDescription.value = "";
    for (var element in frequencyController.frequencies.values) {
      if(element.frequency.ceilToDouble() == newFrequency) {
        frequencyDescription.value = element.description;
      }
    }

    if(existsInChamber.value) isUpdate.value = true;

    await soundController.setFrequency(newFrequency);
    update([AppPageIdConstants.generator]);
  }

  Future<void> decreaseFrequency({double step = 1}) async {
    double newFrequency = chamberPreset.neomFrequency!.frequency - step;
    if(newFrequency <= 0) return;
    await setFrequency(newFrequency);
  }

  RxBool longPressed = false.obs;
  RxInt timerDuration = NeomGeneratorConstants.recursiveCallTimerDuration.obs;

  void increaseOnLongPress() {
    if(longPressed.value) {
      if(timerDuration > NeomGeneratorConstants.recursiveCallTimerDurationMin) timerDuration--;
      increaseFrequency();
      Timer(Duration(milliseconds: timerDuration.value), increaseOnLongPress);
    }
  }

  void decreaseOnLongPress() {
    if(longPressed.value) {
      if(timerDuration > NeomGeneratorConstants.recursiveCallTimerDurationMin) timerDuration--;
      decreaseFrequency();
      Timer(Duration(milliseconds: timerDuration.value), decreaseOnLongPress);
    }
  }

}
