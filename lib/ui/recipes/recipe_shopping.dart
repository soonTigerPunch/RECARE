import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/recipe_repository.dart';
import '../../domain/inventory.dart';
import '../../domain/recipes.dart';
import '../../domain/shopping.dart';
import '../design_system.dart';
import 'recipe_common.dart';

class _Purchase {
  _Purchase(this.ingredient)
    : unit = recipeEntryUnit(ingredient.unit ?? FoodUnit.piece),
      quantity = TextEditingController(
        text: ingredient.amount == null || ingredient.unit == null
            ? ''
            : recipeEntryUnit(ingredient.unit!)
                  .quantityText(ingredient.amount!),
      );
  final RecipeIngredient ingredient;
  FoodUnit unit;
  final TextEditingController quantity;
  bool selected = true;
}

class RecipeShoppingPage extends StatefulWidget {
  const RecipeShoppingPage({
    super.key,
    required this.recipe,
    required this.repository,
    required this.clock,
  });
  final Recipe recipe;
  final RecipeRepository repository;
  final DateTime Function() clock;
  @override
  State<RecipeShoppingPage> createState() => _RecipeShoppingPageState();
}

class _RecipeShoppingPageState extends State<RecipeShoppingPage> {
  late final purchases = widget.recipe.ingredients
      .where((i) => i.kind != RecipeIngredientKind.inventory)
      .map(_Purchase.new)
      .toList();
  final requestId = const Uuid().v4();
  List<ShoppingItem>? submitted;
  bool saving = false, completed = false;
  String? error, summary;
  @override
  void dispose() {
    for (final purchase in purchases) {
      purchase.quantity.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || completed) return;
    try {
      // Keep the exact same ID and payload when storage success is uncertain.
      final items =
          submitted ??
          purchases
              .where((p) => p.selected)
              .map(
                (p) => ShoppingItem(
                  id: const Uuid().v4(),
                  name: p.ingredient.name,
                  unit: p.unit,
                  amount: p.unit.parseQuantity(p.quantity.text),
                  created: widget.clock(),
                ),
              )
              .toList();
      require(items.isNotEmpty, '장보기에 추가할 항목을 선택해주세요.');
      setState(() {
        saving = true;
        error = null;
        submitted = items;
      });
      final result = await widget.repository.addShoppingBatch(requestId, items);
      if (!mounted) return;
      setState(() {
        completed = true;
        summary = '새로 추가 ${result.added}개 · 이미 있는 동일 항목 ${result.existing}개';
      });
    } catch (e) {
      if (mounted) setState(() => error = recipeError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('장보기 항목 확인')),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          const Text(
            '레시피 필요량을 참고해 실제 구매할 단위와 수량을 직접 확인해주세요. 기본 양념도 필요할 때 선택할 수 있어요.',
          ),
          const SizedBox(height: Space.md),
          const Text(
            '약간·큰술 같은 표현을 g/ml/개로 자동 환산하지 않아요. 무게·부피·개수 중 실제 구매 단위를 선택하고 정확한 수량을 입력해주세요.',
          ),
          if (purchases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: Text('이 레시피에는 추가 구매나 양념 항목이 없어요.'),
            ),
          for (final purchase in purchases)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(purchase.ingredient.name),
                      subtitle: Text(
                        '레시피 필요량: ${purchase.ingredient.displayQuantity}',
                      ),
                      value: purchase.selected,
                      onChanged: completed || submitted != null
                          ? null
                          : (v) =>
                                setState(() => purchase.selected = v ?? false),
                    ),
                    DropdownButtonFormField<FoodUnit>(
                      initialValue: purchase.unit,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '구매 단위'),
                      items: [
                        for (final unit in FoodUnit.values)
                          DropdownMenuItem(
                            value: unit,
                            child: Text(unit.label),
                          ),
                      ],
                      onChanged: completed || submitted != null
                          ? null
                          : (unit) => setState(() {
                              if (unit == null) return;
                              if (unit.family == purchase.unit.family &&
                                  purchase.quantity.text.trim().isNotEmpty) {
                                try {
                                  purchase.quantity.text = unit.quantityText(
                                    purchase.unit.parseQuantity(
                                      purchase.quantity.text,
                                    ),
                                  );
                                } catch (_) {
                                  purchase.quantity.clear();
                                }
                              } else {
                                purchase.quantity.clear();
                              }
                              purchase.unit = unit;
                            }),
                    ),
                    const SizedBox(height: Space.md),
                    TextField(
                      key: ValueKey('recipe-buy-${purchase.ingredient.name}'),
                      controller: purchase.quantity,
                      enabled:
                          purchase.selected && !completed && submitted == null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '구매 수량 (${purchase.unit.label})',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (summary != null)
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Text(summary!),
            ),
          if (saving)
            const LinearProgressIndicator(key: ValueKey('recipe-saving')),
        ],
      ),
      bottomNavigationBar: RecipeBottomAction(
        child: completed
            ? FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              )
            : FilledButton(
                key: const ValueKey('recipe-shopping-save'),
                onPressed: saving || purchases.isEmpty ? null : _save,
                child: Text(
                  saving
                      ? '전체 항목 저장 중…'
                      : submitted == null
                      ? '확인한 항목 장보기에 추가'
                      : '같은 추가 작업 다시 확인',
                ),
              ),
      ),
    ),
  );
}
