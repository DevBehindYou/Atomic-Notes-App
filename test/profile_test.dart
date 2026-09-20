// Profile: the bundled avatars, the avatar popup, the settings cards and the
// profile page. None of it needs Hive or the network.

import 'dart:io';

import 'package:atomic_notes/page/endpage/edit_profile_page.dart';
import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/utility/component/avatar_picker_dialog.dart';
import 'package:atomic_notes/utility/component/profile_avatar.dart';
import 'package:atomic_notes/utility/component/settings_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AvatarPickerDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() async {
    await ProfileStore.instance.setAvatar(null);
    await ProfileStore.instance.setPublicProfile(true);
  });

  group('avatars', () {
    test('there are 14, and every file is on disk and bundled', () {
      expect(Avatars.all.length, 14);
      expect(Avatars.all.toSet().length, 14);
      for (final path in Avatars.all) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
      // Nothing in the folder is left out of the list.
      final onDisk = Directory('assets/Avatars')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .length;
      expect(onDisk, Avatars.all.length);

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/Avatars/men/'));
      expect(pubspec, contains('- assets/Avatars/women/'));
    });
  });

  group('profile store', () {
    test('starts on the default photo', () {
      expect(ProfileStore.instance.avatarAsset, Avatars.defaultAsset);
      expect(ProfileStore.instance.hasCustomAvatar, isFalse);
    });

    test('keeps a chosen avatar, tells listeners, and resets', () async {
      int heard = 0;
      void listener() => heard++;
      ProfileStore.instance.addListener(listener);
      addTearDown(() => ProfileStore.instance.removeListener(listener));

      await ProfileStore.instance.setAvatar(Avatars.all[4]);
      expect(ProfileStore.instance.avatarAsset, Avatars.all[4]);
      expect(ProfileStore.instance.hasCustomAvatar, isTrue);
      expect(heard, 1);

      await ProfileStore.instance.setAvatar(null);
      expect(ProfileStore.instance.avatarAsset, Avatars.defaultAsset);
      expect(heard, 2);
    });

    test('ignores anything that is not a bundled avatar', () async {
      await ProfileStore.instance.setAvatar('assets/../secret.png');
      expect(ProfileStore.instance.avatarAsset, Avatars.defaultAsset);
    });

    test('public profile defaults on and can be switched', () async {
      expect(ProfileStore.instance.publicProfile, isTrue);
      await ProfileStore.instance.setPublicProfile(false);
      expect(ProfileStore.instance.publicProfile, isFalse);
    });
  });

  group('avatar popup', () {
    testWidgets('shows all 14, and tapping one sets it and closes',
        (tester) async {
      _phone(tester);
      await _openPicker(tester);

      for (final path in Avatars.all) {
        expect(find.byKey(ValueKey(path)), findsOneWidget, reason: path);
      }
      // No default-photo button until something else is chosen.
      expect(find.text('USE DEFAULT PHOTO'), findsNothing);

      await tester.tap(find.byKey(ValueKey(Avatars.all[5])));
      await tester.pumpAndSettle();

      expect(ProfileStore.instance.avatarAsset, Avatars.all[5]);
      expect(find.byType(AvatarPickerDialog), findsNothing);
    });

    testWidgets('marks the current avatar and can go back to the default',
        (tester) async {
      _phone(tester);
      await ProfileStore.instance.setAvatar(Avatars.all[2]);
      await _openPicker(tester);

      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('USE DEFAULT PHOTO'));
      await tester.pumpAndSettle();

      expect(ProfileStore.instance.avatarAsset, Avatars.defaultAsset);
      expect(find.byType(AvatarPickerDialog), findsNothing);
    });
  });

  testWidgets('the avatar widget follows the store', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfileAvatar(size: 64))),
    );
    String shown() =>
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName;

    expect(shown(), Avatars.defaultAsset);
    await ProfileStore.instance.setAvatar(Avatars.all[9]);
    await tester.pump();
    expect(shown(), Avatars.all[9]);
  });

  group('settings card', () {
    testWidgets('shows its title and caption and answers a tap',
        (tester) async {
      _phone(tester);
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: SettingsCard(
                      icon: Icons.person_outline,
                      title: 'Profile',
                      caption: 'Photo, name, 2FA',
                      onTap: () => taps++,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SettingsCard(
                      icon: Icons.cloud_sync_outlined,
                      title: 'Cloud Sync',
                      caption: 'Drive backup',
                      onTap: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('PROFILE'), findsOneWidget);
      expect(find.text('PHOTO, NAME, 2FA'), findsOneWidget);
      expect(find.text('CLOUD SYNC'), findsOneWidget);

      await tester.tap(find.text('PROFILE'));
      expect(taps, 1);
    });

    testWidgets('the wide danger card renders on its own row', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SettingsCard(
                icon: Icons.warning_amber_rounded,
                title: 'Danger Zone',
                caption: 'Wipe cloud or this device',
                danger: true,
                wide: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('DANGER ZONE'), findsOneWidget);
      expect(find.text('WIPE CLOUD OR THIS DEVICE'), findsOneWidget);
    });
  });

  group('profile page', () {
    Future<void> openPage(WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          routes: {'/twofactor': (_) => const Scaffold(body: Text('2FA PAGE'))},
          home: const EditProfilePage(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('lists account, privacy and security', (tester) async {
      await openPage(tester);

      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('PRIVACY & SECURITY'), findsOneWidget);
      expect(find.text('USERNAME'), findsOneWidget);
      expect(find.text('EMAIL'), findsOneWidget);
      expect(find.text('PUBLIC PROFILE'), findsOneWidget);
      expect(find.text('TWO-FACTOR AUTHENTICATION'), findsOneWidget);
      expect(find.text('CONNECTED ACCOUNTS'), findsOneWidget);
    });

    testWidgets('connected accounts shows Google and nothing else',
        (tester) async {
      await openPage(tester);

      expect(find.text('Google'), findsOneWidget);
      expect(find.text('GitHub'), findsNothing);
      expect(find.text('Discord'), findsNothing);
    });

    testWidgets('two-factor is off by default and its row opens the page',
        (tester) async {
      await openPage(tester);

      expect(find.text('Off'), findsOneWidget);
      await tester.ensureVisible(find.text('TWO-FACTOR AUTHENTICATION'));
      await tester.tap(find.text('TWO-FACTOR AUTHENTICATION'));
      await tester.pumpAndSettle();

      expect(find.text('2FA PAGE'), findsOneWidget);
    });

    testWidgets('the public profile switch is remembered', (tester) async {
      await openPage(tester);

      await tester.ensureVisible(find.byType(CupertinoSwitch));
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();

      expect(ProfileStore.instance.publicProfile, isFalse);
    });

    testWidgets('the camera badge opens the avatar popup', (tester) async {
      await openPage(tester);

      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(AvatarPickerDialog), findsOneWidget);
    });
  });
}
