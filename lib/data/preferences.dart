import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum AppAppearance { system, light, dark }

class AppPreferences {
  const AppPreferences({
    this.appearance = AppAppearance.system,
    this.includeFinished = false,
  });

  final AppAppearance appearance;
  final bool includeFinished;

  AppPreferences copyWith({AppAppearance? appearance, bool? includeFinished}) =>
      AppPreferences(
        appearance: appearance ?? this.appearance,
        includeFinished: includeFinished ?? this.includeFinished,
      );

  static AppPreferences _decode(Object? value) {
    if (value is! Map<String, dynamic>) return const AppPreferences();
    return AppPreferences(
      appearance: switch (value['appearance']) {
        'light' => AppAppearance.light,
        'dark' => AppAppearance.dark,
        _ => AppAppearance.system,
      },
      includeFinished: value['includeFinished'] == true,
    );
  }

  Map<String, Object> _encode() => {
    'appearance': appearance.name,
    'includeFinished': includeFinished,
  };
}

class PreferencesStore {
  PreferencesStore(String filePath) : _file = File(filePath);

  final File _file;
  Future<void> _saveTail = Future<void>.value();
  static int _temporaryId = 0;

  static Future<PreferencesStore> open() async => PreferencesStore(
    p.join(await getDatabasesPath(), 'recare_preferences.json'),
  );

  Future<AppPreferences> load() async {
    await _saveTail;
    try {
      return AppPreferences._decode(jsonDecode(await _file.readAsString()));
    } on FileSystemException {
      return const AppPreferences();
    } on FormatException {
      return const AppPreferences();
    }
  }

  Future<void> save(AppPreferences preferences) {
    final operation = _saveTail.then((_) => _write(preferences));
    // A failed write is reported to its caller without blocking later changes.
    _saveTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _write(AppPreferences preferences) async {
    await _file.parent.create(recursive: true);
    final temporary = File(
      p.join(
        _file.parent.path,
        '.${p.basename(_file.path)}.$pid.'
        '${DateTime.now().microsecondsSinceEpoch}.${_temporaryId++}.tmp',
      ),
    );
    try {
      await temporary.writeAsString(
        jsonEncode(preferences._encode()),
        flush: true,
      );
      // Rename replaces the destination after the entire new file is written.
      await temporary.rename(_file.path);
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Cleanup must not mask the original save result.
      }
    }
  }
}
