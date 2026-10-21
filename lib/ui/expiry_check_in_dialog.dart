import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/inventory_repository.dart';
import '../domain/expiry_check_in.dart';
import '../domain/inventory.dart';
import 'design_system.dart';

/// Answers describe additional consumption from the currently recorded stock.
class ExpiryCheckInDialog extends StatefulWidget {
  const ExpiryCheckInDialog({
    super.key,
    required this.repository,
    required this.foods,
    required this.clock,
  });
  final InventoryRepository repository;
  final List<Food> foods;
  final DateTime Function() clock;
  @override
  State<ExpiryCheckInDialog> createState() => _ExpiryCheckInDialogState();
}

class _ExpiryCheckInDialogState extends State<ExpiryCheckInDialog> {
  late List<Food> _foods;
  CheckInAnswer? _answer;
  String _requestId = const Uuid().v4();
  bool _busy = false;
  int _handled = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _foods = List.of(widget.foods);
  }

  Future<void> _submit(CheckInAnswer answer, {bool all = false}) async {
    if (_busy || _foods.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final targets = all ? List<Food>.of(_foods) : [_foods.first];
      for (final food in targets) {
        final saved = await widget.repository.answerExpiryCheckIn(
          food: food,
          today: widget.clock(),
          answer: answer,
          requestId: all ? const Uuid().v4() : _requestId,
        );
        if (saved) _handled++;
      }
      final pending = await widget.repository.pendingExpiryCheckIns(
        widget.clock(),
      );
      if (!mounted) return;
      if (pending.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _foods = pending;
        _answer = null;
        _requestId = const Uuid().v4();
      });
    } catch (e) {
      // Reload stale stock before allowing another fraction to be submitted.
      try {
        final pending = await widget.repository.pendingExpiryCheckIns(
          widget.clock(),
        );
        if (!mounted) return;
        if (pending.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        setState(() {
          _foods = pending;
          _answer = null;
          _requestId = const Uuid().v4();
        });
      } catch (_) {
        /* Keep the original selection and request identity for retry. */
      }
      if (mounted) {
        setState(
          () => _error = e is ArgumentError
              ? '${e.message} 최신 수량을 확인하고 다시 선택해주세요.'
              : '저장하지 못했어요. 다시 시도하거나 이번에는 닫아주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final food = _foods.first;
    final days = food.expiry.difference(civilDate(widget.clock())).inDays;
    final unit = food.unit.compatible.first;
    final amount = _answer?.amount(food.remaining);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        key: const ValueKey('expiry-check-in'),
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.xl,
        ),
        title: const Text('이 식재료의 소비기한이 임박했어요! 얼마나 소비하셨나요?'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_handled + 1} / ${_handled + _foods.length} · ${days == 0 ? '소비기한 당일' : '소비기한 $days일 전'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Space.sm),
            Text(food.name, style: Theme.of(context).textTheme.titleLarge),
            Text('현재 남은 재고 ${unit.quantityText(food.remaining)} ${unit.label}'),
            const SizedBox(height: Space.md),
            const Text('앱에 남아 있는 재고 중 이번에 소비한 양을 골라주세요. 이미 기록한 소비량은 제외해주세요.'),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final answer in CheckInAnswer.values.where(
                  (a) => a != CheckInAnswer.skip,
                ))
                  ChoiceChip(
                    key: ValueKey('check-in-${answer.name}'),
                    label: Text(answer.label),
                    selected: _answer == answer,
                    onSelected: _busy || answer.amount(food.remaining) == 0
                        ? null
                        : (_) => setState(() => _answer = answer),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            if (amount != null)
              Text(
                '소비량 ${unit.quantityText(amount)} ${unit.label} · 남을 재고 ${unit.quantityText(food.remaining - amount)} ${unit.label}',
              ),
            if (_answer == CheckInAnswer.none)
              const Text('재고 수량을 유지하고 오늘 확인한 것으로 저장해요.'),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('이번에는 닫기'),
              ),
            ],
          ],
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            key: const ValueKey('check-in-skip-all'),
            onPressed: _busy
                ? null
                : () => _submit(CheckInAnswer.skip, all: true),
            child: const Text('오늘 모두 건너뛰기'),
          ),
          TextButton(
            key: const ValueKey('check-in-skip'),
            onPressed: _busy ? null : () => _submit(CheckInAnswer.skip),
            child: const Text('건너뛰기'),
          ),
          FilledButton(
            key: const ValueKey('check-in-save'),
            onPressed: _busy || _answer == null
                ? null
                : () => _submit(_answer!),
            child: const Text('확인 저장'),
          ),
        ],
      ),
    );
  }
}
