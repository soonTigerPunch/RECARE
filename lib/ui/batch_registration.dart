import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/inventory_repository.dart';
import '../domain/food_catalog.dart';
import '../domain/inventory.dart';
import '../domain/shopping.dart';
import 'design_system.dart';

class BatchRegistrationPage extends StatefulWidget {
  const BatchRegistrationPage({
    super.key,
    required this.repository,
    required this.clock,
    this.initialItems = const [],
  });
  final InventoryRepository repository;
  final DateTime Function() clock;
  final List<ShoppingItem> initialItems;
  @override
  State<BatchRegistrationPage> createState() => _BatchRegistrationPageState();
}

class _Draft {
  _Draft({
    String name = '',
    FoodUnit unit = FoodUnit.piece,
    int amount = 1000,
    this.shoppingId,
  }) : id = const Uuid().v4(),
       unit = _inputUnit(unit, amount),
       name = TextEditingController(text: name),
       quantity = TextEditingController(
         text: _inputUnit(unit, amount).quantityText(amount),
       );
  final String id;
  final String? shoppingId;
  final TextEditingController name, quantity;
  final price = TextEditingController();
  FoodUnit unit;
  DateTime? expiry;
  static FoodUnit _inputUnit(FoodUnit unit, int amount) => switch (unit) {
    FoodUnit.litre when amount % 1000 != 0 => FoodUnit.ml,
    FoodUnit.kilogram when amount % 1000 != 0 => FoodUnit.gram,
    _ => unit,
  };
  void dispose() {
    name.dispose();
    quantity.dispose();
    price.dispose();
  }
}

class _BatchRegistrationPageState extends State<BatchRegistrationPage> {
  final _form = GlobalKey<FormState>();
  final _drafts = <_Draft>[];
  List<Food> _history = [];
  bool _busy = false, _historyFailed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final item in widget.initialItems) {
      _drafts.add(
        _Draft(
          name: item.name,
          unit: item.unit,
          amount: item.amount,
          shoppingId: item.id,
        ),
      );
    }
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    try {
      final foods = await widget.repository.recentFoods();
      if (mounted) {
        setState(() {
          _history = foods;
          _historyFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  List<FoodSuggestion> get _choices {
    final seen = <String>{};
    return [
          for (final food in _history)
            FoodSuggestion(
              id: 'recent-${food.id}',
              name: food.name,
              unit: food.unit,
              amount: food.total,
              visual: foodVisualForName(food.name),
              origin: SuggestionOrigin.history,
            ),
          ...foodCatalog,
        ]
        .where(
          (s) => seen.add(
            '${normalizeFoodName(s.name)}|${s.unit.family}|${s.amount}',
          ),
        )
        .toList();
  }

  Future<void> _selectItems() async {
    final choices = _choices;
    final selected = <String>{};
    String query = '';
    final picked = await showModalBottomSheet<List<FoodSuggestion>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final matches = choices
              .where(
                (s) =>
                    normalizeFoodName(s.name)
                        .contains(normalizeFoodName(query)) ||
                    s.aliases.any(
                      (alias) =>
                          normalizeFoodName(alias)
                              .contains(normalizeFoodName(query)),
                    ),
              )
              .toList();
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: '이전 등록·기본 목록 검색',
                      ),
                      onChanged: (text) => setSheetState(() => query = text),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final item = matches[i];
                        return CheckboxListTile(
                          key: ValueKey('batch-choice-${item.id}'),
                          value: selected.contains(item.id),
                          title: Text(item.name),
                          subtitle: Text(
                            '${item.quantityLabel} · ${item.sourceLabel}',
                          ),
                          onChanged: (value) => setSheetState(() {
                            if (value == true) {
                              selected.add(item.id);
                            } else {
                              selected.remove(item.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: FilledButton(
                      key: const ValueKey('batch-choices-done'),
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(
                              choices
                                  .where((item) => selected.contains(item.id))
                                  .toList(),
                            ),
                      child: Text('${selected.length}개 선택 완료'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      for (final item in picked) {
        _drafts.add(
          _Draft(name: item.name, unit: item.inputUnit, amount: item.amount),
        );
      }
      _error = null;
    });
  }

  Future<void> _chooseDate(_Draft draft) async {
    final now = widget.clock();
    final selected = await showDatePicker(
      context: context,
      initialDate: draft.expiry ?? now,
      confirmText: '선택',
      cancelText: '취소',
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected != null && mounted) {
      setState(() {
        draft.expiry = civilDate(selected);
        _error = null;
      });
    }
  }

  void _changeUnit(_Draft draft, FoodUnit unit) {
    if (draft.unit == unit) return;
    int? amount;
    try {
      amount = draft.unit.parseQuantity(draft.quantity.text);
    } catch (_) {
      /* Keep invalid input for validation. */
    }
    setState(() {
      if (amount != null && draft.unit.family == unit.family) {
        draft.unit = _Draft._inputUnit(unit, amount);
        draft.quantity.text = draft.unit.quantityText(amount);
      } else {
        draft.unit = unit;
        if (amount != null) draft.quantity.text = '1';
      }
    });
  }

  Future<void> _save() async {
    if (_busy || _drafts.isEmpty || !_form.currentState!.validate()) return;
    if (_drafts.any((d) => d.expiry == null)) {
      setState(() => _error = '모든 재료의 소비기한을 선택해주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final foods = [
        for (final d in _drafts)
          Food(
            id: d.id,
            name: d.name.text,
            unit: d.unit,
            total: d.unit.parseQuantity(d.quantity.text),
            expiry: d.expiry!,
            price: parsePrice(d.price.text),
            created: widget.clock(),
          ),
      ];
      await widget.repository.saveBatch(
        foods,
        shoppingItemsByFoodId: {
          for (final d in _drafts)
            if (d.shoppingId != null) d.id: d.shoppingId!,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ArgumentError
              ? e.message.toString()
              : '등록하지 못했어요. 입력 내용을 확인하고 다시 시도해주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('한 번에 등록')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Space.lg,
            Space.lg,
            Space.lg,
            Space.lg + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('batch-save'),
                  onPressed: _busy || _drafts.isEmpty ? null : _save,
                  child: Text('${_drafts.length}개 재료 등록'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            key: const ValueKey('batch-page'),
            padding: const EdgeInsets.all(Space.lg),
            children: [
              const Text('장본 재료를 모아서 등록하세요. 소비기한과 실제 구매금액은 이번 구매 기준으로 입력해주세요.'),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('batch-select'),
                    onPressed: _busy ? null : _selectItems,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('목록에서 여러 개 선택'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('batch-manual'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _drafts.add(_Draft());
                            _error = null;
                          }),
                    icon: const Icon(Icons.add),
                    label: const Text('직접 추가'),
                  ),
                ],
              ),
              if (_historyFailed)
                TextButton(
                  onPressed: _busy ? null : _loadHistory,
                  child: const Text('이전 등록 이력 다시 불러오기'),
                ),
              if (_drafts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.xl),
                  child: Text('등록할 재료를 선택하거나 직접 추가해주세요.'),
                ),
              for (var i = 0; i < _drafts.length; i++)
                _draftCard(_drafts[i], i),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _draftCard(_Draft draft, int i) => Card(
    key: ValueKey(draft.id),
    margin: const EdgeInsets.symmetric(vertical: Space.sm),
    child: Padding(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '재료 ${i + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: ValueKey('batch-remove-$i'),
                tooltip: '이번 등록에서 빼기',
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _drafts.remove(draft);
                        draft.dispose();
                      }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          TextFormField(
            key: ValueKey('batch-name-$i'),
            controller: draft.name,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '식재료 이름'),
            validator: (value) =>
                value == null ||
                    value.trim().isEmpty ||
                    value.trim().length > 60
                ? '식재료 이름은 1~60자로 입력해주세요.'
                : null,
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            key: ValueKey('batch-quantity-$i'),
            controller: draft.quantity,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '등록 수량'),
            validator: (value) {
              try {
                draft.unit.parseQuantity(value ?? '');
                return null;
              } catch (e) {
                return e is ArgumentError
                    ? e.message.toString()
                    : '수량을 확인해주세요.';
              }
            },
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            children: [
              for (final unit in FoodUnit.values)
                ChoiceChip(
                  label: Text(unit.label),
                  selected: draft.unit == unit,
                  showCheckmark: false,
                  onSelected: _busy ? null : (_) => _changeUnit(draft, unit),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          OutlinedButton.icon(
            key: ValueKey('batch-expiry-${draft.shoppingId ?? draft.id}'),
            onPressed: _busy ? null : () => _chooseDate(draft),
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              draft.expiry == null
                  ? '소비기한 선택'
                  : '소비기한 ${dateText(draft.expiry!)}',
            ),
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            key: ValueKey('batch-price-$i'),
            controller: draft.price,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '전체 구매금액 (선택)',
              suffixText: '원',
              helperText: '비워두면 금액 미입력으로 저장합니다.',
            ),
            validator: (value) {
              try {
                parsePrice(value ?? '');
                return null;
              } catch (e) {
                return e is ArgumentError
                    ? e.message.toString()
                    : '금액을 확인해주세요.';
              }
            },
          ),
        ],
      ),
    ),
  );
}
