import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/commons/ui/theme/app_color.dart';
import 'package:neom_commons/commons/ui/widgets/appbar_child.dart';
import 'package:video_360/video_360.dart';

import 'neom_360_viewer_controller.dart';

class Neom360ViewerPage extends StatelessWidget {
  const Neom360ViewerPage({super.key});


  @override
  Widget build(BuildContext context) {

    var width = MediaQuery.of(context).size.width;
    var height = MediaQuery.of(context).size.height;

    return GetBuilder<Neom360ViewerController>(
        builder: (_) => Scaffold(
      appBar: AppBarChild(title: 'Video 360 Plugin example app'),
      body: Stack(
        children: [
          Center(
            child: SizedBox(
              width: width,
              height: height,
              child: Video360View(
                onVideo360ViewCreated: _.onVideo360ViewCreated,
                url: 'https://multiplatform-f.akamaihd.net/i/multi/will/bunny/big_buck_bunny_,640x360_400,640x360_700,640x360_1000,950x540_1500,.f4v.csmil/master.m3u8',
                onPlayInfo: (Video360PlayInfo info) {
                  _.setPlayInfoValue(info);
                },
              ),
            ),
          ),
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  MaterialButton(
                    onPressed: () {
                      _.controller.play();
                    },
                    color: AppColor.darkViolet,
                    child: Text('Play'),
                  ),
                  MaterialButton(
                    onPressed: () {
                      _.controller.stop();
                    },
                    color: AppColor.darkViolet,
                    child: Text('Stop'),
                  ),
                  MaterialButton(
                    onPressed: () {
                      _.controller.reset();
                    },
                    color: AppColor.darkViolet,
                    child: Text('Reset'),
                  ),
                  MaterialButton(
                    onPressed: () {
                      _.controller.jumpTo(80000);
                    },
                    color: AppColor.darkViolet,
                    child: Text('1:20'),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  MaterialButton(
                    onPressed: () {
                      _.controller.seekTo(-2000);
                    },
                    color: AppColor.darkViolet,
                    child: Text('<<'),
                  ),
                  MaterialButton(
                    onPressed: () {
                      _.controller.seekTo(2000);
                    },
                    color: AppColor.darkViolet,
                    child: Text('>>'),
                  ),
                  Flexible(
                    child: MaterialButton(
                      onPressed: () {},
                      color: AppColor.darkViolet,
                      child: Text('${_.durationText} / ${_.totalText.value}'),
                    ),
                  ),
                ],
              )
            ],
          )
        ],
      ),),
    );
  }

}
