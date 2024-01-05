import 'package:neom_commons/core/domain/model/neom/chamber_preset.dart';
import 'package:neom_commons/core/utils/enums/chamber_preset_state.dart';

abstract class ChamberPresetService {

  Future<void> updateChamberPreset(ChamberPreset updatedPreset);
  Future<bool> removePresetFromChamber(ChamberPreset chamberPreset);
  void setChamberPresetState(ChamberPresetState newState);
  Future<void> getChamberPresetDetails(ChamberPreset chamberPreset);
  Future<bool> addPresetToChamber(ChamberPreset chamberPreset, String chamberId);
  void loadPresetsFromChamber();

}
