import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recare/services/reminder_service.dart';
import 'package:recare/ui/reminder_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('recare/reminders_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, Object> saved;
  late bool granted;
  late bool failSave;
  late int permissionRequests;
  late ReminderService service;
  setUp(() {
    saved = {'enabled': false, 'hour': 19, 'minute': 0};
    granted = true;
    failSave = false;
    permissionRequests = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'loadSettings':
          return saved;
        case 'requestPermission':
          permissionRequests++;
          return granted;
        case 'configure':
          if (failSave) throw PlatformException(code: 'schedule_failed');
          saved = Map<String, Object>.from(call.arguments as Map);
          return null;
        case 'consumeOpenUrgent':
          return true;
      }
      throw MissingPluginException();
    });
    service = ReminderService(channel: channel, supported: true);
  });
  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('defaults and persisted local time survive bridge round trip', () async {
    final defaults = await service.loadSettings();
    expect(defaults.enabled, isFalse);
    expect(defaults.hour, 19);
    expect(defaults.minute, 0);
    await service.configure(
      const ReminderSettings(enabled: true, hour: 8, minute: 15),
    );
    final loaded = await service.loadSettings();
    expect(loaded.enabled, isTrue);
    expect(loaded.hour, 8);
    expect(loaded.minute, 15);
    expect(permissionRequests, 0);
  });
  test('denial and configuration errors reach caller', () async {
    granted = false;
    expect(await service.requestPermission(), isFalse);
    failSave = true;
    await expectLater(
      service.configure(const ReminderSettings(enabled: true)),
      throwsA(isA<PlatformException>()),
    );
    expect((await service.loadSettings()).enabled, isFalse);
  });
  test('invalid clock fields cannot cross native boundary', () async {
    await expectLater(
      service.configure(const ReminderSettings(hour: 24)),
      throwsArgumentError,
    );
    await expectLater(
      service.configure(const ReminderSettings(minute: -1)),
      throwsArgumentError,
    );
  });
  test('absent plugin never reports enabled', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect((await service.loadSettings()).enabled, isFalse);
    expect(service.isSupported, isFalse);
    expect(await service.requestPermission(), isFalse);
    expect(await service.consumeOpenUrgent(), isFalse);
    await expectLater(
      service.configure(const ReminderSettings(enabled: true)),
      throwsUnsupportedError,
    );
  });
  test('cold consumption and warm notification events are bridged', () async {
    expect(await service.consumeOpenUrgent(), isTrue);
    final event = expectLater(service.openUrgentRequests, emits(isNull));
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('openUrgent'),
      ),
      (ByteData? _) {},
    );
    await event;
  });
  Future<void> render(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: ReminderSettingsCard(service: service),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('permission only on enable; denial stays off and explains', (
    tester,
  ) async {
    granted = false;
    await render(tester);
    expect(permissionRequests, 0);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(permissionRequests, 1);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.textContaining('알림 권한'), findsOneWidget);
    expect(saved['enabled'], isFalse);
  });
  testWidgets('failed save leaves previous state and allows retry', (
    tester,
  ) async {
    await render(tester);
    failSave = true;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.textContaining('저장하지 못했어요'), findsOneWidget);
    failSave = false;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(saved['enabled'], isFalse);
    expect(permissionRequests, 2);
  });
  testWidgets('resume refreshes revocation; narrow large text fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    saved['enabled'] = true;
    await render(tester, scale: 2);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    saved['enabled'] = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
