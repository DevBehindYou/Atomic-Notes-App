import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

/// The profile pictures bundled with the app (assets/Avatars).
class Avatars {
  Avatars._();

  /// Shown until the user picks one.
  static const String defaultAsset = 'assets/photo.png';

  static const List<String> all = [
    'assets/Avatars/men/man_01_short_dark_hair.png',
    'assets/Avatars/men/man_02_blond_quiff.png',
    'assets/Avatars/men/man_03_ginger_freckles.png',
    'assets/Avatars/men/man_04_curly_afro.png',
    'assets/Avatars/men/man_05_bearded_plaid.png',
    'assets/Avatars/men/man_06_glasses_blazer.png',
    'assets/Avatars/men/man_07_beanie.png',
    'assets/Avatars/women/woman_01_long_chestnut.png',
    'assets/Avatars/women/woman_02_blonde_bob.png',
    'assets/Avatars/women/woman_03_black_hair_bangs.png',
    'assets/Avatars/women/woman_04_red_wavy_freckles.png',
    'assets/Avatars/women/woman_05_lavender_pixie.png',
    'assets/Avatars/women/woman_06_space_buns.png',
    'assets/Avatars/women/woman_07_bun_and_glasses.png',
  ];

  static bool isKnown(String? asset) => asset != null && all.contains(asset);
}

/// Profile choices kept on this device: the picture, and the Public Profile
/// switch.
///
/// Neither is sent to the server. The picture is one of the bundled avatars, so
/// only its name is stored, per account, in a small Hive box. Until [init] has
/// run (as in widget tests) the values are held in memory instead.
class ProfileStore extends ChangeNotifier {
  ProfileStore._();

  static final ProfileStore instance = ProfileStore._();

  static const String boxName = 'profileBox';

  Box<dynamic>? _box;
  final Map<String, dynamic> _memory = {};

  Future<void> init() async {
    _box = await Hive.openBox<dynamic>(boxName);
  }

  String get _who => ApiClient.instance.currentUserId ?? 'device';
  String get _avatarKey => 'avatar.$_who';
  String get _publicKey => 'public.$_who';

  dynamic _get(String key) => _box != null ? _box!.get(key) : _memory[key];

  Future<void> _put(String key, dynamic value) async {
    if (_box != null) {
      await _box!.put(key, value);
    } else {
      _memory[key] = value;
    }
  }

  Future<void> _remove(String key) async {
    if (_box != null) {
      await _box!.delete(key);
    } else {
      _memory.remove(key);
    }
  }

  /// The asset to draw: the chosen avatar, or the default photo.
  String get avatarAsset {
    final Object? saved = _get(_avatarKey);
    return saved is String && Avatars.isKnown(saved)
        ? saved
        : Avatars.defaultAsset;
  }

  bool get hasCustomAvatar => avatarAsset != Avatars.defaultAsset;

  /// Pass null to go back to the default photo. Anything that is not one of
  /// the bundled avatars is ignored.
  Future<void> setAvatar(String? asset) async {
    if (asset == null) {
      await _remove(_avatarKey);
    } else if (Avatars.isKnown(asset)) {
      await _put(_avatarKey, asset);
    } else {
      return;
    }
    notifyListeners();
  }

  /// A display-only switch: it changes nothing else in the app.
  bool get publicProfile {
    final Object? saved = _get(_publicKey);
    return saved is bool ? saved : true;
  }

  Future<void> setPublicProfile(bool value) async {
    await _put(_publicKey, value);
    notifyListeners();
  }
}
