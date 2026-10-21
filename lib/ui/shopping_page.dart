import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/inventory_repository.dart';
import '../domain/inventory.dart';
import '../domain/shopping.dart';
import 'batch_registration.dart';
import 'design_system.dart';

class ShoppingPage extends StatefulWidget {
  const ShoppingPage({
    super.key,
    required this.repository,
    required this.clock,
  });
  final InventoryRepository repository;
  final DateTime Function() clock;

  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  List<ShoppingItem> _items = [];
  List<Food> _foods = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final items = await widget.repository.loadShoppingList();
      final snapshot = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _foods = snapshot.foods;
        _selected.retainAll(items.map((item) => item.id));
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '장보기 목록을 불러오지 못했어요. 다시 시도해주세요.';
      });
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _ShoppingItemDialog(
        repository: widget.repository,
        clock: widget.clock,
      ),
    );
    if (!mounted || message == null) return;
    setState(() => _busy = true);
    await _reload();
    if (mounted) {
      _message(message);
      setState(() => _busy = false);
    }
  }

  Future<void> _remove(ShoppingItem item) async {
    setState(() => _busy = true);
    try {
      await widget.repository.removeShoppingItem(item.id);
      await _reload();
    } catch (_) {
      if (mounted) _message('항목을 삭제하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkout() async {
    final selected = _items
        .where((item) => _selected.contains(item.id))
        .toList();
    if (selected.isEmpty) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BatchRegistrationPage(
          repository: widget.repository,
          clock: widget.clock,
          initialItems: selected,
        ),
      ),
    );
    if (!mounted) return;
    // The batch transaction alone removes purchased entries. Cancelled or
    // failed registrations leave both the stored list and selection intact.
    await _reload();
  }

  int _onHand(ShoppingItem item) => _foods
      .where(
        (food) =>
            normalizedShoppingName(food.name) ==
                normalizedShoppingName(item.name) &&
            food.unit.family == item.unit.family &&
            food.remaining > 0,
      )
      .fold(0, (amount, food) => amount + food.remaining);

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('shopping-page'),
    appBar: AppBar(title: const Text('장보기 목록')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.xl,
              vertical: Space.md,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('shopping-add'),
                onPressed: _busy || _loading ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('장볼 재료 추가'),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.xl,
                      vertical: Space.md,
                    ),
                    children: [
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _reload,
                          child: const Text('다시 시도'),
                        ),
                      ],
                      if (_items.isEmpty && _error == null) ...[
                        const SizedBox(height: Space.xxl),
                        const Icon(Icons.shopping_basket_outlined, size: 40),
                        const SizedBox(height: Space.lg),
                        const Text(
                          '장보기 목록이 비어 있어요.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_items.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: Space.lg),
                          child: Text('구매한 재료를 선택하고 소비기한을 확인해 등록하세요.'),
                        ),
                      for (final item in _items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: Card(
                            key: ValueKey('shopping-item-${item.id}'),
                            child: Padding(
                              padding: const EdgeInsets.all(Space.sm),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    key: ValueKey('shopping-select-${item.id}'),
                                    semanticLabel: '${item.name} 구매 선택',
                                    value: _selected.contains(item.id),
                                    onChanged: _busy
                                        ? null
                                        : (value) => setState(() {
                                            if (value == true) {
                                              _selected.add(item.id);
                                            } else {
                                              _selected.remove(item.id);
                                            }
                                          }),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: Space.md,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                          const SizedBox(height: Space.xs),
                                          Text(
                                            '장볼 수량 ${item.unit.quantityText(item.amount)} ${item.unit.label}',
                                          ),
                                          Text(
                                            '현재 재고 ${item.unit.quantityText(_onHand(item))} ${item.unit.label}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey('shopping-remove-${item.id}'),
                                    tooltip: '${item.name} 삭제',
                                    onPressed: _busy
                                        ? null
                                        : () => _remove(item),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: FilledButton(
          key: const ValueKey('shopping-checkout'),
          onPressed: _busy || _loading || _error != null || _selected.isEmpty
              ? null
              : _checkout,
          child: Text(
            _selected.isEmpty
                ? '구매한 재료 등록'
                : '구매한 재료 등록 (${_selected.length}개)',
          ),
        ),
      ),
    ),
  );
}

class _ShoppingItemDialog extends StatefulWidget {
  const _ShoppingItemDialog({required this.repository, required this.clock});
  final InventoryRepository repository;
  final DateTime Function() clock;
  @override
  State<_ShoppingItemDialog> createState() => _ShoppingItemDialogState();
}

class _ShoppingItemDialogState extends State<_ShoppingItemDialog> {
  final _name = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _form = GlobalKey<FormState>();
  FoodUnit _unit = FoodUnit.piece;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final item = ShoppingItem(
        id: const Uuid().v4(),
        name: _name.text,
        unit: _unit,
        amount: _unit.parseQuantity(_quantity.text),
        created: widget.clock(),
      );
      await widget.repository.addShoppingItem(item);
      final persisted = await widget.repository.loadShoppingList();
      final added = persisted.any((entry) => entry.id == item.id);
      if (mounted) {
        Navigator.of(context)
            .pop(added ? '장보기 목록에 추가했어요.' : '같은 항목이 이미 장보기 목록에 있어요.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ArgumentError
              ? error.message.toString()
              : '저장하지 못했어요. 입력한 내용을 유지했으니 다시 시도해주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('장볼 재료 추가'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              TextFormField(
                key: const ValueKey('shopping-name'),
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '식재료 이름'),
                validator: (value) =>
                    value == null ||
                        value.trim().isEmpty ||
                        value.trim().length > 60
                    ? '식재료 이름은 1~60자로 입력해주세요.'
                    : null,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                key: const ValueKey('shopping-quantity'),
                controller: _quantity,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '장볼 수량'),
                validator: (value) {
                  try {
                    _unit.parseQuantity(value ?? '');
                    return null;
                  } on ArgumentError catch (error) {
                    return error.message.toString();
                  }
                },
              ),
              const SizedBox(height: Space.lg),
              DropdownButtonFormField<FoodUnit>(
                key: const ValueKey('shopping-unit'),
                initialValue: _unit,
                decoration: const InputDecoration(labelText: '단위'),
                items: [
                  for (final unit in FoodUnit.values)
                    DropdownMenuItem(value: unit, child: Text(unit.label)),
                ],
                onChanged: _busy
                    ? null
                    : (unit) {
                        if (unit != null) setState(() => _unit = unit);
                      },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.md),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const ValueKey('shopping-save'),
          onPressed: _busy ? null : _save,
          child: const Text('추가'),
        ),
      ],
    ),
  );
}
