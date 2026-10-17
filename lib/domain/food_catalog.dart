import 'inventory.dart';

enum FoodVisual {
  milk,
  egg,
  carrot,
  potato,
  onion,
  cucumber,
  greens,
  fruit,
  banana,
  tofu,
  mushroom,
  meat,
  bread,
  rice,
  yogurt,
  grocery,
}

enum SuggestionOrigin { history, product, ingredient }

String normalizeFoodName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), '').trim();

class FoodSuggestion {
  const FoodSuggestion({
    required this.id,
    required this.name,
    required this.unit,
    required this.amount,
    required this.visual,
    required this.origin,
    this.aliases = const [],
  });
  final String id, name;
  final FoodUnit unit;
  final int amount;
  final FoodVisual visual;
  final SuggestionOrigin origin;
  final List<String> aliases;
  FoodUnit get inputUnit => switch (unit) {
    FoodUnit.litre when amount % 1000 != 0 => FoodUnit.ml,
    FoodUnit.kilogram when amount % 1000 != 0 => FoodUnit.gram,
    _ => unit,
  };
  String get quantityLabel => '${unit.quantityText(amount)} ${unit.label}';
  String get sourceLabel => switch (origin) {
    SuggestionOrigin.history => '이전 등록',
    SuggestionOrigin.product => '대표 상품',
    SuggestionOrigin.ingredient => '기본 입력량',
  };
}

// Product sizes are sourced in docs/AUTOCOMPLETE.md. Generic amounts are
// editable starting quantities, not claims about a particular package.
const foodCatalog = <FoodSuggestion>[
  FoodSuggestion(
    id: 'seoul-lowfat-1l',
    name: '서울우유 나100% 저지방우유',
    unit: FoodUnit.litre,
    amount: 1000000,
    visual: FoodVisual.milk,
    origin: SuggestionOrigin.product,
    aliases: ['서울 우유', '서울 저지방', '저지방우유'],
  ),
  FoodSuggestion(
    id: 'seoul-lowfat-500ml',
    name: '서울우유 나100% 저지방우유',
    unit: FoodUnit.ml,
    amount: 500000,
    visual: FoodVisual.milk,
    origin: SuggestionOrigin.product,
    aliases: ['서울 우유', '서울 저지방', '저지방우유'],
  ),
  FoodSuggestion(
    id: 'seoul-lowfat-200ml',
    name: '서울우유 나100% 저지방우유',
    unit: FoodUnit.ml,
    amount: 200000,
    visual: FoodVisual.milk,
    origin: SuggestionOrigin.product,
    aliases: ['서울 우유', '서울 저지방', '저지방우유'],
  ),
  FoodSuggestion(
    id: 'milk',
    name: '우유',
    unit: FoodUnit.litre,
    amount: 1000000,
    visual: FoodVisual.milk,
    origin: SuggestionOrigin.ingredient,
    aliases: ['흰우유', 'milk'],
  ),
  FoodSuggestion(
    id: 'eggs',
    name: '달걀',
    unit: FoodUnit.piece,
    amount: 10000,
    visual: FoodVisual.egg,
    origin: SuggestionOrigin.ingredient,
    aliases: ['계란', 'egg'],
  ),
  FoodSuggestion(
    id: 'tofu',
    name: '두부',
    unit: FoodUnit.gram,
    amount: 300000,
    visual: FoodVisual.tofu,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'carrot',
    name: '당근',
    unit: FoodUnit.piece,
    amount: 1000,
    visual: FoodVisual.carrot,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'potato',
    name: '감자',
    unit: FoodUnit.gram,
    amount: 500000,
    visual: FoodVisual.potato,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'onion',
    name: '양파',
    unit: FoodUnit.piece,
    amount: 1000,
    visual: FoodVisual.onion,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'scallion',
    name: '대파',
    unit: FoodUnit.gram,
    amount: 100000,
    visual: FoodVisual.greens,
    origin: SuggestionOrigin.ingredient,
    aliases: ['파'],
  ),
  FoodSuggestion(
    id: 'lettuce',
    name: '상추',
    unit: FoodUnit.gram,
    amount: 100000,
    visual: FoodVisual.greens,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'cabbage',
    name: '양배추',
    unit: FoodUnit.piece,
    amount: 1000,
    visual: FoodVisual.greens,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'apple',
    name: '사과',
    unit: FoodUnit.piece,
    amount: 1000,
    visual: FoodVisual.fruit,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'banana',
    name: '바나나',
    unit: FoodUnit.piece,
    amount: 1000,
    visual: FoodVisual.banana,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'tomato',
    name: '토마토',
    unit: FoodUnit.piece,
    amount: 1000,
    visual: FoodVisual.fruit,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'cucumber',
    name: '오이',
    unit: FoodUnit.piece,
    amount: 1000,
    visual: FoodVisual.cucumber,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'mushroom',
    name: '새송이버섯',
    unit: FoodUnit.gram,
    amount: 150000,
    visual: FoodVisual.mushroom,
    origin: SuggestionOrigin.ingredient,
    aliases: ['버섯'],
  ),
  FoodSuggestion(
    id: 'chicken',
    name: '닭가슴살',
    unit: FoodUnit.gram,
    amount: 300000,
    visual: FoodVisual.meat,
    origin: SuggestionOrigin.ingredient,
    aliases: ['닭고기'],
  ),
  FoodSuggestion(
    id: 'pork',
    name: '돼지고기',
    unit: FoodUnit.gram,
    amount: 300000,
    visual: FoodVisual.meat,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'rice',
    name: '쌀',
    unit: FoodUnit.kilogram,
    amount: 1000000,
    visual: FoodVisual.rice,
    origin: SuggestionOrigin.ingredient,
  ),
  FoodSuggestion(
    id: 'yogurt',
    name: '플레인 요거트',
    unit: FoodUnit.gram,
    amount: 100000,
    visual: FoodVisual.yogurt,
    origin: SuggestionOrigin.ingredient,
    aliases: ['요구르트', '요거트'],
  ),
  FoodSuggestion(
    id: 'bread',
    name: '식빵',
    unit: FoodUnit.piece,
    amount: 6000,
    visual: FoodVisual.bread,
    origin: SuggestionOrigin.ingredient,
    aliases: ['빵'],
  ),
];

FoodVisual foodVisualForName(String name) {
  final normalized = normalizeFoodName(name);
  if (normalized.isEmpty) return FoodVisual.grocery;
  for (final item in foodCatalog) {
    if (normalizeFoodName(item.name) == normalized ||
        item.aliases.any((alias) => normalizeFoodName(alias) == normalized)) {
      return item.visual;
    }
  }
  // Generic ingredient illustrations only; never infer a branded SKU.
  for (final item in foodCatalog.where(
    (item) => item.origin == SuggestionOrigin.ingredient,
  )) {
    if (normalized.contains(normalizeFoodName(item.name))) return item.visual;
  }
  return FoodVisual.grocery;
}

class _SearchEntry {
  _SearchEntry(this.item)
    : name = normalizeFoodName(item.name),
      aliases = item.aliases.map(normalizeFoodName).toList(growable: false);
  final FoodSuggestion item;
  final String name;
  final List<String> aliases;
  int? match(String query) {
    if (name == query) return 0;
    if (name.startsWith(query)) return 1;
    if (aliases.any((alias) => alias.startsWith(query))) return 2;
    if (name.contains(query) || aliases.any((alias) => alias.contains(query))) {
      return 3;
    }
    return null;
  }
}

class FoodSuggestionIndex {
  FoodSuggestionIndex({
    Iterable<Food> history = const [],
    Iterable<FoodSuggestion> catalog = foodCatalog,
  }) {
    final seen = <String>{};
    final catalogue = catalog.toList(growable: false);
    final choices = [
      for (final food in history.take(200))
        FoodSuggestion(
          id: 'history-${food.id}',
          name: food.name,
          unit: food.unit,
          amount: food.total,
          visual: foodVisualForName(food.name),
          origin: SuggestionOrigin.history,
          aliases: [
            for (final item in catalogue)
              if (normalizeFoodName(item.name) == normalizeFoodName(food.name))
                ...item.aliases,
          ],
        ),
      ...catalogue,
    ];
    for (final item in choices) {
      final key =
          '${normalizeFoodName(item.name)}|${item.unit.family}|${item.amount}';
      if (seen.add(key)) _entries.add(_SearchEntry(item));
    }
  }
  final _entries = <_SearchEntry>[];

  List<FoodSuggestion> search(String text, {int limit = 5}) {
    if (limit <= 0) return const [];
    final query = normalizeFoodName(text);
    if (query.isEmpty) return const [];
    final matches = <({int rank, int order, FoodSuggestion item})>[];
    for (var i = 0; i < _entries.length; i++) {
      final rank = _entries[i].match(query);
      if (rank != null) {
        matches.add((rank: rank, order: i, item: _entries[i].item));
      }
    }
    matches.sort((a, b) {
      final rank = a.rank.compareTo(b.rank);
      return rank == 0 ? a.order.compareTo(b.order) : rank;
    });
    return List.unmodifiable(matches.take(limit).map((match) => match.item));
  }
}
