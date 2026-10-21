import 'package:flutter/material.dart';

import '../services/reminder_service.dart';
import 'design_system.dart';

class ReminderSettingsCard extends StatefulWidget {
  const ReminderSettingsCard({super.key, required this.service});
  final ReminderService service;

  @override
  State<ReminderSettingsCard> createState() => _ReminderSettingsCardState();
}

class _ReminderSettingsCardState extends State<ReminderSettingsCard>
    with WidgetsBindingObserver {
  ReminderSettings _settings = const ReminderSettings();
  bool _busy = true;
  bool _loaded = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final settings = await widget.service.loadSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loaded = true;
        _message = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loaded = false;
        _message = '알림 설정을 확인하지 못했어요. 다시 시도해주세요.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(ReminderSettings next) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (next.enabled && !_settings.enabled) {
        final granted = await widget.service.requestPermission();
        if (!granted) {
          if (mounted) {
            setState(
              () => _message = '알림 권한이 필요해요. 기기 설정에서 RE:CARE 알림을 허용한 뒤 켜주세요.',
            );
          }
          return;
        }
      }
      await widget.service.configure(next);
      final saved = await widget.service.loadSettings();
      if (mounted) {
        setState(() {
          _settings = saved;
          _loaded = true;
        });
      }
    } catch (_) {
      // The scheduler may have rolled back; always show the native persisted state.
      try {
        final saved = await widget.service.loadSettings();
        if (mounted) setState(() => _settings = saved);
      } catch (_) {
        if (mounted) setState(() => _loaded = false);
      }
      if (mounted) setState(() => _message = '알림 설정을 저장하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _settings.hour, minute: _settings.minute),
      helpText: '매일 알림 시간',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (value != null && mounted) {
      await _save(_settings.copyWith(hour: value.hour, minute: value.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = widget.service.isSupported;
    final available = supported && _loaded && !_busy;
    final time = TimeOfDay(
      hour: _settings.hour,
      minute: _settings.minute,
    ).format(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('소비기한 알림'),
              subtitle: const Text(
                '소비기한 3일 전, 1일 전, 당일에 남은 식재료를 알려드려요. '
                '앱을 열면 팝업에서 소비한 수량을 기록할 수 있어요.',
              ),
              value: _loaded && _settings.enabled,
              onChanged: available
                  ? (value) => _save(_settings.copyWith(enabled: value))
                  : null,
            ),
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              onPressed: available ? _pickTime : null,
              icon: const Icon(Icons.schedule),
              label: Text('알림 시간 $time', textAlign: TextAlign.center),
            ),
            const SizedBox(height: Space.sm),
            Text(
              supported
                  ? '기기의 절전 상태에 따라 알림이 늦게 도착할 수 있어요.'
                  : '매일 알림은 Android 앱에서 사용할 수 있어요.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: Space.md),
                child: LinearProgressIndicator(),
              ),
            if (_message != null) ...[
              const SizedBox(height: Space.md),
              Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (!_loaded && !_busy)
                TextButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }
}
