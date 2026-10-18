import 'package:firebase_core/firebase_core.dart';

/// Explicit backend selection. Importing this file never initializes Firebase.
/// No Open Neom application defaults or native auto-discovery are used.
class VrEcosystemFirebaseConfig {
  const VrEcosystemFirebaseConfig({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    this.authDomain,
    this.storageBucket,
    this.iosBundleId,
  });

  const VrEcosystemFirebaseConfig.fromEnvironment()
    : apiKey = const String.fromEnvironment('VRLIZATE_FIREBASE_API_KEY'),
      appId = const String.fromEnvironment('VRLIZATE_FIREBASE_APP_ID'),
      messagingSenderId = const String.fromEnvironment(
        'VRLIZATE_FIREBASE_MESSAGING_SENDER_ID',
      ),
      projectId = const String.fromEnvironment('VRLIZATE_FIREBASE_PROJECT_ID'),
      authDomain = const String.fromEnvironment(
        'VRLIZATE_FIREBASE_AUTH_DOMAIN',
      ),
      storageBucket = const String.fromEnvironment(
        'VRLIZATE_FIREBASE_STORAGE_BUCKET',
      ),
      iosBundleId = const String.fromEnvironment(
        'VRLIZATE_FIREBASE_IOS_BUNDLE_ID',
      );

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String? authDomain;
  final String? storageBucket;
  final String? iosBundleId;

  bool get isComplete => [
    apiKey,
    appId,
    messagingSenderId,
    projectId,
  ].every((value) => value.isNotEmpty && value == value.trim());

  FirebaseOptions get options {
    if (!isComplete) throw StateError('VRlizate backend is not configured.');
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: _optional(authDomain),
      storageBucket: _optional(storageBucket),
      iosBundleId: _optional(iosBundleId),
    );
  }

  bool matches(FirebaseOptions other) =>
      isComplete &&
      other.projectId == projectId &&
      other.appId == appId &&
      other.apiKey == apiKey &&
      other.messagingSenderId == messagingSenderId &&
      _optional(other.authDomain) == _optional(authDomain) &&
      _optional(other.storageBucket) == _optional(storageBucket) &&
      _optional(other.iosBundleId) == _optional(iosBundleId);

  static String? _optional(String? value) =>
      value == null || value.isEmpty ? null : value;
}
