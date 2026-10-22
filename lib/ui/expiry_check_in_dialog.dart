import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/inventory_repository.dart';
import '../domain/expiry_check_in.dart';
import '../domain/inventory.dart';
import 'design_system.dart';

/// One review sheet, with independent answers for the currently recorded stock.
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
  final _answers = <String, CheckInAnswer>{};
  final _requests = <String, String>{};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _foods = List.of(widget.foods);
  }

  Future<void> _submit({bool skipAll = false}) async {
    if (_busy || _foods.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.answerExpiryCheckIns(
        today: widget.clock(),
        answers: [
          for (final food in _foods)
            (
              food: food,
              answer: skipAll
                  ? CheckInAnswer.skip
                  : _answers[food.id] ?? CheckInAnswer.skip,
              requestId: _requests.putIfAbsent(
                food.id,
                () => const Uuid().v4(),
              ),
            ),
        ],
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      try {
        final pending = await widget.repository.pendingExpiryCheckIns(
          widget.clock(),
        );
        if (!mounted) return;
        if (pending.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        final previous = {for (final food in _foods) food.id: food};
        setState(() {
          for (final food in pending) {
            final old = previous[food.id];
            if (old == null ||
                old.remaining != food.remaining ||
                old.expiry != food.expiry ||
                old.unit != food.unit) {
              _answers.remove(food.id);
              _requests.remove(food.id);
            }
          }
          final ids = pending.map((food) => food.id).toSet();
          _answers.removeWhere((id, _) => !ids.contains(id));
          _foods = pending;
        });
      } catch (_) {
        /* Keep answers and request identities for a safe retry. */
      }
      if (mounted) {
        setState(
          () => _error = e is ArgumentError
              ? '${e.message} 변경된 재료의 수량을 다시 선택해주세요.'
              : '저장하지 못했어요. 다시 시도하거나 이번에는 닫아주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _foodCard(Food food) {
    final days = food.expiry.difference(civilDate(widget.clock())).inDays;
    final deadline = days == 0
        ? '오늘까지'
        : days > 0
        ? '$days일 남음'
        : '${-days}일 지남';
    final unit = food.unit.compatible.first;
    final answer = _answers[food.id];
    final amount = answer?.amount(food.remaining);
    return Card(
      key: ValueKey('check-in-food-${food.id}'),
      margin: const EdgeInsets.only(top: Space.md),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(food.name, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '$deadline · 소비기한 ${dateText(food.expiry)}',
              key: ValueKey('check-in-deadline-${food.id}'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text('현재 남은 재고 ${unit.quantityText(food.remaining)} ${unit.label}'),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                for (final choice in CheckInAnswer.values.where(
                  (a) => a != CheckInAnswer.skip,
                ))
                  ChoiceChip(
                    key: ValueKey('check-in-${food.id}-${choice.name}'),
                    label: Text(choice.label),
                    selected: answer == choice,
                    onSelected: _busy || choice.amount(food.remaining) == 0
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              _answers[food.id] = choice;
                            } else {
                              _answers.remove(food.id);
                            }
                          }),
                  ),
              ],
            ),
            if (amount != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  '소비량 ${unit.quantityText(amount)} ${unit.label} · 남을 재고 ${unit.quantityText(food.remaining - amount)} ${unit.label}',
                ),
              ),
            if (answer == CheckInAnswer.none)
              const Text('재고를 유지하고 오늘 확인한 것으로 저장해요.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
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
          Text('확인할 재료 ${_foods.length}개 · 현재 남은 재고 기준'),
          const Text('이미 기록한 소비량은 제외하고 재료별로 골라주세요.'),
          const Text('선택하지 않은 재료는 오늘 건너뛰어요.'),
          for (final food in _foods) _foodCard(food),
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
        if (_busy) const LinearProgressIndicator(),
        TextButton(
          key: const ValueKey('check-in-skip-all'),
          onPressed: _busy ? null : () => _submit(skipAll: true),
          child: const Text('오늘 모두 건너뛰기'),
        ),
        FilledButton(
          key: const ValueKey('check-in-save'),
          onPressed: _busy || _answers.isEmpty ? null : _submit,
          child: Text('선택한 ${_answers.length}개 저장'),
        ),
      ],
    ),
  );
}
