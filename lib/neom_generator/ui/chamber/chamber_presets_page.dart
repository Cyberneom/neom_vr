import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:neom_commons/core/ui/widgets/appbar_child.dart';
import 'package:neom_commons/core/utils/app_color.dart';
import 'package:neom_commons/core/utils/app_theme.dart';
import 'package:neom_commons/core/utils/constants/app_constants.dart';
import 'package:neom_commons/core/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/core/utils/constants/app_route_constants.dart';
import 'package:neom_commons/core/utils/constants/app_translation_constants.dart';
import 'package:neom_commons/core/utils/enums/spotify_search_type.dart';

import '../widgets/chamber_widgets.dart';
import 'chamber_preset_controller.dart';

class ChamberPresetsPage extends StatelessWidget {
  const ChamberPresetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ChamberPresetController>(
      id: AppPageIdConstants.chamberPresets,
      init: ChamberPresetController(),
      builder: (_) => Scaffold(
        backgroundColor: AppColor.getMain(),
        appBar: AppBarChild(title: _.chamber.name.length > AppConstants.maxItemlistNameLength
            ? "${_.chamber.name.substring(0,AppConstants.maxItemlistNameLength)}..."
            : _.chamber.name),
        body: Container(
          width: AppTheme.fullWidth(context),
          height: AppTheme.fullHeight(context),
          decoration: AppTheme.appBoxDecoration, 
          child: _.isLoading.value ? const Center(child: CircularProgressIndicator())
              : Obx(()=> buildPresetsList(context, _)),
        ),
        floatingActionButton: _.isFixed || !_.chamber.isModifiable ? const SizedBox.shrink()
            : FloatingActionButton(
          tooltip: AppTranslationConstants.addItem.tr,
          onPressed: ()=> {
            Get.toNamed(AppRouteConstants.itemSearch,
                arguments: [SpotifySearchType.song, _.chamber])
          },
          child: const Icon(Icons.playlist_add),
        ),
      ),
    );
  }
}
