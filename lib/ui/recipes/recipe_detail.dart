import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/inventory_repository.dart';
import '../../data/recipe_repository.dart';
import '../../domain/inventory.dart';
import '../../domain/recipes.dart';
import '../design_system.dart';
import 'recipe_common.dart';
import 'recipe_shopping.dart';

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({
    super.key,
    required this.recipe,
    required this.inventory,
    required this.repository,
    required this.favorites,
    required this.clock,
    required this.onRecommend,
    this.saved = false,
  });
  final Recipe recipe;
  final InventoryRepository inventory;
  final RecipeRepository repository;
  final RecipeFavorites favorites;
  final DateTime Function() clock;
  final VoidCallback onRecommend;
  final bool saved;
  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage>
    with WidgetsBindingObserver {
  List<Food> foods = [];
  CookingOperation? operation;
  bool loading = true, busy = false;
  String? error;
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
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await widget.inventory.load();
      final latest = await widget.repository.latestCooking(widget.recipe.id);
      if (mounted) {
        setState(() {
          foods = snapshot.foods;
          operation = latest;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = recipeError(e);
          loading = false;
        });
      }
    }
  }

  Future<void> _cook() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      // A previous save may have succeeded even when the screen closed early.
      final latest = await widget.repository.latestCooking(widget.recipe.id);
      if (!mounted) return;
      final completed =
          latest?.state == 'completed' || latest?.state == 'undone';
      if (completed &&
          !await recipeConfirm(
            context,
            '새 조리 회차를 시작할까요?',
            '이전 회차는 기록을 완료하거나 실행 취소했어요. 실제로 다시 만든 경우에만 새 먹음 기록을 저장해주세요.',
            action: '새 회차 시작',
          )) {
        return;
      }
      if (!mounted) return;
      final draft = await widget.repository.beginCooking(
        widget.recipe,
        widget.clock(),
        newRound: completed,
      );
      if (!mounted) return;
      final saved = await Navigator.push<CookingOperation>(
        context,
        MaterialPageRoute(
          builder: (_) => RecipeCookingPage(
            recipe: widget.recipe,
            operation: draft,
            inventory: widget.inventory,
            repository: widget.repository,
            clock: widget.clock,
          ),
        ),
      );
      if (!mounted) return;
      await _load();
      if (!mounted || saved == null) return;
      recipeMessage(
        context,
        '먹음 기록 ${saved.recordCount}건을 저장했어요',
        undo: () async {
          try {
            if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
            final restored = await widget.repository.undoCooking(saved.id);
            if (!mounted) return;
            recipeMessage(
              context,
              restored
                  ? '이 조리 회차의 먹음 기록을 모두 되돌렸어요.'
                  : '더 최근 기록이나 재고 변경으로 전체 실행 취소를 할 수 없어요. 기존 기록은 유지했어요.',
            );
            await _load();
          } catch (e) {
            if (mounted) recipeMessage(context, recipeError(e));
          }
        },
      );
    } catch (e) {
      if (mounted) recipeMessage(context, recipeError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _stock(RecipeIngredient ingredient) {
    final current = eligibleRecipeFoods(
      foods,
      widget.clock(),
    ).where((f) => ingredient.foodIds.contains(f.id)).toList();
    if (current.isEmpty) return '연결된 현재 재고 없음 · 다른 보관분은 직접 선택해주세요';
    final amount = current.fold<int>(0, (sum, f) => sum + f.remaining);
    final unit = ingredient.unit ?? current.first.unit;
    return '현재 연결 재고 ${unit.quantityText(amount)} ${unit.label}\n${current.map((f) => '${f.name} · ${dateText(f.expiry)} · ${f.unit.quantityText(f.remaining)} ${f.unit.label}').join('\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ScaffoldMessenger.of(context).removeCurrentSnackBar();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('레시피 상세'),
          actions: [RecipeStar(recipe: recipe, favorites: widget.favorites)],
        ),
        body: loading
            ? const Center(
                child: CircularProgressIndicator(
                  key: ValueKey('recipe-initial-loading'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(Space.lg),
                children: [
                  Text(
                    recipe.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    '예상 ${recipe.minutes}분 · ${recipe.servings}인분 · AI가 제안한 레시피',
                  ),
                  Text('생성 ${dateText(recipe.generatedAt)}'),
                  const SizedBox(height: Space.md),
                  Text(
                    widget.saved
                        ? '저장 당시 레시피예요. 현재 재고와 알레르기 조건을 확인해주세요.'
                        : '추천 당시 재고를 기준으로 해요. 조리 전 현재 보관분과 사용량을 확인해주세요.',
                  ),
                  const SizedBox(height: Space.lg),
                  Text(recipe.reason),
                  if (error != null) Text(error!),
                  const SizedBox(height: Space.xl),
                  Text(
                    '재고 재료와 현재 보관분',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final ingredient in recipe.ingredients.where(
                    (i) => i.kind == RecipeIngredientKind.inventory,
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${ingredient.name} · ${ingredient.displayQuantity}',
                      ),
                      subtitle: Text(_stock(ingredient)),
                    ),
                  if (recipe.ingredients.any(
                    (i) => i.kind == RecipeIngredientKind.staple,
                  )) ...[
                    const SizedBox(height: Space.lg),
                    Text(
                      '확인한 기본 양념',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final ingredient in recipe.ingredients.where(
                      (i) => i.kind == RecipeIngredientKind.staple,
                    ))
                      Text(
                        '${ingredient.name} · ${ingredient.displayQuantity}',
                      ),
                  ],
                  if (recipe.shoppingIngredients.isNotEmpty) ...[
                    const SizedBox(height: Space.lg),
                    Text(
                      '추가 구매 재료',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final ingredient in recipe.shoppingIngredients)
                      Text(
                        '${ingredient.name} · ${ingredient.displayQuantity}',
                      ),
                  ],
                  const SizedBox(height: Space.md),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeShoppingPage(
                          recipe: recipe,
                          repository: widget.repository,
                          clock: widget.clock,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('장보기 항목 확인'),
                  ),
                  const SizedBox(height: Space.xl),
                  Text('조리 순서', style: Theme.of(context).textTheme.titleMedium),
                  for (final step in recipe.steps.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Text('${step.$1 + 1}. ${step.$2}'),
                    ),
                  const SizedBox(height: Space.lg),
                  for (final warning in recipe.warnings) Text('• $warning'),
                  const Text(
                    '제품의 알레르기 표시와 재료 상태·익힘을 직접 확인해주세요. 안전을 보증하는 레시피가 아니에요.',
                  ),
                  const SizedBox(height: Space.lg),
                  if (operation?.state == 'completed')
                    Text('기록 완료 · 먹음 ${operation!.recordCount}건'),
                  const Text('인분을 바꾸려면 조건을 수정하고 다시 추천받아주세요.'),
                  TextButton(
                    onPressed: () {
                      widget.onRecommend();
                      Navigator.pop(context);
                    },
                    child: const Text('이 재료로 다시 추천'),
                  ),
                ],
              ),
        bottomNavigationBar: RecipeBottomAction(
          child: FilledButton(
            onPressed: busy || loading ? null : _cook,
            child: Text(
              busy
                  ? '기록 확인 중…'
                  : operation?.state == 'completed'
                  ? '다시 만들었어요'
                  : '만들었어요 · 사용량 확인',
            ),
          ),
        ),
      ),
    );
  }
}

class _UseRow {
  _UseRow(this.food, int amount)
    : controller = TextEditingController(
        text: amount == 0
            ? '0'
            : recipeEntryUnit(food.unit).quantityText(amount),
      );
  Food food;
  FoodUnit get entryUnit => recipeEntryUnit(food.unit);
  final TextEditingController controller;
  bool unavailable = false;
  int get amount =>
      controller.text.trim() == '0' ||
          controller.text.trim() == '0.0' ||
          controller.text.trim() == '0.00' ||
          controller.text.trim() == '0.000'
      ? 0
      : entryUnit.parseQuantity(controller.text);
}

class RecipeCookingPage extends StatefulWidget {
  const RecipeCookingPage({
    super.key,
    required this.recipe,
    required this.operation,
    required this.inventory,
    required this.repository,
    required this.clock,
  });
  final Recipe recipe;
  final CookingOperation operation;
  final InventoryRepository inventory;
  final RecipeRepository repository;
  final DateTime Function() clock;
  @override
  State<RecipeCookingPage> createState() => _RecipeCookingPageState();
}

class _RecipeCookingPageState extends State<RecipeCookingPage>
    with WidgetsBindingObserver {
  final rows = <_UseRow>[];
  List<Food> current = [];
  bool loading = true, saving = false, stale = false;
  String? error;
  late DateTime draftDay = widget.operation.day;
  Future<void> draftWrites = Future.value();
  Timer? midnight;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final usage in widget.operation.usages) {
      rows.add(_UseRow(usage.food, usage.amount));
    }
    _refresh();
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    midnight?.cancel();
    final now = widget.clock();
    midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        _refresh();
        _scheduleMidnight();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _scheduleMidnight();
    }
  }

  @override
  void dispose() {
    midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final row in rows) {
      row.controller.dispose();
    }
    super.dispose();
  }

  bool _same(Food a, Food b) =>
      a.id == b.id &&
      a.name == b.name &&
      a.remaining == b.remaining &&
      a.unit == b.unit &&
      a.expiry == b.expiry &&
      a.total == b.total &&
      a.price == b.price &&
      a.created == b.created;
  Future<bool> _refresh({bool reconfirm = false}) async {
    try {
      final snapshot = await widget.inventory.load();
      if (!mounted) return true;
      final eligible = eligibleRecipeFoods(snapshot.foods, widget.clock());
      final map = {for (final food in eligible) food.id: food};
      var changed = draftDay != civilDate(widget.clock());
      for (final row in rows) {
        final updated = map[row.food.id];
        if (updated == null || !_same(row.food, updated)) changed = true;
        row.unavailable = updated == null;
        if (reconfirm && updated != null) {
          if (row.food.unit.family != updated.unit.family) {
            row.controller.clear();
          }
          row.food = updated;
        }
      }
      setState(() {
        current = eligible;
        loading = false;
        stale = reconfirm ? false : stale || changed;
        if (changed && !reconfirm) {
          error = '재고 또는 날짜가 바뀌었어요. 입력한 사용량은 유지했어요. 최신 재고를 확인하고 다시 확정해주세요.';
        }
        if (reconfirm) {
          draftDay = civilDate(widget.clock());
          error = '최신 보관분을 반영했어요. 사용량과 남는 양을 확인한 뒤 저장해주세요.';
        }
      });
      if (reconfirm) _persistDraft();
      return changed;
    } catch (e) {
      if (mounted) {
        setState(() {
          error = recipeError(e);
          loading = false;
          stale = true;
        });
      }
      return true;
    }
  }

  List<RecipeUsage> _usages({bool requirePositive = false}) {
    final usages = <RecipeUsage>[];
    for (final row in rows) {
      final amount = row.amount;
      require(
        amount <= row.food.remaining,
        '${row.food.name}의 현재 재고 이하로 입력해주세요.',
      );
      require(
        !row.unavailable || amount == 0,
        '${row.food.name}의 연결 재고가 없어요. 0으로 제외하거나 재료를 직접 바꿔주세요.',
      );
      if (!row.unavailable) {
        usages.add(RecipeUsage(food: row.food, amount: amount));
      }
    }
    if (requirePositive) {
      require(usages.any((u) => u.amount > 0), '양수 사용량을 한 항목 이상 입력해주세요.');
    }
    return usages;
  }

  void _persistDraft() {
    if (loading || stale || saving) return;
    List<RecipeUsage> usages;
    try {
      usages = _usages();
    } catch (_) {
      return;
    }
    final today = draftDay;
    draftWrites = draftWrites
        .then((_) async {
          await widget.repository.saveCookingDraft(
            widget.operation.id,
            usages,
            today,
          );
        })
        .catchError((Object e) {
          if (mounted) {
            setState(() {
              stale = true;
              error = recipeError(e);
            });
          }
        });
  }

  Future<void> _save() async {
    if (saving || stale) return;
    List<RecipeUsage> usages;
    try {
      usages = _usages(requirePositive: true);
    } catch (e) {
      setState(() => error = recipeError(e));
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await draftWrites;
      final latest = await widget.repository.latestCooking(widget.recipe.id);
      if (!mounted) return;
      if (latest?.id == widget.operation.id && latest?.state == 'completed') {
        Navigator.pop(context, latest);
        return;
      }
      if (await _refresh() || stale || !mounted) return;
      await widget.repository.saveCookingDraft(
        widget.operation.id,
        usages,
        widget.clock(),
      );
      await widget.repository.completeCooking(
        widget.operation.id,
        usages,
        widget.clock(),
      );
      final completed = await widget.repository.latestCooking(widget.recipe.id);
      if (mounted) Navigator.pop(context, completed);
    } catch (e) {
      // A reopened screen checks the same operation before offering any save.
      if (!mounted) return;
      setState(() => error = recipeError(e));
      await _refresh();
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _add() async {
    await _refresh();
    if (!mounted) return;
    final already = rows.map((r) => r.food.id).toSet();
    final candidates = current.where((f) => !already.contains(f.id)).toList();
    final chosen = await showDialog<Food>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('현재 재고에서 직접 선택'),
        content: SizedBox(
          width: double.maxFinite,
          child: candidates.isEmpty
              ? const Text('추가할 사용 가능한 보관분이 없어요.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final food in candidates)
                      ListTile(
                        title: Text(food.name),
                        subtitle: Text(
                          '${food.unit.quantityText(food.remaining)} ${food.unit.label} · ${dateText(food.expiry)}',
                        ),
                        onTap: () => Navigator.pop(context, food),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    if (!mounted || chosen == null) return;
    setState(() => rows.add(_UseRow(chosen, 0)));
    _persistDraft();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('사용량 확인')),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                key: ValueKey('recipe-initial-loading'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(Space.lg),
              children: [
                Text(
                  widget.recipe.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  '실제 조리에 사용한 양을 먹음 기록으로 저장해요. 사용하지 않은 재료는 0으로 입력해주세요.',
                ),
                const SizedBox(height: Space.md),
                const Text(
                  '재고에서 확인되지 않은 재료는 이번 기록에 반영되지 않아요. 다른 보관분은 직접 선택해야 하며 자동으로 대체하지 않아요.',
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.md),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (stale)
                  OutlinedButton(
                    onPressed: saving ? null : () => _refresh(reconfirm: true),
                    child: const Text('최신 재고 확인 · 다시 확정'),
                  ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(Space.lg),
                    child: Text('연결된 현재 재고가 없어요. 실제 사용한 등록 재료를 직접 추가해주세요.'),
                  ),
                for (final row in rows) _row(row),
                OutlinedButton.icon(
                  onPressed: saving ? null : _add,
                  icon: const Icon(Icons.add),
                  label: const Text('재료 바꾸기/추가'),
                ),
                const SizedBox(height: Space.lg),
                const Text(
                  '여러 재료는 모두 함께 저장해요. 한 재료라도 변경되면 부분 저장 없이 다시 확인해요. 완성 음식이나 실제 섭취량의 별도 재고는 만들지 않아요.',
                ),
                if (saving)
                  const LinearProgressIndicator(key: ValueKey('recipe-saving')),
              ],
            ),
      bottomNavigationBar: RecipeBottomAction(
        child: FilledButton(
          key: const ValueKey('recipe-cooking-save'),
          onPressed: saving || stale || loading ? null : _save,
          child: Text(saving ? '전체 기록 저장 중…' : '확인한 사용량으로 먹음 기록 저장'),
        ),
      ),
    ),
  );
  Widget _row(_UseRow row) {
    String? invalid;
    int? remaining;
    try {
      final amount = row.amount;
      if (amount > row.food.remaining) {
        invalid = '현재 재고 이하로 입력해주세요.';
      } else if (row.unavailable && amount > 0) {
        invalid = '현재 사용 가능한 연결 재고가 없어요. 0으로 제외해주세요.';
      } else {
        remaining = row.food.remaining - amount;
      }
    } catch (_) {
      invalid = '0 또는 유효한 수량을 입력해주세요.';
    }
    final updated = current.where((f) => f.id == row.food.id).firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    row.food.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '${row.food.name} 이번 기록에서 제외',
                  onPressed: saving
                      ? null
                      : () {
                          setState(() => rows.remove(row));
                          _persistDraft();
                          row.controller.dispose();
                        },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text('소비기한 ${dateText(row.food.expiry)} · 보관분별 기록'),
            Text(
              row.unavailable
                  ? '현재 사용 가능한 재고 없음'
                  : '현재 재고 ${row.food.unit.quantityText(updated?.remaining ?? row.food.remaining)} ${row.food.unit.label}',
            ),
            const SizedBox(height: Space.md),
            TextField(
              key: ValueKey('recipe-use-${row.food.id}'),
              controller: row.controller,
              enabled: !saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '실제 사용량 (${row.entryUnit.label})',
                errorText: invalid,
              ),
              onChanged: (_) {
                setState(() {});
                _persistDraft();
              },
            ),
            if (remaining != null && !stale && !row.unavailable)
              Text(
                '저장 후 ${row.food.unit.quantityText(remaining)} ${row.food.unit.label} 남아요',
              ),
          ],
        ),
      ),
    );
  }
}
