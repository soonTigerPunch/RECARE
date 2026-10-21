import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.hour = 19,
    this.minute = 0,
  });

  final bool enabled;
  final int hour;
  final int minute;

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );
}

/// The Android boundary owns persistence, permission checks and scheduling.
class ReminderService {
  ReminderService({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('com.detabev.recare/reminders'),
      _supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (_supported) _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  bool _supported;
  final _openUrgent = StreamController<void>.broadcast();
  bool get isSupported => _supported;
  Stream<void> get openUrgentRequests => _openUrgent.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'openUrgent' && await consumeOpenUrgent()) {
      if (!_openUrgent.isClosed) _openUrgent.add(null);
    }
  }

  Future<ReminderSettings> loadSettings() async {
    if (!_supported) return const ReminderSettings();
    try {
      final values = await _channel.invokeMapMethod<String, dynamic>(
        'loadSettings',
      );
      if (values == null) return const ReminderSettings();
      final hour = values['hour'];
      final minute = values['minute'];
      if (hour is! int ||
          minute is! int ||
          hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59) {
        throw const FormatException('알림 시간을 확인할 수 없어요.');
      }
      return ReminderSettings(
        enabled: values['enabled'] == true,
        hour: hour,
        minute: minute,
      );
    } on MissingPluginException {
      _supported = false;
      return const ReminderSettings();
    }
  }

  Future<bool> requestPermission() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      _supported = false;
      return false;
    }
  }

  Future<void> configure(ReminderSettings settings) async {
    if (settings.hour < 0 ||
        settings.hour > 23 ||
        settings.minute < 0 ||
        settings.minute > 59) {
      throw ArgumentError('알림 시간을 확인해주세요.');
    }
    if (!_supported) throw UnsupportedError('Android에서 알림을 설정할 수 있어요.');
    try {
      await _channel.invokeMethod<void>('configure', {
        'enabled': settings.enabled,
        'hour': settings.hour,
        'minute': settings.minute,
      });
    } on MissingPluginException {
      _supported = false;
      throw UnsupportedError('이 환경에서는 알림을 설정할 수 없어요.');
    }
  }

  Future<bool> consumeOpenUrgent() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('consumeOpenUrgent') ?? false;
    } on MissingPluginException {
      _supported = false;
      return false;
    }
  }

  void dispose() {
    if (_supported) _channel.setMethodCallHandler(null);
    _openUrgent.close();
  }
}
