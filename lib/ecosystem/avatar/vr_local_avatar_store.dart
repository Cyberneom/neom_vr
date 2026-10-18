import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

/// Device-local drafts, partitioned by the host's account/profile identity.
/// These preferences are not an authentication token or a public avatar feed.
class VrLocalAvatarStore {
  VrLocalAvatarStore({Future<SharedPreferences> Function()? open})
    : _open = open ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _open;
  Future<void> _writing = Future<void>.value();

  String _key(String owner) =>
      'vrlizate.avatar.v1.${base64Url.encode(utf8.encode(owner))}';

  Future<VrAvatarProfile> read({
    required String owner,
    required String profileId,
  }) async {
    await _writing;
    final store = await _open();
    final raw = store.getString(_key(owner));
    if (raw == null) return VrAvatarProfile(profileId: profileId);
    final value = VrAvatarProfile.fromJson(
      Map<String, Object?>.from(jsonDecode(raw) as Map),
    );
    if (value.profileId != profileId) {
      throw const FormatException('Avatar belongs to a different profile.');
    }
    return value;
  }

  Future<void> write({
    required String owner,
    required VrAvatarProfile value,
    required bool Function() isCurrent,
  }) {
    final operation = _writing.then((_) async {
      if (!isCurrent()) throw StateError('Avatar session changed.');
      final store = await _open();
      if (!isCurrent()) throw StateError('Avatar session changed.');
      final saved = await store.setString(
        _key(owner),
        jsonEncode(value.toJson()),
      );
      if (!saved) throw StateError('Avatar storage failed.');
      if (!isCurrent()) throw StateError('Avatar session changed.');
    });
    _writing = operation.catchError((Object _) {});
    return operation;
  }
}
