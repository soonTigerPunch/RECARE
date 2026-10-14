import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:recare/data/preferences.dart';

void main() {
  late Directory temp;
  late String filePath;
  late PreferencesStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recare-preferences-test-');
    filePath = p.join(temp.path, 'recare_preferences.json');
    store = PreferencesStore(filePath);
  });

  tearDown(() async {
    if (!p.isWithin(
      Directory.systemTemp.resolveSymbolicLinksSync(),
      temp.resolveSymbolicLinksSync(),
    )) {
      throw StateError('Unexpected temporary directory');
    }
    await temp.delete(recursive: true);
  });

  test('missing file loads defaults without creating a file', () async {
    final preferences = await store.load();
    expect(preferences.appearance, AppAppearance.system);
    expect(preferences.includeFinished, isFalse);
    expect(await File(filePath).exists(), isFalse);
  });

  test(
    'new store instance restores appearance and finished visibility',
    () async {
      await store.save(
        const AppPreferences(
          appearance: AppAppearance.dark,
          includeFinished: true,
        ),
      );
      final restored = await PreferencesStore(filePath).load();
      expect(restored.appearance, AppAppearance.dark);
      expect(restored.includeFinished, isTrue);
    },
  );

  test('invalid JSON and non-object values safely load defaults', () async {
    for (final content in ['{', 'null', '[]', '42', '"dark"']) {
      await File(filePath).writeAsString(content);
      final preferences = await store.load();
      expect(preferences.appearance, AppAppearance.system);
      expect(preferences.includeFinished, isFalse);
    }
  });

  test(
    'invalid fields fall back individually while valid fields survive',
    () async {
      await File(filePath)
          .writeAsString('{"appearance":"unknown","includeFinished":true}');
      final invalidAppearance = await store.load();
      expect(invalidAppearance.appearance, AppAppearance.system);
      expect(invalidAppearance.includeFinished, isTrue);

      await File(filePath)
          .writeAsString('{"appearance":"light","includeFinished":"true"}');
      final invalidVisibility = await store.load();
      expect(invalidVisibility.appearance, AppAppearance.light);
      expect(invalidVisibility.includeFinished, isFalse);

      await File(filePath).writeAsString('{}');
      final missingFields = await store.load();
      expect(missingFields.appearance, AppAppearance.system);
      expect(missingFields.includeFinished, isFalse);
    },
  );

  test(
    'changing settings replaces an existing file and keeps input immutable',
    () async {
      const original = AppPreferences(
        appearance: AppAppearance.dark,
        includeFinished: true,
      );
      await store.save(original);
      await store.save(
        original.copyWith(
          appearance: AppAppearance.light,
          includeFinished: false,
        ),
      );
      final restored = await PreferencesStore(filePath).load();
      expect(restored.appearance, AppAppearance.light);
      expect(restored.includeFinished, isFalse);
      expect(original.appearance, AppAppearance.dark);
      expect(original.includeFinished, isTrue);
    },
  );

  test('rapid saves persist the last requested settings', () async {
    final first = store.save(
      const AppPreferences(appearance: AppAppearance.dark),
    );
    final second = store.save(
      const AppPreferences(appearance: AppAppearance.light),
    );
    final last = store.save(const AppPreferences(includeFinished: true));
    await Future.wait([first, second, last]);
    final restored = await PreferencesStore(filePath).load();
    expect(restored.appearance, AppAppearance.system);
    expect(restored.includeFinished, isTrue);
  });

  test('a failed save reports failure and allows a later retry', () async {
    final blockedDestination = Directory(filePath);
    await blockedDestination.create();
    await expectLater(
      store.save(const AppPreferences(appearance: AppAppearance.dark)),
      throwsA(isA<FileSystemException>()),
    );
    expect(await blockedDestination.exists(), isTrue);
    await blockedDestination.delete();
    await store.save(const AppPreferences(appearance: AppAppearance.light));
    expect((await store.load()).appearance, AppAppearance.light);
    final files = await temp.list().toList();
    expect(files.map((entry) => p.basename(entry.path)), [
      'recare_preferences.json',
    ]);
  });

  test(
    'settings persistence leaves the inventory database untouched',
    () async {
      final database = File(p.join(temp.path, 'recare.db'));
      const contents = [83, 81, 76, 105, 116, 101, 0, 255];
      await database.writeAsBytes(contents);
      await store.save(const AppPreferences(appearance: AppAppearance.dark));
      await store.load();
      expect(await database.readAsBytes(), contents);
    },
  );
}
