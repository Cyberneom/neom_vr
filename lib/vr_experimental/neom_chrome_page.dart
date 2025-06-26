import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'neom_360_viewer_controller.dart';

class NeomChromePage extends StatelessWidget {
  const NeomChromePage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<Neom360ViewerController>(
        builder: (_) => Scaffold(
        body: Container(
          color: Colors.blue,
          child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
              Row(),
          Text('VR Experimental',
          style: TextStyle(
          fontSize: 60,
          color: Colors.white,
          fontWeight: FontWeight.bold
          ),
        ),
        SizedBox(height: 20),
        TextButton(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text('ENTER',
            style: TextStyle(
            fontSize: 25,
            color: Colors.white,
            ),
          ),
        ),
        onPressed: () => _.launchChromeVRView(context),
      ),
      ],
    ),
    ),
        ),
    );
  }

}
