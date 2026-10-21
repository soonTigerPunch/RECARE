import 'inventory.dart';

class WastedFoodInsight {
  WastedFoodInsight(this.name, this.count, Map<FoodUnit, int> amounts)
    : amounts = Map.unmodifiable(amounts);
  final String name;
  final int count;
  final Map<FoodUnit, int> amounts;
}

class WasteInsights {
  WasteInsights({
    required this.recordCount,
    required this.knownTotal,
    required this.unknownPriceCount,
    required this.unknownReasonCount,
    required Map<WasteReason, int> reasonCounts,
    required List<WastedFoodInsight> topFoods,
    required this.mostCommonReason,
    required this.hint,
  }) : reasonCounts = Map.unmodifiable(reasonCounts),
       topFoods = List.unmodifiable(topFoods);
  final int recordCount, knownTotal, unknownPriceCount, unknownReasonCount;
  final Map<WasteReason, int> reasonCounts;
  final List<WastedFoodInsight> topFoods;
  final WasteReason? mostCommonReason;
  final String hint;
}

WasteInsights buildWasteInsights(WeekSummary week) {
  final reasons = <WasteReason, int>{};
  final counts = <String, int>{};
  final amounts = <String, Map<FoodUnit, int>>{};
  for (final record in week.records) {
    final reason = record.wasteReason;
    if (reason != null) reasons.update(reason, (v) => v + 1, ifAbsent: () => 1);
    counts.update(record.foodName, (v) => v + 1, ifAbsent: () => 1);
    final unit = switch (record.unit.family) {
      'volume' => FoodUnit.ml,
      'weight' => FoodUnit.gram,
      _ => FoodUnit.piece,
    };
    amounts
        .putIfAbsent(record.foodName, () => {})
        .update(unit, (v) => v + record.amount, ifAbsent: () => record.amount);
  }
  WasteReason? common;
  for (final reason in WasteReason.values) {
    if ((reasons[reason] ?? 0) > (reasons[common] ?? 0)) common = reason;
  }
  final foods =
      counts.entries
          .map((e) => WastedFoodInsight(e.key, e.value, amounts[e.key]!))
          .toList()
        ..sort((a, b) {
          final count = b.count.compareTo(a.count);
          return count == 0 ? a.name.compareTo(b.name) : count;
        });
  final hint = week.records.isEmpty
      ? '이번 주에는 기록된 폐기가 없어요.'
      : switch (common) {
          WasteReason.tooMuch => '다음 장보기에는 구매 수량을 조금 줄여보세요.',
          WasteReason.forgot => '소비기한이 가까운 재료를 먼저 보이는 곳에 두세요.',
          WasteReason.disliked => '새로운 식재료는 작은 수량부터 구매해보세요.',
          WasteReason.other => '폐기한 상황을 살펴보고 다음 구매량을 조절해보세요.',
          null => '폐기 이유를 기록하면 다음 장보기 계획에 도움이 돼요.',
        };
  return WasteInsights(
    recordCount: week.records.length,
    knownTotal: week.knownTotal,
    unknownPriceCount: week.unknownCount,
    unknownReasonCount: week.records.where((r) => r.wasteReason == null).length,
    reasonCounts: reasons,
    topFoods: foods,
    mostCommonReason: common,
    hint: hint,
  );
}
