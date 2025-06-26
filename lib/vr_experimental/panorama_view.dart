import 'package:flutter/material.dart';
import 'package:neom_core/core/app_config.dart';
import 'package:panorama/panorama.dart';
import 'package:split_view/split_view.dart';


class PanoramaView extends StatelessWidget {
  const PanoramaView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
      child:
      SplitView(
        viewMode: SplitViewMode.Vertical,
        activeIndicator: SplitIndicator(
          viewMode: SplitViewMode.Vertical,
          isActive: true,
        ),
        onWeightChanged: (w) => AppConfig.logger.d("Horizon: $w"),
        controller: SplitViewController(limits: [null, WeightLimit(max: 0.5)]),
        children: [
          Panorama(
            child: Image.network('https://image.shutterstock.com/z/stock-photo-connection-lines-around-earth-globe-futuristic-technology-theme-background-with-light-effect-d-549340267.jpg'),
          ),
          Panorama(
            child: Image.network('https://image.shutterstock.com/z/stock-photo-connection-lines-around-earth-globe-futuristic-technology-theme-background-with-light-effect-d-549340267.jpg'),
          ),
        ],
      ),
      ),
    );
  }
}
