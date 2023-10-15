import 'dart:io';


import 'package:neom_generator/neom_generator/neom_generator_controller.dart';
import 'package:neom_generator/neom_generator/utils.constants/neom_generator_constants.dart';
import 'package:neom_generator/neom_generator/utils.constants/neom_slider_constants.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:neom_commons/neom_commons.dart';
import 'package:rflutter_alert/rflutter_alert.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';
import 'package:surround_frequency_generator/surround_frequency_generator.dart';
import 'package:get/get.dart';
import 'package:enum_to_string/enum_to_string.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

class NeomGeneratorPage extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return GetBuilder<NeomGeneratorController>(
        id: AppPageIdConstants.generator,
        init: NeomGeneratorController(),
    builder: (_) => WillPopScope(
        onWillPop: () async {

      try {
        if(_.isPlaying.value) {
          await _.playStopPreview();
        }
        _.soundController.removeListener(() { });
        _.soundController.dispose();
        _.soundController = SoundController();
        if(Platform.isAndroid) {
          await _.webViewAndroidController.clearCache(); // Clear the WebView cache (optional)
          await _.webViewAndroidController.goBack();    // Dispose of the WebView
        } else {
          await _.webViewIosController.clearCache();
          await _.webViewIosController.goBack();
        }

        _.isPlaying.value = false;
      } catch (e) {
        AppUtilities.logger.e(e.toString());
      }

      return true;
    },
    child: Scaffold(
      appBar: AppBarChild(title: AppTranslationConstants.frequencyGenerator.tr),
        body: Container(
        height: AppTheme.fullHeight(context),
        width: AppTheme.fullWidth(context),
        decoration: AppTheme.appBoxDecoration,
        child: SingleChildScrollView(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SoundWidget(soundController: _.soundController,
              webViewAndroidController: _.webViewAndroidController,
              webViewIosController: _.webViewIosController),
          AppTheme.heightSpace20,
          ValueListenableBuilder<AudioParam>(
            valueListenable: _.soundController,
            builder: (context, AudioParam freqValue, __) {
              AudioParam freqValue = _.getAudioParam();
              return Column(
                children: <Widget>[
                  SleekCircularSlider(
                    appearance: NeomSliderConstants.appearance01,
                    min: NeomGeneratorConstants.frequencyMin,
                    max: NeomGeneratorConstants.frequencyMax,
                    initialValue: _.chamberPreset.neomFrequency!.frequency,
                    onChange: (double val) async {
                      await _.setFrequency(val);
                    },
                    innerWidget: (double value) {
                      return Align(
                        alignment: Alignment.center,
                        child: SleekCircularSlider(
                          appearance: NeomSliderConstants.appearance02,
                          min: NeomGeneratorConstants.positionMin,
                          max: NeomGeneratorConstants.positionMax,
                          initialValue: freqValue.x,
                          onChange: (double val) {
                            _.setParameterPosition(x: val, y: freqValue.y, z: freqValue.z);
                            // _.soundController.setPosition(val, freqValue.y, freqValue.z);
                          },
                          innerWidget: (double v) {
                            return Align(
                              alignment: Alignment.center,
                              child: SleekCircularSlider(
                                appearance: NeomSliderConstants.appearance03,
                                min: NeomGeneratorConstants.positionMin,
                                max: NeomGeneratorConstants.positionMax,
                                initialValue: freqValue.y,
                                onChange: (double val) {
                                  _.setParameterPosition(x: freqValue.x, y: val, z: freqValue.z);
                                  // _.soundController.setPosition(freqValue.x, val, freqValue.z);
                                },
                                innerWidget: (double v) {
                                  return Align(
                                    alignment: Alignment.center,
                                    child: SleekCircularSlider(
                                      appearance: NeomSliderConstants.appearance04,
                                      min: NeomGeneratorConstants.positionMin,
                                      max: NeomGeneratorConstants.positionMax,
                                      initialValue: freqValue.z,
                                      onChange: (double val) {
                                        _.setParameterPosition(x: freqValue.x, y: freqValue.y, z: val);
                                      },
                                      innerWidget: (double val) {
                                        return Container(
                                          padding: EdgeInsets.all(25),
                                          child: Ink(
                                            decoration: BoxDecoration(
                                              color: _.isPlaying.value ? AppColor.deepDarkViolet : Colors.transparent,
                                              shape: BoxShape.circle,
                                            ),
                                            child: InkWell(
                                              child: IconButton(
                                                  onPressed: ()  async {
                                                    await _.playStopPreview();
                                                  },
                                                  icon: Icon(FontAwesomeIcons.om, size: 60)
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  Slider(
                    value: freqValue.volume,
                    min: NeomGeneratorConstants.volumeMin,
                    max: NeomGeneratorConstants.volumeMax,
                    onChanged: (val) {
                      _.setVolume(val);
                    },
                  ),
                  AppTheme.heightSpace20,
                  Text(
                    AppTranslationConstants.parameters.tr.capitalizeFirst!,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 25,
                    ),
                  ),
                  AppTheme.heightSpace10,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text("${AppTranslationConstants.volume.tr}: ${(_.soundController.value.volume*100).round()}"),
                      Text("${AppTranslationConstants.frequency.tr}: ${_.soundController.value.freq.round()} Hz"),
                    ],
                  ),
                  AppTheme.heightSpace10,
                  Text(
                    AppTranslationConstants.surroundSound.tr.capitalizeFirst!,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  AppTheme.heightSpace10,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text("${AppTranslationConstants.xAxis.tr}: ${_.soundController.value.x.toPrecision(2)}"),
                      Text("${AppTranslationConstants.yAxis.tr}: ${_.soundController.value.y.toPrecision(2)}"),
                      Text("${AppTranslationConstants.zAxis.tr}: ${_.soundController.value.z.toPrecision(2)}"),
                    ],
                  ),
                  AppTheme.heightSpace20,
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 30),
                    child: _.existsInChamber && !_.isUpdate ? Container() : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        GestureDetector(
                          child: buildIconActionChip(icon: Icon(Icons.remove), controllerFunction: () async {await _.decreaseFrequency();}),
                          onLongPress: () {
                            _.longPressed.value = true;
                            _.timerDuration.value = NeomGeneratorConstants.recursiveCallTimerDuration;
                            _.decreaseOnLongPress();
                          },
                          onLongPressUp: () => _.longPressed.value = false,
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                            backgroundColor: AppColor.bondiBlue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),),
                          child: Text(_.isUpdate ? AppTranslationConstants.savePreset.tr : _.existsInChamber ? AppTranslationConstants.removePreset.tr : AppTranslationConstants.savePreset.tr,
                              style: TextStyle(
                                  color: Colors.white,fontSize: 18.0,
                                  fontWeight: FontWeight.bold
                              )
                          ),
                          onPressed: () async {
                            if(_.existsInChamber && !_.isUpdate) {
                              await _.removePreset(context);
                            } else {
                              await Alert(
                                context: context,
                                style: AlertStyle(
                                    backgroundColor: AppColor.main50,
                                    titleStyle: const TextStyle(color: Colors.white)
                                ),
                                title: AppTranslationConstants.chamberPrefs.tr,
                                content: Column(
                                  children: <Widget>[
                                    Obx(()=>
                                        DropdownButton<String>(
                                          items: AppItemState.values.map((AppItemState itemState) {
                                            return DropdownMenuItem<String>(
                                                value: itemState.name,
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                  children: [
                                                    Text(itemState.name.tr),
                                                    itemState.value == 0 ? Container() : const Text(" - "),
                                                    itemState.value == 0 ? Container() :
                                                    RatingBar(
                                                      initialRating: itemState.value.toDouble(),
                                                      minRating: 1,
                                                      ignoreGestures: true,
                                                      direction: Axis.horizontal,
                                                      allowHalfRating: false,
                                                      itemCount: 5,
                                                      ratingWidget: RatingWidget(
                                                        full: CoreUtilities.ratingImage(AppAssets.heart),
                                                        half: CoreUtilities.ratingImage(AppAssets.heartHalf),
                                                        empty: CoreUtilities.ratingImage(AppAssets.heartBorder),
                                                      ),
                                                      itemPadding: const EdgeInsets.symmetric(horizontal: 1.0),
                                                      itemSize: 10,
                                                      onRatingUpdate: (rating) {
                                                        _.logger.i("New Rating set to $rating");
                                                      },
                                                    ),
                                                  ],
                                                )
                                            );
                                          }).toList(),
                                          onChanged: (String? newItemState) {
                                            _.setFrequencyState(EnumToString.fromString(AppItemState.values, newItemState!) ?? AppItemState.noState);
                                          },
                                          value: CoreUtilities.getItemState(_.frequencyState).name,
                                          alignment: Alignment.center,
                                          icon: const Icon(Icons.arrow_downward),
                                          iconSize: 15,
                                          elevation: 15,
                                          style: const TextStyle(color: Colors.white),
                                          dropdownColor: AppColor.main75,
                                          underline: Container(
                                            height: 1,
                                            color: Colors.grey,
                                          ),
                                        )
                                    ),
                                    _.chambers.length > 1 ? Obx(()=> DropdownButton<String>(
                                      items: _.chambers.values.map((neomChamber) =>
                                          DropdownMenuItem<String>(
                                            value: neomChamber.id,
                                            child: Center(
                                                child: Text(
                                                    neomChamber.name.length > AppConstants.maxItemlistNameLength
                                                        ? "${neomChamber.name
                                                        .substring(0,AppConstants.maxItemlistNameLength).capitalizeFirst}..."
                                                        : neomChamber.name.capitalizeFirst!
                                                )
                                            ),
                                          )
                                      ).toList(),
                                      onChanged: (String? selectedNeomChamber) {
                                        _.setSelectedItemlist(selectedNeomChamber!);
                                      },
                                      value: _.chamber.id,
                                      icon: const Icon(Icons.arrow_downward),
                                      alignment: Alignment.center,
                                      iconSize: 20,
                                      elevation: 16,
                                      style: const TextStyle(color: Colors.white),
                                      dropdownColor: AppColor.main75,
                                      underline: Container(
                                        height: 1,
                                        color: Colors.grey,
                                      ),
                                    )) : Container()
                                  ],
                                ),
                                buttons: [
                                  DialogButton(
                                    color: AppColor.bondiBlue75,
                                    child: Obx(()=>_.isLoading ? const Center(child: CircularProgressIndicator())
                                        : Text(AppTranslationConstants.add.tr,
                                    )),
                                    onPressed: () async {
                                      if(_.frequencyState > 0) {
                                        await _.addPreset(context, frequencyPracticeState: _.frequencyState);
                                        Navigator.pop(context);
                                      } else {
                                        Get.snackbar(
                                            AppTranslationConstants.appItemPrefs.tr,
                                            MessageTranslationConstants.selectItemStateMsg.tr,
                                            snackPosition: SnackPosition.bottom
                                        );
                                      }
                                    },
                                  )],
                              ).show();
                            }
                            Navigator.pop(context);
                          },
                        ),
                        GestureDetector(
                          child: buildIconActionChip(icon: Icon(Icons.add), controllerFunction: () async { await _.increaseFrequency();}),
                          onLongPress: () {
                            _.longPressed.value = true;
                            _.timerDuration.value = NeomGeneratorConstants.recursiveCallTimerDuration;
                            _.increaseOnLongPress();
                          },
                          onLongPressUp: () => _.longPressed.value = false,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    child:Text(_.frequencyDescription.value,
                      style: TextStyle(
                          fontSize: 12,
                          overflow: TextOverflow.ellipsis
                      ),
                      textAlign: TextAlign.justify,
                      maxLines: 6,
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 20),
                  ),
                  AppTheme.heightSpace50,
                  AppTheme.heightSpace20,
                ],
              );
            },
          ),
        ],
      ),),
        ),
      //TODO EXPERIMENTAL FEATURES TO MOVE NEOM CHAMBER 2D TO A 3D VERSION TO USE IT WITH SMARTPHONE VR
      // floatingActionButton: Row(
      //   mainAxisAlignment: MainAxisAlignment.end,
      //   children: [
      //   FloatingActionButton(
      //     heroTag: "",
      //     backgroundColor: Colors.white12,
      //     mini: true,
      //     child: Icon(FontAwesomeIcons.vrCardboard, size: 12,color: Colors.white,),
      //     onPressed: ()=>{
      //       // Get.to(() => PanoramaView())
      //     },
      //   ),
      //   FloatingActionButton(
      //     heroTag: " ",
      //     backgroundColor: Colors.white12,
      //     mini: true,
      //     child: Icon(FontAwesomeIcons.globe, size: 12,color: Colors.white,),
      //     onPressed: ()=> {
      //       // Get.to(() => VideoSection())
      //     },
      //   ),
      //     FloatingActionButton(
      //       heroTag: " _",
      //       backgroundColor: Colors.white12,
      //       mini: true,
      //       child: Icon(FontAwesomeIcons.chrome, size: 12,color: Colors.white,),
      //       onPressed: ()=> {
      //         _.neom360viewerController.launchChromeVRView(context, url: 'https://larkintuckerllc.github.io/hello-react-360/')
      //       },
      //     )
      // ],
      // )
    ),),
    );
  }
}