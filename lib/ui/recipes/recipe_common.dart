import 'package:flutter/material.dart';

import '../../data/recipe_repository.dart';
import '../../domain/recipes.dart';
import '../../domain/inventory.dart';
import '../design_system.dart';

FoodUnit recipeEntryUnit(FoodUnit unit) => switch (unit) {
  FoodUnit.kilogram => FoodUnit.gram,
  FoodUnit.litre => FoodUnit.ml,
  _ => unit,
};

String recipeError(Object error) {
  if (error is ArgumentError) {
    return error.message?.toString() ?? '입력값을 확인해주세요.';
  }
  if (error is StateError) return error.message;
  return '기기에 저장하지 못했어요. 입력을 유지했으니 다시 확인해주세요.';
}

void recipeMessage(BuildContext context, String message, {VoidCallback? undo}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: undo == null
            ? null
            : SnackBarAction(label: '실행 취소', onPressed: undo),
      ),
    );
}

Future<bool> recipeConfirm(
  BuildContext context,
  String title,
  String message, {
  String action = '확인',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class RecipeFavorites extends ChangeNotifier {
  RecipeFavorites(this.repository);
  final RecipeRepository repository;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  List<Recipe> recipes = [];
  final Set<String> busy = {};
  bool has(String id) => recipes.any((r) => r.id == id);
  Future<void> load() async {
    recipes = await repository.loadFavorites();
    _notify();
  }

  Future<void> toggle(BuildContext context, Recipe recipe) async {
    if (!busy.add(recipe.id)) return;
    _notify();
    final removing = has(recipe.id);
    try {
      final savedAt = removing
          ? await repository.favoriteSavedAt(recipe.id)
          : null;
      await repository.setFavorite(recipe, !removing);
      await load();
      if (!context.mounted ||
          _disposed ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      recipeMessage(
        context,
        removing ? '즐겨찾기에서 해제했어요' : '즐겨찾기에 추가했어요',
        undo: !removing
            ? null
            : () async {
                if (_disposed) return;
                if (!busy.add(recipe.id)) return;
                _notify();
                try {
                  await repository.restoreFavorite(
                    recipe,
                    savedAt ?? recipe.generatedAt,
                  );
                  await load();
                } catch (error) {
                  if (context.mounted) {
                    recipeMessage(context, recipeError(error));
                  }
                } finally {
                  busy.remove(recipe.id);
                  _notify();
                }
              },
      );
    } catch (error) {
      if (context.mounted) recipeMessage(context, recipeError(error));
    } finally {
      busy.remove(recipe.id);
      _notify();
    }
  }
}

class RecipeStar extends StatelessWidget {
  const RecipeStar({super.key, required this.recipe, required this.favorites});
  final Recipe recipe;
  final RecipeFavorites favorites;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: favorites,
    builder: (context, _) {
      final selected = favorites.has(recipe.id);
      return Semantics(
        toggled: selected,
        child: IconButton(
          tooltip: '${recipe.title} 즐겨찾기 ${selected ? '해제' : '추가'}',
          onPressed: favorites.busy.contains(recipe.id)
              ? null
              : () => favorites.toggle(context, recipe),
          icon: Icon(selected ? Icons.star_rounded : Icons.star_border_rounded),
        ),
      );
    },
  );
}

class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.recipe,
    required this.favorites,
    required this.onOpen,
  });
  final Recipe recipe;
  final RecipeFavorites favorites;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextButton(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    recipe.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              RecipeStar(recipe: recipe, favorites: favorites),
            ],
          ),
          Text('예상 ${recipe.minutes}분 · ${recipe.servings}인분'),
          const SizedBox(height: Space.sm),
          Text(
            recipe.ingredients
                .map((i) => '${i.name} ${i.displayQuantity}')
                .join(' · '),
          ),
          const SizedBox(height: Space.sm),
          Text(recipe.reason),
          Text('추가 구매 ${recipe.shoppingIngredients.length}종'),
          TextButton(onPressed: onOpen, child: const Text('조리법 보기')),
        ],
      ),
    ),
  );
}

class RecipeBottomAction extends StatelessWidget {
  const RecipeBottomAction({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.lg,
          Space.sm,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
      ),
    ),
  );
}
