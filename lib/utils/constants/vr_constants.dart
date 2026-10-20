class VrConstants {
  static const String vrDemoUrl = 'https://sbis04.github.io/demo360';
  static const String vrVideoUrl =
      'https://multiplatform-f.akamaihd.net/i/multi/will/bunny/big_buck_bunny_,640x360_400,640x360_700,640x360_1000,950x540_1500,.f4v.csmil/master.m3u8';
  static const String vrVideoUrl2 =
      'https://github.com/stephangopaul/video_samples/blob/master/gb.mp4?raw=true';
  static const String panoramaImageUrl1 =
      'https://image.shutterstock.com/z/stock-photo-connection-lines-around-earth-globe-futuristic-technology-theme-background-with-light-effect-d-549340267.jpg';
  static const String panoramaImageUrl2 =
      'https://image.shutterstock.com/z/stock-photo-connection-lines-around-earth-globe-futuristic-technology-theme-background-with-light-effect-d-549340267.jpg';

  // Spatial Tracking & Tri-Camera Inspector ValueKeys
  static const String keyTriCameraLiveInspectorCard =
      'vr_tri_camera_live_inspector_card';
  static const String keyToggleLiveCameraInspectorBtn =
      'toggle_live_camera_inspector_btn';
  static const String keySwitchInspectorCameraLensBtn =
      'switch_inspector_camera_lens_btn';
  static const String keySpatialInspectorStereoHudSwitch =
      'spatial_inspector_stereo_hud_switch';
  static const String keySettingsPassthroughMixSlider =
      'settings_passthrough_mix_slider';
  static const String keySettingsUserStatureSlider =
      'settings_user_stature_slider';
  static const String keySpatialInputBindingVerificationPanel =
      'spatial_input_binding_verification_panel';
  static const String keyVerifyBipedalWalkBtn = 'verify_bipedal_walk_btn';
  static const String keyVerify360ScanBtn = 'verify_360_scan_btn';
  static const String keyVerifyHandTofBtn = 'verify_hand_tof_btn';
  static const String keyVerifyAllChannelsBtn = 'verify_all_channels_btn';
  static const String keySpatialVerificationReportText =
      'spatial_verification_report_text';
  static const String keyStereoSpatialInspectorHud =
      'vr_stereo_spatial_inspector_hud';

  // Camera Role & Object Identifiers
  static const String cameraRoleFront = 'front';
  static const String cameraRoleFrontUpper = 'front_upper';
  static const String cameraRoleRear = 'rear';
  static const String cameraRoleRearFloor = 'rear_floor';
  static const String objectIdUserFootLeft = 'user_foot_left';
  static const String objectIdUserFootRight = 'user_foot_right';
  static const String objectIdUserHandsJoystick = 'user_hands_joystick';
  static const String objectIdVisorHandLive = 'visor_hand_live';

  // Default Spatial Inspector Numeric Parameters
  static const double defaultJoystickWaistHeightMeters = 1.05;
  static const double defaultSpeedOfSoundMetersPerSec = 343.2;
  static const double minStatureSliderMeters = 1.40;
  static const double maxStatureSliderMeters = 2.05;
  static const int passthroughVisionFrameIntervalUs = 140000;
}
